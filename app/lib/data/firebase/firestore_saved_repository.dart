import 'package:cloud_firestore/cloud_firestore.dart';

import '../repositories/saved_repository.dart';

class FirestoreSavedRepository implements SavedRepository {
  FirestoreSavedRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final FirebaseFirestore _db;
  final DateTime Function() _clock;

  CollectionReference<Map<String, dynamic>> _saved(String uid) =>
      _db.collection('users').doc(uid).collection('saved');

  @override
  Future<List<SavedPlace>> listSaved(String uid) async {
    final snap = await _saved(uid).orderBy('createdAt', descending: true).get();
    final now = _clock();
    final out = [
      for (final d in snap.docs)
        SavedPlace(
          placeId: d.id,
          // Escrita local ainda sem o timestamp do servidor: acabou de salvar.
          savedAt: switch (d.data()['createdAt']) {
            final Timestamp ts => ts.toDate(),
            _ => now,
          },
        ),
    ];
    out.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return out;
  }

  @override
  Future<void> save({required String uid, required String placeId}) {
    // Schema exato validado pelas Rules: só `createdAt` = request.time.
    return _saved(
      uid,
    ).doc(placeId).set({'createdAt': FieldValue.serverTimestamp()});
  }

  @override
  Future<DateTime?> savedAtOf({
    required String uid,
    required String placeId,
  }) async {
    final snap = await _saved(uid).doc(placeId).get();
    if (!snap.exists) return null;
    return switch (snap.data()?['createdAt']) {
      final Timestamp ts => ts.toDate(),
      _ => _clock(),
    };
  }

  @override
  Future<void> remove({required String uid, required String placeId}) {
    return _saved(uid).doc(placeId).delete();
  }
}
