import 'package:cloud_firestore/cloud_firestore.dart';
import '../repositories/privacy_repository.dart';

class FirestorePrivacyRepository implements PrivacyRepository {
  FirestorePrivacyRepository(this.db);
  final FirebaseFirestore db;
  DocumentReference<Map<String, dynamic>> _ref(String uid) =>
      db.collection('users').doc(uid).collection('preferences').doc('privacy');
  @override
  Future<bool> silentDefault(String uid) async =>
      (await _ref(uid)
              .get(const GetOptions(source: Source.server))
              .timeout(const Duration(seconds: 10)))
          .data()?['silent'] ==
      true;
  @override
  Future<void> setSilentDefault(String uid, bool value) async {
    try {
      await _ref(
        uid,
      ).set({'silent': value}).timeout(const Duration(seconds: 15));
    } on Object {
      if (await silentDefault(uid) != value) rethrow;
    }
  }
}
