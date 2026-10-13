import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';
import 'package:naarea/data/firebase/firestore_open_report_repository.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/domain/open_status.dart';

FirebaseException _denied() =>
    FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');

FirebaseException _unavailable() =>
    FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');

NewOpenReport _new({String placeId = 'mangai', bool open = true}) =>
    NewOpenReport(
      authorId: 'alice',
      authorName: 'Alice',
      placeId: placeId,
      open: open,
    );

const _discovered = Place(
  id: 'osm-n123',
  name: 'Bar do Zé',
  category: 'Bar',
  neighborhood: 'Sé',
  city: 'São Paulo',
  lat: -23.5503,
  lng: -46.6339,
  osmId: 'node/123',
  source: PlaceSource.osm,
  inCatalog: false,
  discovered: true,
);

final _now = DateTime.utc(2030, 10, 12, 23);

Future<void> _add(
  FakeFirebaseFirestore db, {
  required String id,
  String placeId = 'mangai',
  required Duration ago,
  Object? open = true,
}) => db.collection('openReports').doc(id).set({
  'authorId': 'ana',
  'authorName': 'Ana',
  'placeId': placeId,
  'open': open,
  'createdAt': Timestamp.fromDate(_now.subtract(ago)),
});

void main() {
  group('FirestoreOpenReportRepository.createReport (F20)', () {
    test('grava as 5 chaves das Rules e a trava no mesmo batch', () async {
      final db = FakeFirebaseFirestore();
      final result = await FirestoreOpenReportRepository(
        db,
      ).createReport(_new(open: false));
      expect(result.placeCreated, isFalse);
      final doc = (await db.collection('openReports').get()).docs.single;
      expect(doc.data().keys.toSet(), {
        'authorId',
        'authorName',
        'placeId',
        'open',
        'createdAt',
      });
      expect(doc.data()['open'], isFalse);
      expect(doc.data()['createdAt'], isA<Timestamp>());
      final lock = (await db.doc('users/alice/openReportLocks/mangai').get())
          .data()!;
      expect(lock.keys.toSet(), {'lastAt', 'reportId', 'placeId'});
      expect(lock['reportId'], doc.id);
      expect(lock['placeId'], 'mangai');
      expect(lock['lastAt'], isA<Timestamp>());
    });

    test('local descoberto: criado no mesmo batch do relato', () async {
      final db = FakeFirebaseFirestore();
      final result = await FirestoreOpenReportRepository(
        db,
      ).createReport(_new(placeId: 'osm-n123'), newPlace: _discovered);
      expect(result.placeCreated, isTrue);
      final place = (await db.doc('places/osm-n123').get()).data()!;
      expect(place['createdBy'], 'alice');
      expect(
        (await db.collection('openReports').get()).docs.single['placeId'],
        'osm-n123',
      );
    });

    test('local já criado por outra pessoa: não recria', () async {
      final db = FakeFirebaseFirestore();
      await db.doc('places/osm-n123').set({'name': 'Bar do Zé (antigo)'});
      final result = await FirestoreOpenReportRepository(
        db,
      ).createReport(_new(placeId: 'osm-n123'), newPlace: _discovered);
      expect(result.placeCreated, isFalse);
      expect(
        (await db.doc('places/osm-n123').get()).data()!['name'],
        'Bar do Zé (antigo)',
      );
    });

    test('newPlace de outro local é recusado antes do Firestore', () async {
      final db = FakeFirebaseFirestore();
      expect(
        () => FirestoreOpenReportRepository(
          db,
        ).createReport(_new(), newPlace: _discovered),
        throwsArgumentError,
      );
      expect((await db.collection('openReports').get()).docs, isEmpty);
    });

    test('ack perdido: relê e conclui sem reenviar', () async {
      final db = FakeFirebaseFirestore();
      var commits = 0;
      final repo = FirestoreOpenReportRepository(
        db,
        commitBatch: (batch) async {
          commits++;
          await batch.commit();
          throw _unavailable();
        },
      );
      await repo.createReport(_new());
      expect(commits, 1);
      expect((await db.collection('openReports').get()).docs, hasLength(1));
    });

    test('sem resposta em 15 s (timeout): caminho de ack perdido', () async {
      expect(
        FirestoreOpenReportRepository.defaultCommitTimeout,
        const Duration(seconds: 15),
      );
      final db = FakeFirebaseFirestore();
      final repo = FirestoreOpenReportRepository(
        db,
        commitTimeout: const Duration(milliseconds: 50),
        commitBatch: (batch) async {
          await batch.commit();
          await Completer<void>().future;
        },
      );
      await repo.createReport(_new());
      expect((await db.collection('openReports').get()).docs, hasLength(1));
    });

    test('commit negado sem gravar: o erro original sobe', () async {
      final db = FakeFirebaseFirestore();
      final repo = FirestoreOpenReportRepository(
        db,
        commitBatch: (batch) async => throw _denied(),
      );
      await expectLater(
        repo.createReport(_new()),
        throwsA(
          isA<FirebaseException>().having(
            (e) => e.code,
            'code',
            'permission-denied',
          ),
        ),
      );
      expect((await db.collection('openReports').get()).docs, isEmpty);
    });

    test(
      'corrida: o local nasce no meio → 1 relato, placeCreated false',
      () async {
        final db = FakeFirebaseFirestore();
        await db.doc('places/osm-n123').set({'name': 'Bar do Zé (de outra)'});
        final ref = db.doc('places/osm-n123');
        whenCalling(
          Invocation.method(#get, [null]),
        ).on(ref).thenThrow(_unavailable());
        whenCalling(Invocation.method(#set, null)).on(ref).thenThrow(_denied());
        final result = await FirestoreOpenReportRepository(
          db,
        ).createReport(_new(placeId: 'osm-n123'), newPlace: _discovered);
        expect(result.placeCreated, isFalse);
        final reports = (await db.collection('openReports').get()).docs;
        expect(reports, hasLength(1));
        final lock =
            (await db.doc('users/alice/openReportLocks/osm-n123').get())
                .data()!;
        expect(lock['reportId'], reports.single.id);
      },
    );
  });

  group('FirestoreOpenReportRepository: trava e leituras', () {
    test('openReportLockOf: null sem trava; lastAt com trava', () async {
      final db = FakeFirebaseFirestore();
      final repo = FirestoreOpenReportRepository(db);
      expect(await repo.openReportLockOf('alice', 'mangai'), isNull);
      await db.doc('users/alice/openReportLocks/mangai').set({
        'lastAt': Timestamp.fromDate(_now),
        'reportId': 'o1',
        'placeId': 'mangai',
      });
      expect((await repo.openReportLockOf('alice', 'mangai'))!.toUtc(), _now);
      expect(await repo.openReportLockOf('bob', 'mangai'), isNull);
      await db.doc('users/bob/openReportLocks/mangai').set({'lastAt': 'x'});
      expect(await repo.openReportLockOf('bob', 'mangai'), isNull);
    });

    test('fetchForPlace: só o local, só a janela, mais recentes primeiro, '
        'ignora docs fora do schema', () async {
      final db = FakeFirebaseFirestore();
      await _add(db, id: 'a', ago: const Duration(minutes: 20));
      await _add(db, id: 'b', ago: const Duration(minutes: 5), open: false);
      await _add(db, id: 'velho', ago: const Duration(hours: 4));
      await _add(db, id: 'outro', placeId: 'x', ago: Duration.zero);
      await _add(db, id: 'ruim', ago: Duration.zero, open: 'sim');
      final list = await FirestoreOpenReportRepository(
        db,
      ).fetchForPlace('mangai', since: openReportsSince(_now));
      expect(list.map((r) => r.id), ['b', 'a']);
      expect(list.first.open, isFalse);
      expect(list.first.authorName, 'Ana');
    });

    test(
      'fetchForPlaces: placeId in em lotes de 30, janela, ordenado',
      () async {
        final db = FakeFirebaseFirestore();
        final ids = [for (var i = 0; i < 31; i++) 'p$i'];
        await _add(
          db,
          id: 'r0',
          placeId: 'p0',
          ago: const Duration(minutes: 9),
        );
        await _add(
          db,
          id: 'r30',
          placeId: 'p30',
          ago: const Duration(minutes: 1),
        );
        await _add(db, id: 'old', placeId: 'p1', ago: const Duration(hours: 5));
        await _add(db, id: 'fora', placeId: 'zz', ago: Duration.zero);
        final list = await FirestoreOpenReportRepository(
          db,
        ).fetchForPlaces(ids, since: openReportsSince(_now));
        expect(list.map((r) => r.id), ['r30', 'r0']);
        expect(
          await FirestoreOpenReportRepository(
            db,
          ).fetchForPlaces(const [], since: _now),
          isEmpty,
        );
      },
    );
  });
}
