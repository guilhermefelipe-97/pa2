import 'package:cloud_firestore/cloud_firestore.dart';
import '../repositories/owner_repository.dart';

class FirestoreOwnerRepository implements OwnerRepository {
  FirestoreOwnerRepository(this.db);
  final FirebaseFirestore db;
  @override
  Future<String?> ownerOf(String placeId) async =>
      (await db
                  .collection('placeOwners')
                  .doc(placeId)
                  .get(const GetOptions(source: Source.server)))
              .data()?['uid']
          as String?;
  CollectionReference<Map<String, dynamic>> _requests(String uid) =>
      db.collection('users').doc(uid).collection('ownershipRequests');
  @override
  Future<List<OwnershipRequest>> requestsOf(String uid) async =>
      (await _requests(uid).get(const GetOptions(source: Source.server))).docs
          .map((d) => OwnershipRequest(d.id, d.data()['status'] as String))
          .toList();
  @override
  Future<OwnershipRequest> request(String uid, String placeId) async {
    final ref = _requests(uid).doc(placeId);
    final old = await ref.get(const GetOptions(source: Source.server));
    if (old.exists) {
      return OwnershipRequest(placeId, old.data()!['status'] as String);
    }
    try {
      await ref.set({
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on Object {
      final raced = await ref.get(const GetOptions(source: Source.server));
      if (!raced.exists) rethrow;
      return OwnershipRequest(placeId, raced.data()!['status'] as String);
    }
    return OwnershipRequest(placeId, 'pending');
  }
}
