import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/place_list.dart';
import '../repositories/lists_repository.dart';

class FirestoreListsRepository implements ListsRepository {
  FirestoreListsRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final FirebaseFirestore _db;
  final DateTime Function() _clock;

  DocumentReference<Map<String, dynamic>> _user(String uid) =>
      _db.collection('users').doc(uid);

  CollectionReference<Map<String, dynamic>> _lists(String uid) =>
      _user(uid).collection('lists');

  @override
  String newListId(String uid) => _lists(uid).doc().id;

  @override
  Future<List<PlaceList>> listLists(String uid) async {
    final snap = await _lists(uid).get();
    final now = _clock();
    final out = [
      for (final d in snap.docs)
        if (_parse(d.id, d.data(), now) case final PlaceList l) l,
    ];
    out.sort((a, b) {
      final byDate = a.createdAt.compareTo(b.createdAt);
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });
    return out;
  }

  @override
  Future<List<PlaceList>> listVisibleLists(String ownerUid) async {
    // O filtro é obrigatório: as Rules só liberam a consulta do seguidor
    // que prova `visible == true`.
    final QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await _lists(ownerUid).where('visible', isEqualTo: true).get();
    } on FirebaseException catch (e, stack) {
      // Quem não segue a dona (ou deixou de seguir): negado pelas Rules.
      if (e.code == 'permission-denied') {
        Error.throwWithStackTrace(const ListAccessDeniedException(), stack);
      }
      rethrow;
    }
    final now = _clock();
    final out = [
      for (final d in snap.docs)
        if (_parse(d.id, d.data(), now) case final PlaceList l) l,
    ];
    out.sort((a, b) {
      final byDate = a.createdAt.compareTo(b.createdAt);
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });
    return out;
  }

  static PlaceList? _parse(String id, Map<String, dynamic> data, DateTime now) {
    final name = data['name'];
    if (name is! String) return null;
    final emoji = data['emoji'];
    final ids = data['placeIds'];
    final fromUid = data['copiedFromUid'];
    final fromName = data['copiedFromName'];
    final fromList = data['copiedFromListId'];
    return PlaceList(
      id: id,
      name: name,
      emoji: emoji is String ? emoji : null,
      placeIds: [
        if (ids is List)
          for (final p in ids)
            if (p is String) p,
      ],
      // Escrita local ainda sem o timestamp do servidor: acabou de criar.
      createdAt: switch (data['createdAt']) {
        final Timestamp ts => ts.toDate(),
        _ => now,
      },
      // Listas anteriores ao F13 não têm a chave: privadas.
      visible: data['visible'] == true,
      copiedFrom: fromUid is String && fromName is String && fromList is String
          ? ListCredit(uid: fromUid, name: fromName, listId: fromList)
          : null,
    );
  }

  @override
  Future<void> createList({
    required String uid,
    required String listId,
    required String name,
    required String? emoji,
    required List<String> placeIds,
    ListCredit? copiedFrom,
  }) {
    // Schema exato validado pelas Rules (o trio do crédito vem junto ou não
    // vem; `visible` ausente = privada).
    return _lists(uid).doc(listId).set({
      'name': name,
      'emoji': emoji,
      'placeIds': placeIds,
      if (copiedFrom != null) ...{
        'copiedFromUid': copiedFrom.uid,
        'copiedFromName': copiedFrom.name,
        'copiedFromListId': copiedFrom.listId,
      },
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> setVisible({
    required String uid,
    required String listId,
    required bool visible,
  }) {
    return _lists(uid).doc(listId).update({
      'visible': visible,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  CollectionReference<Map<String, dynamic>> _copies(
    String ownerUid,
    String listId,
  ) => _lists(ownerUid).doc(listId).collection('copies');

  @override
  Future<int> copyCount({
    required String ownerUid,
    required String listId,
  }) async {
    final snap = await _copies(ownerUid, listId).count().get();
    return snap.count ?? 0;
  }

  @override
  Future<void> recordCopy({
    required String ownerUid,
    required String listId,
    required String copierUid,
  }) async {
    // Direto, sem ler antes: offline a escrita entra na fila do SDK e
    // sincroniza depois. Já registrada (2ª cópia), o set vira update e as
    // Rules negam: é o "uma por pessoa", não um erro.
    try {
      await _copies(
        ownerUid,
        listId,
      ).doc(copierUid).set({'createdAt': FieldValue.serverTimestamp()});
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
    }
  }

  @override
  Future<void> updateList({
    required String uid,
    required String listId,
    required String name,
    required String? emoji,
  }) {
    return _lists(uid).doc(listId).update({
      'name': name,
      'emoji': emoji,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Máximo de escritas num batch do Firestore.
  static const int maxBatchWrites = 500;

  @override
  Future<void> deleteList({required String uid, required String listId}) async {
    // O contador de cópias (F13) sai junto: no mesmo batch da lista. Com
    // mais de 499 cópias, as excedentes saem antes, em batches próprios.
    final copies = (await _copies(uid, listId).get()).docs;
    final last = maxBatchWrites - 1;
    final early = copies.length > last ? copies.length - last : 0;
    for (var i = 0; i < early; i += maxBatchWrites) {
      final batch = _db.batch();
      for (final d in copies.sublist(i, (i + maxBatchWrites).clamp(0, early))) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
    final batch = _db.batch();
    for (final d in copies.sublist(early)) {
      batch.delete(d.reference);
    }
    batch.delete(_lists(uid).doc(listId));
    await batch.commit();
  }

  @override
  Future<void> setMembership({
    required String uid,
    required String listId,
    required String placeId,
    required bool member,
  }) {
    return _lists(uid).doc(listId).update({
      'placeIds': member
          ? FieldValue.arrayUnion([placeId])
          : FieldValue.arrayRemove([placeId]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> removeEverywhere({
    required String uid,
    required String placeId,
    required Iterable<String> listIds,
  }) {
    final batch = _db.batch()
      ..delete(_user(uid).collection('saved').doc(placeId));
    for (final id in listIds) {
      batch.update(_lists(uid).doc(id), {
        'placeIds': FieldValue.arrayRemove([placeId]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    return batch.commit();
  }
}
