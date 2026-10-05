import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/user_profile.dart';
import '../repositories/user_repository.dart';

class FirestoreUserRepository implements UserRepository {
  FirestoreUserRepository(this._db);

  final FirebaseFirestore _db;

  /// Maior code point do BMP de uso privado: fecha a faixa da busca por prefixo.
  static const String _prefixUpperBound = '\uf8ff';

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');

  @override
  Future<void> createProfile({
    required String uid,
    required String displayName,
  }) {
    final name = UserProfile.normalizeName(displayName);
    return _users.doc(uid).set({
      'displayName': name,
      'displayNameLower': name.toLowerCase(),
    });
  }

  @override
  Future<UserProfile?> getProfile(String uid) async {
    final snap = await _users.doc(uid).get();
    final data = snap.data();
    if (data == null) return null;
    return UserProfile(
      uid: snap.id,
      displayName: data['displayName'] as String,
    );
  }

  @override
  Future<List<UserProfile>> searchByName(String query, {int limit = 20}) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    final snap = await _users
        .where('displayNameLower', isGreaterThanOrEqualTo: q)
        .where('displayNameLower', isLessThan: '$q$_prefixUpperBound')
        .orderBy('displayNameLower')
        .limit(limit)
        .get();
    return snap.docs
        .map(
          (d) => UserProfile(
            uid: d.id,
            displayName: d.data()['displayName'] as String,
          ),
        )
        .toList();
  }

  @override
  Future<Set<String>> getFollowing(String uid) async {
    final snap = await _users.doc(uid).collection('following').get();
    return snap.docs.map((d) => d.id).toSet();
  }

  @override
  Future<void> follow({required String uid, required String targetUid}) {
    return _users.doc(uid).collection('following').doc(targetUid).set({
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> unfollow({required String uid, required String targetUid}) {
    return _users.doc(uid).collection('following').doc(targetUid).delete();
  }
}
