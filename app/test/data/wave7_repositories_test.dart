import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/data/firebase/firestore_place_history_repository.dart';
import 'package:naarea/data/firebase/firestore_sponsorship_repository.dart';
import 'package:naarea/data/repositories/place_history_repository.dart';
import 'package:naarea/data/sponsorship_floor_reader.dart';
import 'package:naarea/domain/models/review.dart';
import 'package:naarea/domain/models/visit.dart';
import 'package:naarea/domain/sponsorship_floor.dart';

class _FailingHistory implements PlaceHistoryRepository {
  int calls = 0;
  @override
  Future<List<Review>> reviewsSince(String placeId, DateTime since) async {
    calls++;
    throw StateError('offline');
  }

  @override
  Future<List<Visit>> visitsSince(String placeId, DateTime since) async => [];
}

void main() {
  final now = DateTime.utc(2026, 11, 4, 21);

  Future<void> addReview(
    FakeFirebaseFirestore db,
    String id, {
    String placeId = 'p',
    int? food = 4,
    int? service,
    required DateTime at,
    bool silent = false,
  }) => db.doc('reviews/$id').set({
    'authorId': 'a-$id',
    'authorName': 'Pessoa $id',
    'placeId': placeId,
    'placeName': 'Local',
    'food': food,
    'ambience': null,
    'service': service,
    'companion': null,
    if (silent) 'silent': true,
    'createdAt': Timestamp.fromDate(at),
  });

  Future<void> addSlot(FakeFirebaseFirestore db) async {
    await db.doc('config/features').set({
      'sponsorshipEnabled': true,
      'sponsoredSlotIds': ['s'],
    });
    await db.doc('placeOwners/p').set({'uid': 'owner'});
    await db.doc('sponsoredSlots/s').set({
      'placeId': 'p',
      'startsAt': Timestamp.fromDate(now.subtract(const Duration(days: 1))),
      'endsAt': Timestamp.fromDate(now.add(const Duration(days: 6))),
    });
  }

  group('histórico do local (F23/F26)', () {
    test('lê a janela inteira em páginas, inclusive silenciosas', () async {
      final db = FakeFirebaseFirestore();
      for (var i = 0; i < 7; i++) {
        await addReview(
          db,
          'r$i',
          at: now.subtract(Duration(days: i)),
          silent: i.isEven,
        );
      }
      await addReview(db, 'old', at: now.subtract(const Duration(days: 400)));
      await addReview(db, 'other', placeId: 'q', at: now);
      final repo = FirestorePlaceHistoryRepository(db, pageSize: 2);
      final reviews = await repo.reviewsSince(
        'p',
        now.subtract(const Duration(days: 365)),
      );
      expect(reviews.map((r) => r.id), [for (var i = 0; i < 7; i++) 'r$i']);
    });

    test('janela acima do limite de leitura falha em vez de truncar', () async {
      final db = FakeFirebaseFirestore();
      for (var i = 0; i < 5; i++) {
        await addReview(db, 'r$i', at: now.subtract(Duration(hours: i)));
      }
      final repo = FirestorePlaceHistoryRepository(
        db,
        pageSize: 2,
        maxPages: 2,
      );
      await expectLater(
        repo.reviewsSince('p', now.subtract(const Duration(days: 1))),
        throwsStateError,
      );
    });

    test('visitas do local a partir da data', () async {
      final db = FakeFirebaseFirestore();
      for (final (id, days) in [('v1', 1), ('v2', 40), ('v3', 500)]) {
        await db.doc('visits/$id').set({
          'authorId': 'a',
          'authorName': 'Ana',
          'placeId': 'p',
          'placeName': 'Local',
          'companion': null,
          'createdAt': Timestamp.fromDate(now.subtract(Duration(days: days))),
        });
      }
      final visits = await FirestorePlaceHistoryRepository(
        db,
      ).visitsSince('p', now.subtract(const Duration(days: 365)));
      expect(visits.map((v) => v.id), ['v1', 'v2']);
    });
  });

  group('freio do Destaque (F26)', () {
    test('slot de local acima do piso aparece', () async {
      final db = FakeFirebaseFirestore();
      await addSlot(db);
      for (var i = 0; i < 5; i++) {
        await addReview(db, 'r$i', at: now.subtract(Duration(days: i * 10)));
      }
      final repo = FirestoreSponsorshipRepository(
        db,
        floor: SponsorshipFloorReader(FirestorePlaceHistoryRepository(db)),
        emulator: true,
      );
      expect((await repo.current(now)).single.id, 's');
    });

    test(
      'média abaixo do piso suspende e volta sozinho após o cache',
      () async {
        final db = FakeFirebaseFirestore();
        await addSlot(db);
        for (var i = 0; i < 5; i++) {
          await addReview(
            db,
            'bad$i',
            food: 3,
            service: 2,
            at: now.subtract(Duration(days: 1 + i)),
          );
        }
        var clock = now;
        final floor = SponsorshipFloorReader(
          FirestorePlaceHistoryRepository(db),
          clock: () => clock,
        );
        final repo = FirestoreSponsorshipRepository(
          db,
          floor: floor,
          emulator: true,
        );
        expect(await repo.current(now), isEmpty);
        final check = await floor.check('p', now);
        expect(check.status, FloorStatus.belowFloor);
        expect(check.average, 2.5);

        for (var i = 0; i < 10; i++) {
          await addReview(db, 'good$i', food: 5, service: 5, at: now);
        }
        expect(await repo.current(now), isEmpty, reason: 'ainda em cache');
        clock = now.add(const Duration(minutes: 11));
        expect((await repo.current(now)).single.id, 's');
      },
    );

    test('amostra insuficiente suspende', () async {
      final db = FakeFirebaseFirestore();
      await addSlot(db);
      for (var i = 0; i < 4; i++) {
        await addReview(db, 'r$i', food: 5, at: now);
      }
      await addReview(
        db,
        'antiga',
        food: 5,
        at: now.subtract(const Duration(days: 91)),
      );
      final repo = FirestoreSponsorshipRepository(
        db,
        floor: SponsorshipFloorReader(FirestorePlaceHistoryRepository(db)),
        emulator: true,
      );
      expect(await repo.current(now), isEmpty);
    });

    test('falha na leitura esconde o slot e não fica em cache', () async {
      final db = FakeFirebaseFirestore();
      await addSlot(db);
      final history = _FailingHistory();
      final floor = SponsorshipFloorReader(history);
      final repo = FirestoreSponsorshipRepository(
        db,
        floor: floor,
        emulator: true,
      );
      expect(await repo.current(now), isEmpty);
      expect(await repo.current(now), isEmpty);
      expect(history.calls, 2);
    });
  });
}
