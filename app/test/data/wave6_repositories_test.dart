import 'package:naarea/ui/feed/feed_view_model.dart';
import 'package:naarea/ui/core/follow_events.dart';
import '../support/fakes.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/data/firebase/firestore_review_repository.dart';
import 'package:naarea/data/firebase/firestore_visit_repository.dart';
import 'package:naarea/data/firebase/firestore_queue_repository.dart';
import 'package:naarea/data/firebase/firestore_reputation_repository.dart';
import 'package:naarea/data/firebase/firestore_privacy_repository.dart';
import 'package:naarea/data/firebase/firestore_sponsorship_repository.dart';
import 'package:naarea/data/repositories/queue_repository.dart';
import 'package:naarea/domain/models/review.dart';
import 'package:naarea/domain/models/scores.dart';

void main() {
  final now = DateTime.utc(2026, 10, 30, 21);
  test(
    'Fila pendente tardia: reconcilia minutos reais, corrige valor encerrado e cria novo doc após cooldown',
    () async {
      final db = FakeFirebaseFirestore();
      var clock = DateTime.now();
      final gate = Completer<void>();
      var calls = 0;
      final repo = FirestoreQueueRepository(
        db,
        clock: () => clock,
        commitTimeout: const Duration(milliseconds: 20),
        commitBatch: (batch) async {
          calls++;
          if (calls == 1) await gate.future;
          await batch.commit();
        },
      );
      NewQueueReport report(int n) => NewQueueReport(
        authorId: 'a',
        authorName: 'Ana',
        placeId: 'p',
        minutes: n,
      );
      await expectLater(
        repo.createReport(report(10)),
        throwsA(isA<TimeoutException>()),
      );
      await expectLater(
        repo.createReport(report(30)),
        throwsA(isA<QueueRecoveryRequired>()),
      );
      expect(calls, 1);
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final receipt = await repo.reconcilePending('a', 'p');
      expect(receipt!.minutes, 10);
      expect(receipt.recovered, true);
      clock = receipt.createdAt.add(const Duration(minutes: 31));
      final next = await repo.createReport(report(30));
      expect(next.minutes, 30);
      expect(next.id, isNot(receipt.id));
      expect((await db.collection('queueReports').get()).docs, hasLength(2));
      final rejected = FirestoreQueueRepository(
        db,
        commitTimeout: const Duration(milliseconds: 20),
        commitBatch: (_) => Future<void>.error(StateError('rede')),
      );
      await expectLater(rejected.createReport(report(5)), throwsStateError);
      // Operação encerrada e ausência confirmada permitem editar, sem trava permanente.
      await expectLater(rejected.createReport(report(8)), throwsStateError);
      expect(await rejected.reconcilePending('a', 'p'), isNull);
    },
  );
  test(
    'Fila pendência reconhecida só após cooldown não consome o novo envio',
    () async {
      final db = FakeFirebaseFirestore();
      final gate = Completer<void>();
      var calls = 0;
      var clock = DateTime.now();
      final repo = FirestoreQueueRepository(
        db,
        clock: () => clock,
        commitTimeout: const Duration(milliseconds: 20),
        commitBatch: (batch) async {
          if (++calls == 1) await gate.future;
          await batch.commit();
        },
      );
      const old = NewQueueReport(
        authorId: 'a',
        authorName: 'Ana',
        placeId: 'p',
        minutes: 10,
      );
      await expectLater(
        repo.createReport(old),
        throwsA(isA<TimeoutException>()),
      );
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      clock = DateTime.now().add(const Duration(minutes: 31));
      final next = await repo.createReport(
        const NewQueueReport(
          authorId: 'a',
          authorName: 'Ana',
          placeId: 'p',
          minutes: 40,
        ),
      );
      expect(next.minutes, 40);
      expect(calls, 2);
      expect((await db.collection('queueReports').get()).docs, hasLength(2));
    },
  );
  test(
    'FeedViewModel real usa consulta pública e encontra pública após 125 silenciosas',
    () async {
      final db = FakeFirebaseFirestore();
      for (var i = 0; i < 125; i++) {
        await db.doc('reviews/s$i').set({
          'authorId': 'a',
          'authorName': 'Ana',
          'placeId': 'p',
          'placeName': 'P',
          'food': 4,
          'ambience': null,
          'service': null,
          'silent': true,
          'createdAt': Timestamp.fromDate(now.subtract(Duration(minutes: i))),
        });
      }
      await db.doc('reviews/publica').set({
        'authorId': 'a',
        'authorName': 'Ana',
        'placeId': 'p',
        'placeName': 'P',
        'food': 4,
        'ambience': null,
        'service': null,
        'createdAt': Timestamp.fromDate(now.subtract(const Duration(days: 1))),
      });
      final users = FakeUserRepository()
        ..addUser('me', 'Eu')
        ..addUser('a', 'Ana');
      users.followingByUser['me'] = {'a'};
      final vm = FeedViewModel(
        authRepository: FakeAuthRepository(uid: 'me'),
        userRepository: users,
        reviewRepository: FirestoreReviewRepository(db),
        visitRepository: FirestoreVisitRepository(db),
        placeRepository: FakePlaceRepository([]),
        followEvents: FollowEvents(),
      );
      await vm.load();
      expect(vm.items.single.reviews.single.id, 'publica');
      vm.dispose();
    },
  );
  test(
    'Consulta pública mantém todos os empates de fronteira em vários lotes',
    () async {
      final db = FakeFirebaseFirestore();
      for (var i = 0; i < 130; i++) {
        await db.doc('reviews/r$i').set({
          'authorId': i == 129 ? 'a30' : 'a0',
          'authorName': 'A',
          'placeId': 'p',
          'placeName': 'P',
          'food': 4,
          'ambience': null,
          'service': null,
          'createdAt': Timestamp.fromDate(now),
        });
      }
      final result = await FirestoreReviewRepository(
        db,
        perBatchLimit: 20,
      ).fetchPublicByAuthors(List.generate(31, (i) => 'a$i'));
      expect(result.items, hasLength(130));
    },
  );
  test(
    'Fila: timeout sem ACK recupera com o mesmo ID antes de repetir',
    () async {
      final db = FakeFirebaseFirestore();
      var calls = 0;
      final repository = FirestoreQueueRepository(
        db,
        commitTimeout: const Duration(milliseconds: 20),
        commitBatch: (batch) {
          calls++;
          return calls == 1
              ? Future<void>.error(
                  TimeoutException('operação encerrada sem escrita'),
                )
              : batch.commit();
        },
      );
      const report = NewQueueReport(
        authorId: 'a',
        authorName: 'Ana',
        placeId: 'p',
        minutes: 10,
      );
      await expectLater(
        repository.createReport(report),
        throwsA(isA<TimeoutException>()),
      );
      await repository.createReport(report);
      expect((await db.collection('queueReports').get()).docs, hasLength(1));
      expect((await db.collection('auditLog').get()).docs, hasLength(1));
      expect(calls, 2);
    },
  );
  Map<String, dynamic> review(String uid, DateTime at, {bool? silent}) => {
    'authorId': uid,
    'authorName': uid,
    'placeId': 'p',
    'placeName': 'Local',
    'food': 4,
    'ambience': null,
    'service': null,
    'companion': null,
    'createdAt': Timestamp.fromDate(at),
    'silent': ?silent,
  };
  test(
    'Consulta pública ultrapassa 100 silenciosas, inclui legado e preserva global',
    () async {
      final db = FakeFirebaseFirestore();
      for (var i = 0; i < 125; i++) {
        await db
            .doc('reviews/s$i')
            .set(review('a', now.subtract(Duration(minutes: i)), silent: true));
      }
      await db
          .doc('reviews/publica')
          .set(review('a', now.subtract(const Duration(days: 1))));
      final repo = FirestoreReviewRepository(db);
      final public = await repo.fetchPublicByAuthors(['a']);
      expect(public.items.single.id, 'publica');
      expect(public.cutoff, isNull);
      expect((await repo.fetchReviewsByAuthors(['a'])).items, hasLength(100));
      expect((await repo.fetchReviewsForPlace('p', ['a'])), hasLength(126));
    },
  );
  test(
    'Corte público em lotes de 31 autores ignora datas silenciosas e visitas legadas',
    () async {
      final db = FakeFirebaseFirestore();
      for (var i = 0; i < 31; i++) {
        await db
            .doc('reviews/a$i')
            .set(review('a$i', now.subtract(Duration(days: i))));
        await db.doc('reviews/s$i').set(review('a$i', now, silent: true));
        await db.doc('visits/a$i').set({
          ...review('a$i', now.subtract(Duration(days: i))),
          'priceBand': null,
        });
      }
      final repo = FirestoreReviewRepository(db, perBatchLimit: 2);
      final public = await repo.fetchPublicByAuthors(
        List.generate(31, (i) => 'a$i'),
      );
      expect(public.items.map((r) => r.id), ['a0', 'a1']);
      expect(public.cutoff?.toUtc(), now.subtract(const Duration(days: 1)));
      final visits = await FirestoreVisitRepository(
        db,
      ).fetchPublicByAuthors(['a0']);
      expect(visits.items.single.silent, false);
    },
  );
  test(
    'Avaliação silenciosa mantém nota/tag/preço e preferência não altera histórico',
    () async {
      final db = FakeFirebaseFirestore();
      final privacy = FirestorePrivacyRepository(db);
      expect(await privacy.silentDefault('a'), false);
      await privacy.setSilentDefault('a', true);
      final repo = FirestoreReviewRepository(db);
      await repo.createReview(
        NewReview(
          authorId: 'a',
          authorName: 'A',
          placeId: 'p',
          placeName: 'P',
          scores: Scores(food: 5),
          silent: true,
          tags: ['vegano'],
        ),
      );
      await privacy.setSilentDefault('a', false);
      final row = (await repo.fetchReviewsForPlace('p', ['a'])).single;
      expect(row.silent, true);
      expect(row.tags, ['vegano']);
      expect(row.scores.food, 5);
    },
  );
  test(
    'Fila lê janela inteira acima de 200 documentos e reconcilia ack perdido',
    () async {
      final db = FakeFirebaseFirestore();
      for (var i = 0; i < 205; i++) {
        await db.doc('queueReports/r$i').set({
          'authorId': 'a$i',
          'authorName': 'A',
          'placeId': 'p',
          'minutes': i % 181,
          'createdAt': Timestamp.fromDate(now.subtract(Duration(minutes: i))),
        });
      }
      final repo = FirestoreQueueRepository(
        db,
        commitTimeout: const Duration(milliseconds: 20),
        commitBatch: (batch) async {
          await batch.commit();
          throw TimeoutException('ack perdido');
        },
      );
      expect(
        await repo.fetchForPlace(
          'p',
          since: now.subtract(const Duration(days: 28)),
        ),
        hasLength(205),
      );
      await repo.createReport(
        const NewQueueReport(
          authorId: 'me',
          authorName: 'Eu',
          placeId: 'p',
          minutes: 0,
        ),
      );
      expect(
        (await db.collection('auditLog').get()).docs.single
            .data()['collection'],
        'queueReports',
      );
      expect(
        (await db
                .collection('queueReports')
                .where('authorId', isEqualTo: 'me')
                .get())
            .docs,
        hasLength(1),
      );
    },
  );
  test(
    'Respostas globais paginam, normalizam e repetir não duplica nem altera notas',
    () async {
      final db = FakeFirebaseFirestore();
      await db.doc('users/owner').set({'displayName': 'Titular'});
      for (var i = 0; i < 25; i++) {
        await db
            .doc('reviews/r$i')
            .set(review('a$i', now.subtract(Duration(minutes: i))));
      }
      final repo = FirestoreReputationRepository(db);
      final first = await repo.reviewsForPlace('p');
      expect(first.reviews, hasLength(20));
      expect(
        (await repo.reviewsForPlace('p', after: first.next)).reviews,
        hasLength(5),
      );
      await repo.reply('owner', 'r0', '  Obrigado  ');
      await repo.reply('owner', 'r0', 'Obrigado');
      expect((await repo.replyFor('r0'))!.text, 'Obrigado');
      expect((await db.collection('ownerReplies').get()).docs, hasLength(1));
      expect((await db.doc('reviews/r0').get()).data()!['food'], 4);
      expect((await db.collection('auditLog').get()).docs, hasLength(1));
      await expectLater(
        repo.reply('owner', 'r0', 'outro texto'),
        throwsStateError,
      );
    },
  );
  test(
    'Destaque exige emulador, flag, vigência e titular mesmo com documentos existentes',
    () async {
      final db = FakeFirebaseFirestore();
      final repo = FirestoreSponsorshipRepository(db, emulator: true);
      expect(await repo.current(now), isEmpty);
      await db.doc('config/features').set({
        'sponsorshipEnabled': true,
        'sponsoredSlotIds': ['bad', 'ok', 'expired', 'unowned'],
      });
      await db.doc('sponsoredSlots/bad').set({
        'placeId': 4,
        'startsAt': 'inválido',
      });
      await db.doc('placeOwners/p').set({'uid': 'owner'});
      for (final id in ['ok', 'expired', 'unowned']) {
        await db.doc('sponsoredSlots/$id').set({
          'placeId': id == 'unowned' ? 'q' : 'p',
          'startsAt': Timestamp.fromDate(now.subtract(const Duration(days: 1))),
          'endsAt': Timestamp.fromDate(
            id == 'expired' ? now : now.add(const Duration(days: 1)),
          ),
        });
      }
      expect((await repo.current(now)).single.id, 'ok');
      expect(await FirestoreSponsorshipRepository(db).current(now), isEmpty);
    },
  );
}
