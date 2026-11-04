import 'package:cloud_firestore/cloud_firestore.dart';
import '../repositories/profile_stats_repository.dart';

class FirestoreProfileStatsRepository implements ProfileStatsRepository {
  FirestoreProfileStatsRepository(this.db);
  final FirebaseFirestore db;
  Future<int?> _count(Query<Map<String, dynamic>> query) async {
    try {
      return (await query.count().get().timeout(
        const Duration(seconds: 10),
      )).count;
    } on Object {
      return null;
    }
  }

  @override
  Future<ProfileTotals> totals(String uid) async {
    final counts = await Future.wait([
      _count(db.collection('reviews').where('authorId', isEqualTo: uid)),
      _count(db.collection('visits').where('authorId', isEqualTo: uid)),
      _count(db.collection('users').doc(uid).collection('following')),
    ]);
    return ProfileTotals(
      reviews: counts[0],
      visits: counts[1],
      following: counts[2],
    );
  }
}
