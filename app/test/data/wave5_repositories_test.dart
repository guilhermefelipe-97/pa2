import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/data/firebase/firestore_review_repository.dart';
import 'package:naarea/data/firebase/firestore_dietary_repository.dart';
import 'package:naarea/data/firebase/firestore_owner_repository.dart';
import 'package:naarea/domain/models/review.dart';
import 'package:naarea/domain/models/scores.dart';

void main() {
  test('NewReview.tags não vazia é persistida e lida', () async {
    final db = FakeFirebaseFirestore();
    final repo = FirestoreReviewRepository(db);
    await repo.createReview(
      NewReview(
        authorId: 'me',
        authorName: 'Eu',
        placeId: 'p1',
        placeName: 'Local',
        scores: Scores(food: 4),
        tags: ['vegano', 'integral'],
      ),
    );
    expect((await db.collection('reviews').get()).docs.single.data()['tags'], [
      'vegano',
      'integral',
    ]);
    expect((await repo.fetchReviewsForPlace('p1', ['me'])).single.tags, [
      'vegano',
      'integral',
    ]);
  });
  test(
    'tags malformadas na última review preservam review e retiram voto anterior',
    () async {
      final db = FakeFirebaseFirestore();
      final repo = FirestoreReviewRepository(db);
      final data = {
        'authorId': 'a',
        'authorName': 'Ana',
        'placeId': 'p1',
        'placeName': 'Local',
        'food': 4,
        'ambience': null,
        'service': null,
        'createdAt': Timestamp.fromDate(DateTime.utc(2030)),
        'tags': ['vegano'],
      };
      for (final uid in ['a', 'b', 'c']) {
        await db.doc('reviews/$uid').set({...data, 'authorId': uid});
      }
      expect((await repo.confirmedFor(['p1']))['p1'], {'vegano': 3});
      for (final malformed in [
        42,
        'vegano',
        ['vegano', 42],
        ['vegano', 'vegano'],
        ['fora-do-vocabulario'],
      ]) {
        await db.doc('reviews/ultima').set({
          ...data,
          'tags': malformed,
          'createdAt': Timestamp.fromDate(DateTime.utc(2031)),
        });
        final rows = await repo.fetchReviewsForPlace('p1', ['a']);
        expect(rows, hasLength(2));
        expect(rows.first.tags, isEmpty);
        expect((await repo.confirmedFor(['p1']))['p1'], isEmpty);
      }
    },
  );
  test(
    'quórum global atravessa 31 locais e mais de 100 reviews sem corte; exclui titular atual',
    () async {
      final db = FakeFirebaseFirestore();
      final timestamp = Timestamp.fromDate(DateTime.utc(2030));
      for (var place = 0; place < 31; place++) {
        for (var author = 0; author < 4; author++) {
          await db.doc('reviews/p$place-a$author').set({
            'authorId': 'a$author',
            'authorName': 'Autor $author',
            'placeId': 'p$place',
            'placeName': 'Local $place',
            'food': 4,
            'ambience': null,
            'service': null,
            'createdAt': timestamp,
            'tags': ['vegano', 'integral'],
          });
        }
      }

      for (var i = 0; i < 105; i++) {
        await db.doc('reviews/repetida$i').set({
          'authorId': 'a0',
          'authorName': 'Autor 0',
          'placeId': 'p0',
          'placeName': 'Local 0',
          'food': 4,
          'ambience': null,
          'service': null,
          'createdAt': timestamp,
          'tags': ['vegano'],
        });
      }
      await db.doc('placeOwners/p30').set({
        'uid': 'a3',
        'verifiedAt': timestamp,
      });
      final tags = await FirestoreReviewRepository(
        db,
      ).confirmedFor(List.generate(31, (i) => 'p$i'));
      expect(tags.length, 31);
      expect(tags['p30'], {'vegano': 3, 'integral': 3});
      expect(tags['p0']?['vegano'], 4);
      expect(tags['p0']?['integral'], 3);

      await db.doc('reviews/ultima').set({
        'authorId': 'a0',
        'authorName': 'Autor 0',
        'placeId': 'p30',
        'placeName': 'Local 30',
        'food': 4,
        'ambience': null,
        'service': null,
        'createdAt': Timestamp.fromDate(DateTime.utc(2031)),
      });
      expect(
        (await FirestoreReviewRepository(db).confirmedFor(['p30']))['p30'],
        isEmpty,
      );
    },
  );
  test(
    'preferências privadas e pedido repetido usam o documento existente',
    () async {
      final db = FakeFirebaseFirestore();
      final dietary = FirestoreDietaryRepository(db);
      expect(await dietary.load('a'), isEmpty);
      await dietary.save('a', {'vegano', 'integral'});
      expect(await FirestoreDietaryRepository(db).load('a'), {
        'vegano',
        'integral',
      });
      final owners = FirestoreOwnerRepository(db);
      expect((await owners.request('a', 'p1')).status, 'pending');
      await db.doc('users/a/ownershipRequests/p1').update({
        'status': 'rejected',
      });
      expect((await owners.request('a', 'p1')).status, 'rejected');
      expect(await owners.ownerOf('p1'), isNull);
    },
  );
}
