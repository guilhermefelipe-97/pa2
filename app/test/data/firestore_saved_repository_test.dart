import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/data/firebase/firestore_review_repository.dart';
import 'package:naarea/data/firebase/firestore_saved_repository.dart';
import 'package:naarea/data/repositories/review_repository.dart';

void main() {
  group('FirestoreSavedRepository', () {
    test('save grava só createdAt em users/{uid}/saved/{placeId}', () async {
      final db = FakeFirebaseFirestore();
      await FirestoreSavedRepository(db).save(uid: 'me', placeId: 'mangai');

      final snap = await db.doc('users/me/saved/mangai').get();
      expect(snap.exists, isTrue);
      expect(snap.data()!.keys, ['createdAt']);
      expect(snap.data()!['createdAt'], isA<Timestamp>());
    });

    test(
      'listSaved: só do usuário, mais recente primeiro, com createdAt',
      () async {
        final db = FakeFirebaseFirestore();
        Future<void> put(String uid, String id, DateTime at) => db
            .doc('users/$uid/saved/$id')
            .set({'createdAt': Timestamp.fromDate(at)});
        await put('me', 'velho', DateTime.utc(2026, 9, 1));
        await put('me', 'novo', DateTime.utc(2026, 9, 20));
        await put('me', 'meio', DateTime.utc(2026, 9, 10));
        await put('outra', 'x', DateTime.utc(2026, 9, 25));

        final list = await FirestoreSavedRepository(db).listSaved('me');
        expect(list.map((s) => s.placeId), ['novo', 'meio', 'velho']);
        expect(
          list.first.savedAt.isAtSameMomentAs(DateTime.utc(2026, 9, 20)),
          isTrue,
        );
      },
    );

    test(
      'listSaved: createdAt ausente (escrita pendente) conta como agora',
      () async {
        final db = FakeFirebaseFirestore();
        final now = DateTime.utc(2026, 10, 1, 12);
        await db.doc('users/me/saved/a').set({
          'createdAt': Timestamp.fromDate(DateTime.utc(2026, 9, 1)),
        });
        await db.doc('users/me/saved/b').set({'createdAt': null});

        final list = await FirestoreSavedRepository(
          db,
          clock: () => now,
        ).listSaved('me');
        final b = list.firstWhere((s) => s.placeId == 'b');
        expect(b.savedAt, now);
        expect(list.first.placeId, 'b');
      },
    );

    test(
      'savedAtOf: createdAt do servidor quando existe; null quando não',
      () async {
        final db = FakeFirebaseFirestore();
        final repo = FirestoreSavedRepository(db);
        await db.doc('users/me/saved/a').set({
          'createdAt': Timestamp.fromDate(DateTime.utc(2026, 9, 1)),
        });
        final at = await repo.savedAtOf(uid: 'me', placeId: 'a');
        expect(at!.isAtSameMomentAs(DateTime.utc(2026, 9, 1)), isTrue);
        expect(await repo.savedAtOf(uid: 'me', placeId: 'b'), isNull);
      },
    );

    test('remove apaga o doc', () async {
      final db = FakeFirebaseFirestore();
      final repo = FirestoreSavedRepository(db);
      await repo.save(uid: 'me', placeId: 'mangai');
      await repo.remove(uid: 'me', placeId: 'mangai');
      expect((await db.doc('users/me/saved/mangai').get()).exists, isFalse);
      expect(await repo.listSaved('me'), isEmpty);
    });
  });

  group('FirestoreReviewRepository.fetchReviewsForPlace', () {
    Future<void> add(
      FakeFirebaseFirestore db,
      String placeId,
      String author,
      DateTime at,
    ) => db.collection('reviews').add({
      'authorId': author,
      'authorName': author.toUpperCase(),
      'placeId': placeId,
      'placeName': 'Local $placeId',
      'food': 4,
      'ambience': 4,
      'service': 4,
      'companion': null,
      'comment': null,
      'createdAt': Timestamp.fromDate(at),
    });

    test('só o local e os autores pedidos, mais recentes primeiro', () async {
      final db = FakeFirebaseFirestore();
      await add(db, 'x', 'a', DateTime.utc(2026, 9, 1));
      await add(db, 'x', 'b', DateTime.utc(2026, 9, 3));
      await add(db, 'x', 'estranho', DateTime.utc(2026, 9, 4));
      await add(db, 'y', 'a', DateTime.utc(2026, 9, 2));

      final list = await FirestoreReviewRepository(
        db,
      ).fetchReviewsForPlace('x', ['a', 'b']);
      expect(list.map((r) => r.authorId), ['b', 'a']);
    });

    test(
      'autores em lotes de 30; amigo antigo não some atrás de muitas avaliações',
      () async {
        final db = FakeFirebaseFirestore();
        final authors = [for (var i = 0; i < 65; i++) 'u$i'];
        for (var i = 0; i < 65; i++) {
          await add(
            db,
            'x',
            'u$i',
            DateTime.utc(2026, 9, 1).add(Duration(minutes: i)),
          );
        }
        for (var i = 0; i < 60; i++) {
          await add(
            db,
            'x',
            'terceiro$i',
            DateTime.utc(2026, 9, 20).add(Duration(minutes: i)),
          );
        }
        final list = await FirestoreReviewRepository(
          db,
        ).fetchReviewsForPlace('x', authors);
        expect(list, hasLength(65));
        expect(list.first.authorId, 'u64');
        expect(list.last.authorId, 'u0');
        expect(ReviewRepository.whereInLimit, 30);
      },
    );

    test('sem autores não consulta', () async {
      final db = FakeFirebaseFirestore();
      await add(db, 'x', 'a', DateTime.utc(2026, 9, 1));
      expect(
        await FirestoreReviewRepository(db).fetchReviewsForPlace('x', const []),
        isEmpty,
      );
    });
  });
}
