import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../domain/models/place.dart';
import '../../domain/queue_status.dart';
import '../repositories/queue_repository.dart';
import 'audit_log.dart';
import 'place_doc.dart';

/// Relatos identificados de espera (F29) no Firestore. Mesmo padrão de batch do
/// F15 (`FirestoreVisitRepository`): local descoberto + relato + trava,
/// timeout de 15 s, ack perdido verificado e corrida na criação do local.
class FirestoreQueueRepository implements QueueRepository {
  FirestoreQueueRepository(
    this._db, {
    this.commitTimeout = defaultCommitTimeout,
    DateTime Function()? clock,
    @visibleForTesting Future<void> Function(WriteBatch batch)? commitBatch,
  }) : _clock = clock ?? DateTime.now,
       _commitBatch = commitBatch ?? ((batch) => batch.commit());

  final FirebaseFirestore _db;
  final DateTime Function() _clock;
  final Future<void> Function(WriteBatch batch) _commitBatch;

  static const Duration defaultCommitTimeout = Duration(seconds: 15);

  /// Sem resposta do commit neste prazo: trata como ack perdido.
  final Duration commitTimeout;

  static const String reportsCollection = 'queueReports';
  final _pending = <String, _QueueAttempt>{};

  /// Subcoleção das travas do F29: `users/{uid}/queueReportLocks/{placeId}`.
  static const String locksCollection = 'queueReportLocks';

  CollectionReference<Map<String, dynamic>> get _reports =>
      _db.collection(reportsCollection);

  DocumentReference<Map<String, dynamic>> _lockRef(
    String uid,
    String placeId,
  ) =>
      _db.collection('users').doc(uid).collection(locksCollection).doc(placeId);

  @override
  Future<DateTime?> queueReportLockOf(String uid, String placeId) async {
    final snap = await _lockRef(
      uid,
      placeId,
    ).get(const GetOptions(source: Source.server)).timeout(commitTimeout);
    final lastAt = snap.data()?['lastAt'];
    return lastAt is Timestamp ? lastAt.toDate() : null;
  }

  @override
  Future<QueueReceipt?> reconcilePending(String uid, String placeId) async {
    final key = '$uid/$placeId';
    final attempt = _pending[key];
    if (attempt == null) return null;
    final written = await _readAttempt(attempt);
    if (written != null) {
      _pending.remove(key);
      return written;
    }
    if (attempt.inFlight) {
      throw const QueueRecoveryRequired(
        'Envio anterior ainda em confirmação. Atualize para conferir antes de repetir.',
      );
    }
    _pending.remove(key);
    // Ausência confirmada e operação encerrada: permite corrigir o valor.
    // O mesmo ID é guardado somente para um retry real com o mesmo conteúdo.
    return null;
  }

  Future<QueueReceipt?> _readAttempt(_QueueAttempt attempt) async {
    try {
      final snap = await attempt.ref
          .get(const GetOptions(source: Source.server))
          .timeout(commitTimeout);
      final d = snap.data();
      if (d == null) return null;
      return QueueReceipt(
        id: snap.id,
        minutes: d['minutes'] as int,
        createdAt: (d['createdAt'] as Timestamp).toDate(),
        placeCreated: attempt.placeCreated,
        recovered: true,
      );
    } on Object {
      // A trava pode confirmar esta tentativa mesmo se a leitura do relato falhar.
      try {
        final d =
            (await _lockRef(attempt.report.authorId, attempt.report.placeId)
                    .get(const GetOptions(source: Source.server))
                    .timeout(commitTimeout))
                .data();
        if (d?['reportId'] == attempt.ref.id && d?['lastAt'] is Timestamp) {
          return QueueReceipt(
            id: attempt.ref.id,
            minutes: attempt.report.minutes,
            createdAt: (d!['lastAt'] as Timestamp).toDate(),
            placeCreated: attempt.placeCreated,
            recovered: true,
          );
        }
      } on Object {
        /* Leitura desconhecida nunca autoriza duplicar. */
      }
      throw const QueueRecoveryRequired(
        'Não foi possível conferir o envio anterior. Atualize antes de repetir.',
      );
    }
  }

