import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/food_tags.dart';
import '../repositories/dietary_repository.dart';

class FirestoreDietaryRepository implements DietaryRepository {
  FirestoreDietaryRepository(this.db);
  final FirebaseFirestore db;
  DocumentReference<Map<String, dynamic>> _ref(String uid) =>
      db.collection('users').doc(uid).collection('preferences').doc('food');
  @override
  Future<Set<String>> load(String uid) async {
    final data = (await _ref(
      uid,
    ).get(const GetOptions(source: Source.server))).data();
    final tags = data == null
        ? <String>[]
        : List<String>.from(data['tags'] as List);
    if (!validFoodTags(tags)) {
      throw const FormatException('Preferências inválidas');
    }
    return tags.toSet();
  }

  @override
  Future<void> save(String uid, Set<String> tags) {
    if (!validFoodTags(tags)) throw ArgumentError('Tags inválidas');
    return _ref(uid).set({'tags': tags.toList()});
  }
}
