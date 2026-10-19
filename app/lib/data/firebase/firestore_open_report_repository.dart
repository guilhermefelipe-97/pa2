import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../domain/models/open_report.dart';
import '../../domain/models/place.dart';
import '../../domain/open_status.dart'
    show openReportsBatchLimit, openReportsPlaceLimit;
import '../chunk.dart';
import '../repositories/open_report_repository.dart';
import 'audit_log.dart';
import 'place_doc.dart';

/// Relatos "Está aberto agora?" (F20) no Firestore. Mesmo padrão de batch do
/// F15 (`FirestoreVisitRepository`): local descoberto + relato + trava,
/// timeout de 15 s, ack perdido verificado e corrida na criação do local.
class FirestoreOpenReportRepository implements OpenReportRepository {
  FirestoreOpenReportRepository(
    this._db, {
    this.commitTimeout = defaultCommitTimeout,
    @visibleForTesting Future<void> Function(WriteBatch batch)? commitBatch,
  }) : _commitBatch = commitBatch ?? ((batch) => batch.commit());

  final FirebaseFirestore _db;
  final Future<void> Function(WriteBatch batch) _commitBatch;

  static const Duration defaultCommitTimeout = Duration(seconds: 15);

  /// Sem resposta do commit neste prazo: trata como ack perdido.
  final Duration commitTimeout;

  static const String reportsCollection = 'openReports';

  /// Subcoleção das travas do F20: `users/{uid}/openReportLocks/{placeId}`.
  static const String locksCollection = 'openReportLocks';

  CollectionReference<Map<String, dynamic>> get _reports =>
      _db.collection(reportsCollection);

  DocumentReference<Map<String, dynamic>> _lockRef(
    String uid,
    String placeId,
  ) =>
      _db.collection('users').doc(uid).collection(locksCollection).doc(placeId);

  @override
  Future<DateTime?> openReportLockOf(String uid, String placeId) async {
    final snap = await _lockRef(
      uid,
      placeId,
    ).get(const GetOptions(source: Source.server));
    final lastAt = snap.data()?['lastAt'];
    return lastAt is Timestamp ? lastAt.toDate() : null;
  }

  @override
  Future<CreateOpenReportResult> createReport(
    NewOpenReport report, {
    Place? newPlace,
  }) async {
    if (newPlace != null && newPlace.id != report.placeId) {
      throw ArgumentError.value(newPlace.id, 'newPlace', 'outro local');
    }
    // Id gerado no cliente: a trava aponta para ele.
    final ref = _reports.doc();
    final placeRef = newPlace != null && newPlace.discovered
        ? _db.collection(placesCollection).doc(newPlace.id)
        : null;
    var createPlace = false;
    if (placeRef != null) {
      try {
        createPlace = !(await placeRef.get()).exists;
      } on Object {
        // Sem ler, tenta criar: se já existir, o batch falha e o ramo de
        // corrida abaixo resolve.
        createPlace = true;
      }
    }
    try {
      await _commit(ref, report, createPlace ? newPlace : null);
      return (placeCreated: createPlace);
    } on Object catch (error, stack) {
      // Ack perdido (ou sem resposta): o batch pode ter sido gravado.
      if (await _written(ref, report)) return (placeCreated: createPlace);
      if (!createPlace) Error.throwWithStackTrace(error, stack);
      // Corrida: o local nasceu entre a leitura e o commit.
      final bool exists;
      try {
        exists = (await placeRef!.get(
          const GetOptions(source: Source.server),
        )).exists;
      } on Object {
        Error.throwWithStackTrace(error, stack);
      }
      if (!exists) Error.throwWithStackTrace(error, stack);
      try {
        await _commit(ref, report, null);
      } on Object catch (retryError, retryStack) {
        if (!await _written(ref, report)) {
          Error.throwWithStackTrace(retryError, retryStack);
        }
      }
      return (placeCreated: false);
    }
  }

  /// O relato [ref] foi gravado? Lê o doc no servidor; se a leitura falha,
  /// lê a trava (só aponta para esta tentativa se o batch foi gravado).
  Future<bool> _written(
    DocumentReference<Map<String, dynamic>> ref,
    NewOpenReport report,
  ) async {
    try {
      return (await ref.get(const GetOptions(source: Source.server))).exists;
    } on Object {
      // Segue para a trava.
    }
    try {
      final lock = await _lockRef(
        report.authorId,
        report.placeId,
      ).get(const GetOptions(source: Source.server));
      return lock.data()?['reportId'] == ref.id;
    } on Object {
      return false;
    }
  }

  Future<void> _commit(
    DocumentReference<Map<String, dynamic>> ref,
    NewOpenReport report,
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
      'open': report.open,
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
    return _commitBatch(batch).timeout(commitTimeout);
  }

  @override
  Future<List<OpenReport>> fetchForPlace(
    String placeId, {
    required DateTime since,
  }) async {
    final snap = await _reports
        .where('placeId', isEqualTo: placeId)
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .orderBy('createdAt', descending: true)
        .limit(openReportsPlaceLimit)
        .get();
    return snap.docs.map(_fromDoc).whereType<OpenReport>().toList();
  }

  @override
  Future<List<OpenReport>> fetchForPlaces(
    List<String> placeIds, {
    required DateTime since,
  }) async {
    final ids = placeIds.toSet().toList();
    if (ids.isEmpty) return const [];
    final snaps = await Future.wait(
      chunked(ids, whereInLimit).map(
        (batch) => _reports
            .where('placeId', whereIn: batch)
            .where(
              'createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(since),
            )
            .orderBy('createdAt', descending: true)
            .limit(openReportsBatchLimit)
            .get(),
      ),
    );
    final out = [
      for (final snap in snaps)
        ...snap.docs.map(_fromDoc).whereType<OpenReport>(),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  /// Documento fora do schema: `null` (ignorado em vez de derrubar a tela).
  static OpenReport? _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final ts = d['createdAt'];
    final authorId = d['authorId'];
    final authorName = d['authorName'];
    final placeId = d['placeId'];
    final open = d['open'];
    if (ts is! Timestamp ||
        authorId is! String ||
        authorName is! String ||
        placeId is! String ||
        open is! bool) {
      return null;
    }
    return OpenReport(
      id: doc.id,
      authorId: authorId,
      authorName: authorName,
      placeId: placeId,
      open: open,
      createdAt: ts.toDate(),
    );
  }
}
