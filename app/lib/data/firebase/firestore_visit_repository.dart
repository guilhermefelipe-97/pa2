import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../domain/models/companion.dart';
import '../../domain/models/place.dart';
import '../../domain/models/visit.dart';
import '../../domain/price_band.dart';
import '../activity_batch.dart';
import '../repositories/visit_repository.dart';
import 'activity_queries.dart' as queries;
import 'audit_log.dart';
import 'place_doc.dart';

class FirestoreVisitRepository implements VisitRepository {
  FirestoreVisitRepository(
    this._db, {
    this.perBatchLimit = defaultPerBatchLimit,
    this.commitTimeout = defaultCommitTimeout,
    @visibleForTesting Future<void> Function(WriteBatch batch)? commitBatch,
  }) : _commitBatch = commitBatch ?? ((batch) => batch.commit());

  final FirebaseFirestore _db;

  /// Envia o batch (nos testes, simula ack perdido ou resposta que não
  /// chega).
  final Future<void> Function(WriteBatch batch) _commitBatch;

  static const Duration defaultCommitTimeout = Duration(seconds: 15);

  /// Sem resposta do commit neste prazo: trata como ack perdido (relê para
  /// saber se a visita foi gravada) em vez de deixar o sheet girando.
  final Duration commitTimeout;

  static const int defaultPerBatchLimit = 100;

  /// Limite por lote na consulta por autores.
  final int perBatchLimit;

  static const String visitsCollection = 'visits';

  /// Subcoleção das travas do F15: `users/{uid}/visitLocks/{placeId}`.
  static const String visitLocksCollection = 'visitLocks';

  CollectionReference<Map<String, dynamic>> get _visits =>
      _db.collection(visitsCollection);

  DocumentReference<Map<String, dynamic>> _lockRef(
    String uid,
    String placeId,
  ) => _db
      .collection('users')
      .doc(uid)
      .collection(visitLocksCollection)
      .doc(placeId);

  @override
  Future<DateTime?> visitLockOf(String uid, String placeId) async {
    // Do servidor: a trava muda fora deste aparelho (outro aparelho, corrida).
    final snap = await _lockRef(
      uid,
      placeId,
    ).get(const GetOptions(source: Source.server));
    final lastAt = snap.data()?['lastAt'];
    return lastAt is Timestamp ? lastAt.toDate() : null;
  }

  @override
  Future<CreateVisitResult> createVisit(
    NewVisit visit, {
    Place? newPlace,
  }) async {
    if (newPlace != null && newPlace.id != visit.placeId) {
      throw ArgumentError.value(newPlace.id, 'newPlace', 'outro local');
    }
    // Id gerado no cliente: a trava aponta para ele.
    final ref = _visits.doc();
    final placeRef = newPlace != null && newPlace.discovered
        ? _db.collection(placesCollection).doc(newPlace.id)
        : null;
    var placeName = visit.placeName;
    var createPlace = false;
    if (placeRef != null) {
      try {
        final existing = await placeRef.get();
        createPlace = !existing.exists;
        placeName = _storedName(existing) ?? placeName;
      } on Object {
        // Sem ler, tenta criar: se já existir, o batch falha e o ramo de
        // corrida abaixo resolve.
        createPlace = true;
      }
    }
    try {
      await _commit(ref, visit, placeName, createPlace ? newPlace : null);
      return (placeCreated: createPlace);
    } on Object catch (error, stack) {
      // Ack perdido (ou sem resposta em [commitTimeout]): o batch pode ter
      // sido gravado. Reenviar com o mesmo id seria negado; o certo é
      // conferir se esta visita existe.
      if (await _written(ref, visit)) return (placeCreated: createPlace);
      if (!createPlace) Error.throwWithStackTrace(error, stack);
      // Corrida: o local nasceu entre a leitura e o commit. Com o doc lá,
      // grava sem ele, com o nome que está gravado.
      final DocumentSnapshot<Map<String, dynamic>> existing;
      try {
        existing = await placeRef!.get(const GetOptions(source: Source.server));
      } on Object {
        Error.throwWithStackTrace(error, stack);
      }
      if (!existing.exists) Error.throwWithStackTrace(error, stack);
      placeName = _storedName(existing) ?? placeName;
      try {
        await _commit(ref, visit, placeName, null);
      } on Object catch (retryError, retryStack) {
        if (!await _written(ref, visit)) {
          Error.throwWithStackTrace(retryError, retryStack);
        }
      }
      return (placeCreated: false);
    }
  }