  @override
  Future<QueueReceipt> createReport(
    NewQueueReport report, {
    Place? newPlace,
  }) async {
    if (report.minutes < 0 || report.minutes > 180) {
      throw ArgumentError('espera deve ser 0–180 min');
    }
    if (newPlace != null && newPlace.id != report.placeId) {
      throw ArgumentError('outro local');
    }
    final key = '${report.authorId}/${report.placeId}';
    final old = _pending[key];
    final recovered = await reconcilePending(report.authorId, report.placeId);
    if (recovered != null &&
        _clock().isBefore(recovered.createdAt.add(queueCooldown))) {
      if (recovered.minutes == report.minutes) return recovered;
      throw QueueRecoveryRequired(
        'Envio anterior confirmado: ${recovered.minutes} min. O novo valor não foi enviado.',
      );
    }
    // Depois de 30 min, uma tentativa legítima usa outro documento, ainda que
    // a confirmação do envio antigo só tenha chegado agora.
    final reuse =
        recovered == null &&
        old != null &&
        !old.inFlight &&
        old.report.minutes == report.minutes;
    final attempt = reuse ? old : _QueueAttempt(_reports.doc(), report);
    _pending[key] = attempt;
    final placeRef = newPlace?.discovered == true
        ? _db.collection(placesCollection).doc(newPlace!.id)
        : null;
    attempt.placeCreated =
        placeRef != null &&
        !(await placeRef
                .get(const GetOptions(source: Source.server))
                .timeout(commitTimeout))
            .exists;
    try {
      await _send(attempt, attempt.placeCreated ? newPlace : null);
    } on Object catch (error, stack) {
      final written = await _readAttempt(attempt);
      if (written != null) {
        _pending.remove(key);
        return written;
      }
      if (!attempt.inFlight &&
          attempt.placeCreated &&
          error is FirebaseException &&
          error.code == 'permission-denied' &&
          (await placeRef!
                  .get(const GetOptions(source: Source.server))
                  .timeout(commitTimeout))
              .exists) {
        attempt.placeCreated = false;
        try {
          await _send(attempt, null);
        } on Object {
          final retryWritten = await _readAttempt(attempt);
          if (retryWritten != null) {
            _pending.remove(key);
            return retryWritten;
          }
          rethrow;
        }
      } else {
        Error.throwWithStackTrace(error, stack);
      }
    }
    final written = await _readAttempt(attempt);
    if (written == null) {
      throw const QueueRecoveryRequired(
        'Envio concluído; atualize para conferir o registro.',
      );
    }
    _pending.remove(key);
    return QueueReceipt(
      id: written.id,
      minutes: written.minutes,
      createdAt: written.createdAt,
      placeCreated: written.placeCreated,
    );
  }

  Future<void> _send(_QueueAttempt attempt, Place? place) async {
    attempt.inFlight = true;
    final operation = _commit(attempt.ref, attempt.report, place);
    // timeout não cancela o SDK. Mantém a identidade até a operação real encerrar.
    final settled = operation.then<void>(
      (_) {
        attempt.inFlight = false;
      },
      onError: (Object error, StackTrace stack) {
        attempt.inFlight = false;
        Error.throwWithStackTrace(error, stack);
      },
    );
    await settled.timeout(commitTimeout);
  }

  Future<void> _commit(
    DocumentReference<Map<String, dynamic>> ref,
    NewQueueReport report,
    Place? createPlace,
  ) {
    final batch = _db.batch();
    if (createPlace != null) {
      // Mesmo batch: as Rules do relato exigem o local ao fim dele.
      batch.set(
        _db.collection(placesCollection).doc(createPlace.id),
        newPlaceData(createPlace, uid: report.authorId),
      );
    }
    // Schema exato (5 chaves) validado pelas Rules; hora do servidor.
    batch.set(ref, {
      'authorId': report.authorId,
      'authorName': report.authorName,
      'placeId': report.placeId,
      'minutes': report.minutes,
      'createdAt': FieldValue.serverTimestamp(),
    });
    // F04: entrada de auditoria no mesmo batch (as Rules exigem o par).
    addAuditEntry(
      batch,
      _db,
      collection: reportsCollection,
      docId: ref.id,
      actorUid: report.authorId,
      placeId: report.placeId,
    );
    batch.set(_lockRef(report.authorId, report.placeId), {
      'lastAt': FieldValue.serverTimestamp(),
      'reportId': ref.id,
      'placeId': report.placeId,
    });
    return _commitBatch(batch);
  }

  @override
  Future<List<QueueReport>> fetchForPlace(
    String placeId, {
    required DateTime since,
  }) async {
    final query = _reports
        .where('placeId', isEqualTo: placeId)
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .orderBy('createdAt', descending: true);
    final result = <QueueReport>[];
    QueryDocumentSnapshot<Map<String, dynamic>>? cursor;
    while (true) {
      final page =
          await (cursor == null ? query : query.startAfterDocument(cursor))
              .limit(100)
              .get(const GetOptions(source: Source.server))
              .timeout(commitTimeout);
      result.addAll(page.docs.map(_fromDoc).whereType<QueueReport>());
      if (page.docs.length < 100) return result;
      cursor = page.docs.last;
    }
  }

  /// Documento fora do schema: `null` (ignorado em vez de derrubar a tela).
  static QueueReport? _fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data();
    final ts = d['createdAt'];
    final authorId = d['authorId'];
    final authorName = d['authorName'];
    final placeId = d['placeId'];
    final minutes = d['minutes'];
    if (ts is! Timestamp ||
        authorId is! String ||
        authorName is! String ||
        placeId is! String ||
        (minutes is! int || minutes < 0 || minutes > 180)) {
      return null;
    }
    return QueueReport(
      id: doc.id,
      authorId: authorId,
      authorName: authorName,
      placeId: placeId,
      minutes: minutes,
      createdAt: ts.toDate(),
    );
  }
}

class _QueueAttempt {
  _QueueAttempt(this.ref, this.report);
  final DocumentReference<Map<String, dynamic>> ref;
  final NewQueueReport report;
  bool inFlight = false, placeCreated = false;
}
