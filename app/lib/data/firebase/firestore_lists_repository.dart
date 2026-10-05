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

  static PlaceList? _parse(String id, Map<String, dynamic> data, DateTime now) {
    final name = data['name'];
    if (name is! String) return null;
    final emoji = data['emoji'];
    final ids = data['placeIds'];
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
    );
  }

  @override
  Future<void> createList({
    required String uid,
    required String listId,
    required String name,
    required String? emoji,
    required List<String> placeIds,
  }) {
    // Schema exato validado pelas Rules.
    return _lists(uid).doc(listId).set({
      'name': name,
      'emoji': emoji,
      'placeIds': placeIds,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
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

  @override
  Future<void> deleteList({required String uid, required String listId}) {
    return _lists(uid).doc(listId).delete();
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
