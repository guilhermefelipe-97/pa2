import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/data/firebase/firestore_review_repository.dart';

void main() {
  late FakeFirebaseFirestore db;
  late FirestoreReviewRepository repo;
  setUp(() {
    db = FakeFirebaseFirestore();
    repo = FirestoreReviewRepository(db);
  });
  Future<void> put(String id, String place, String author, int time) =>
      db.doc('reviews/$id').set({
        'authorId': author,
        'authorName': author,
        'placeId': place,
        'placeName': place,
        'food': 5,
        'ambience': null,
        'service': null,
        'createdAt': Timestamp.fromMillisecondsSinceEpoch(time),
      });
  test(
    'histórico completo com mais de duas páginas e datas empatadas',
    () async {
      for (var i = 0; i < 205; i++) {
        await put('r${i.toString().padLeft(3, '0')}', 'saved', 'friend', 1000);
      }
      for (var i = 0; i < 105; i++) {
        await put('noise$i', 'other', 'friend', 2000);
      }
      await put('outsider', 'saved', 'stranger', 3000);
      final result = await repo.reviewsForCandidates(
        ['saved', 'saved'],
        ['friend', 'friend'],
      );
      expect(result.length, 205);
      expect(result.map((r) => r.id).toSet().length, 205);
      expect(
        result.every((r) => r.placeId == 'saved' && r.authorId == 'friend'),
        isTrue,
      );
    },
  );
  test(
    'divide autores e locais sem perder candidatos ou repetir avaliações',
    () async {
      final authors = [for (var i = 0; i < 31; i++) 'f$i'];
      for (final author in authors) {
        for (final place in ['a', 'b', 'c']) {
          await put('$author-$place', place, author, 1000);
        }
      }
      final result = await repo.reviewsForCandidates(['a', 'b', 'c'], authors);
      expect(result.length, 93);
      expect(result.map((r) => r.id).toSet().length, 93);
    },
  );
  test(
    'sem candidatos, autores ou após cancelamento não retorna dados',
    () async {
      await put('r', 'a', 'f', 1000);
      expect(await repo.reviewsForCandidates([], ['f']), isEmpty);
      expect(await repo.reviewsForCandidates(['a'], []), isEmpty);
      expect(
        await repo.reviewsForCandidates(['a'], ['f'], cancelled: () => true),
        isEmpty,
      );
    },
  );
}
