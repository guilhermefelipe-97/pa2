import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/user_profile.dart';
import '../repositories/user_repository.dart';

class FirestoreUserRepository implements UserRepository {
  FirestoreUserRepository(this._db);

  final FirebaseFirestore _db;

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
      username: data['username'] as String? ?? '',
      bio: data['bio'] as String? ?? '',
      city: data['city'] as String? ?? '',
      instagram: data['instagram'] as String? ?? '',
    );
  }

  @override
  Future<List<UserProfile>> searchByName(String query, {int limit = 20}) async {
    final raw = query.trim().toLowerCase();
    final byUsername = raw.startsWith('@');
    final q = byUsername ? raw.substring(1) : raw;
    if (q.isEmpty) return [];
    final field = byUsername ? 'username' : 'displayNameLower';
    final snap = await _users
        .where(field, isGreaterThanOrEqualTo: q)
        .where(field, isLessThan: '$q$_prefixUpperBound')
        .orderBy(field)
        .limit(limit)
        .get();
    return snap.docs
        .map(
          (d) => UserProfile(
            uid: d.id,
            displayName: d.data()['displayName'] as String,
            username: d.data()['username'] as String? ?? '',
            bio: d.data()['bio'] as String? ?? '',
            city: d.data()['city'] as String? ?? '',
            instagram: d.data()['instagram'] as String? ?? '',
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