  /// A visita [ref] foi gravada? Lê o doc no servidor; se a leitura não
  /// decide (falhou), lê a trava: ela só aponta para esta tentativa
  /// (`visitId == ref.id`) se o batch inteiro foi gravado.
  Future<bool> _written(
    DocumentReference<Map<String, dynamic>> ref,
    NewVisit visit,
  ) async {
    final exists = await _existsOnServer(ref);
    if (exists != null) return exists;
    try {
      final lock = await _lockRef(
        visit.authorId,
        visit.placeId,
      ).get(const GetOptions(source: Source.server));
      return lock.data()?['visitId'] == ref.id;
    } on Object {
      return false;
    }
  }

  static String? _storedName(DocumentSnapshot<Map<String, dynamic>> snap) {
    final name = snap.data()?['name'];
    return snap.exists && name is String ? name : null;
  }

  static Future<bool?> _existsOnServer(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    try {
      return (await ref.get(const GetOptions(source: Source.server))).exists;
    } on Object {
      return null;
    }
  }

  Future<void> _commit(
    DocumentReference<Map<String, dynamic>> ref,
    NewVisit visit,
    String placeName,
    Place? createPlace,
  ) {
    final batch = _db.batch();
    if (createPlace != null) {
      // Mesmo batch: as Rules da visita exigem o local ao fim dele.
      batch.set(
        _db.collection(placesCollection).doc(createPlace.id),
        newPlaceData(createPlace, uid: visit.authorId),
      );
    }
    // Schema exato (7 chaves) validado pelas Rules. Sem notas; o período do
    // dia é derivado do createdAt, sempre do servidor. `priceBand` (F27):
    // 1–5 ou null quando não informado.
    batch.set(ref, {
      'authorId': visit.authorId,
      'authorName': visit.authorName,
      'placeId': visit.placeId,
      'placeName': placeName,
      'companion': visit.companion?.value,
      'priceBand': visit.priceBand?.value,
      'createdAt': FieldValue.serverTimestamp(),
    });
    // F04: entrada de auditoria no mesmo batch (as Rules exigem o par).
    addAuditEntry(
      batch,
      _db,
      collection: visitsCollection,
      docId: ref.id,
      actorUid: visit.authorId,
      placeId: visit.placeId,
    );
    // Trava criada/renovada no mesmo batch, apontando para esta visita.
    // Dentro de 12 h as Rules negam a trava e a visita juntas.
    batch.set(_lockRef(visit.authorId, visit.placeId), {
      'lastAt': FieldValue.serverTimestamp(),
      'visitId': ref.id,
      'placeId': visit.placeId,
    });
    return _commitBatch(batch).timeout(commitTimeout);
  }

  @override
  Future<ActivityBatch<Visit>> fetchVisitsByAuthors(
    List<String> authorIds, {
    int? limit,
  }) => queries.fetchLatestByAuthors(
    _visits,
    authorIds,
    perBatchLimit: perBatchLimit,
    fromDoc: _fromDoc,
    limit: limit,
  );

  @override
  Future<List<Visit>> fetchVisitsForPlace(
    String placeId,
    List<String> authorIds,
  ) => queries.fetchForPlace(_visits, placeId, authorIds, fromDoc: _fromDoc);

  /// Documento fora do schema: `null` (ignorado em vez de derrubar o feed).
  static Visit? _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final ts = d['createdAt'];
    final authorId = d['authorId'];
    final authorName = d['authorName'];
    final placeId = d['placeId'];
    final placeName = d['placeName'];
    final companion = d['companion'];
    if (ts is! Timestamp ||
        authorId is! String ||
        authorName is! String ||
        placeId is! String ||
        placeName is! String ||
        (companion != null && companion is! String)) {
      return null;
    }
    final PriceBand? priceBand;
    try {
      priceBand = readPriceBand(d);
    } on FormatException {
      return null;
    }
    return Visit(
      id: doc.id,
      authorId: authorId,
      authorName: authorName,
      placeId: placeId,
      placeName: placeName,
      companion: Companion.fromValue(companion as String?),
      createdAt: ts.toDate(),
      priceBand: priceBand,
    );
  }
}
