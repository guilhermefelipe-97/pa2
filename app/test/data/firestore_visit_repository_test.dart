import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';
import 'package:naarea/data/firebase/firestore_visit_repository.dart';
import 'package:naarea/domain/models/companion.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/domain/models/visit.dart';
import 'package:naarea/domain/price_band.dart';

FirebaseException _denied() =>
    FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');

FirebaseException _unavailable() =>
    FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');

NewVisit _newVisit({
  String placeId = 'mangai',
  Companion? companion,
  PriceBand? priceBand,
}) => NewVisit(
  authorId: 'alice',
  authorName: 'Alice',
  placeId: placeId,
  placeName: placeId == 'mangai' ? 'Mangai' : 'Bar do Zé',
  companion: companion,
  priceBand: priceBand,
);

/// Local só descoberto pelo Photon (G2).
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

Future<void> _addVisit(
  FakeFirebaseFirestore db, {
  required String id,
  required String authorId,
  String placeId = 'mangai',
  required DateTime createdAt,
  Object? priceBand,
  bool omitPriceBand = true,
}) => db.collection('visits').doc(id).set({
  'authorId': authorId,
  'authorName': authorId.toUpperCase(),
  'placeId': placeId,
  'placeName': 'Local $placeId',
  'companion': null,
  if (!omitPriceBand) 'priceBand': priceBand,
  'createdAt': Timestamp.fromDate(createdAt),
});

DateTime _t(int minutes) =>
    DateTime.utc(2026, 9, 1).add(Duration(minutes: minutes));

void main() {
  group('FirestoreVisitRepository.createVisit (F15)', () {
    test('grava as 7 chaves das Rules e a trava no mesmo batch', () async {
      final db = FakeFirebaseFirestore();
      final result = await FirestoreVisitRepository(
        db,
      ).createVisit(_newVisit(companion: Companion.amigos));
      expect(result.placeCreated, isFalse);
      final visit = (await db.collection('visits').get()).docs.single;
      expect(visit.data().keys.toSet(), {
        'authorId',
        'authorName',
        'placeId',
        'placeName',
        'companion',
        'priceBand',
        'createdAt',
      });
      expect(visit.data()['companion'], 'amigos');
      // F27: sem faixa escolhida, a chave vai com null.
      expect(visit.data()['priceBand'], isNull);
      expect(visit.data()['createdAt'], isA<Timestamp>());
      final lock = await db.doc('users/alice/visitLocks/mangai').get();
      expect(lock.data()!.keys.toSet(), {'lastAt', 'visitId', 'placeId'});
      expect(lock.data()!['visitId'], visit.id);
      expect(lock.data()!['placeId'], 'mangai');
      expect(lock.data()!['lastAt'], isA<Timestamp>());
    });

    test('F27: faixa de preço gravada como int 1–5', () async {
      final db = FakeFirebaseFirestore();
      await FirestoreVisitRepository(
        db,
      ).createVisit(_newVisit(priceBand: PriceBand.upTo30));
      final data = (await db.collection('visits').get()).docs.single.data();
      expect(data['priceBand'], 1);
    });

    test('companhia ausente: chave presente com null; sem notas', () async {
      final db = FakeFirebaseFirestore();
      await FirestoreVisitRepository(db).createVisit(_newVisit());
      final data = (await db.collection('visits').get()).docs.single.data();
      expect(data.containsKey('companion'), isTrue);
      expect(data['companion'], isNull);
      expect(data.containsKey('food'), isFalse);
    });

    test('local descoberto: criado no mesmo batch da visita', () async {
      final db = FakeFirebaseFirestore();
      final result = await FirestoreVisitRepository(
        db,
      ).createVisit(_newVisit(placeId: 'osm-n123'), newPlace: _discovered);
      expect(result.placeCreated, isTrue);
      final place = (await db.doc('places/osm-n123').get()).data()!;
      expect(place['createdBy'], 'alice');
      expect(place['source'], 'osm');
      final visit = (await db.collection('visits').get()).docs.single;
      expect(visit.data()['placeId'], 'osm-n123');
      expect(
        (await db.doc('users/alice/visitLocks/osm-n123').get()).exists,
        isTrue,
      );
    });

    test('local já criado por outra pessoa: usa o nome gravado', () async {
      final db = FakeFirebaseFirestore();
      await db.doc('places/osm-n123').set({'name': 'Bar do Zé (antigo)'});
      final result = await FirestoreVisitRepository(
        db,
      ).createVisit(_newVisit(placeId: 'osm-n123'), newPlace: _discovered);
      expect(result.placeCreated, isFalse);
      final visit = (await db.collection('visits').get()).docs.single;
      expect(visit.data()['placeName'], 'Bar do Zé (antigo)');
    });

    test('newPlace de outro local é recusado antes do Firestore', () async {
      final db = FakeFirebaseFirestore();
      expect(
        () => FirestoreVisitRepository(
          db,
        ).createVisit(_newVisit(), newPlace: _discovered),
        throwsArgumentError,
      );
      expect((await db.collection('visits').get()).docs, isEmpty);
    });

    test('ack perdido de fato: o commit grava e lança; relê a visita e '
        'conclui sem reenviar', () async {
      final db = FakeFirebaseFirestore();
      var commits = 0;
      Object? thrown;
      final repo = FirestoreVisitRepository(
        db,
        commitBatch: (batch) async {
          commits++;
          await batch.commit();
          thrown = _unavailable();
          throw thrown!;
        },
      );
      final result = await repo.createVisit(_newVisit());
      expect(thrown, isA<FirebaseException>(), reason: 'o ack se perdeu');
      expect(commits, 1, reason: 'sem reenvio');
      expect(result.placeCreated, isFalse);
      expect((await db.collection('visits').get()).docs, hasLength(1));
    });

    test('sem resposta em 15 s (timeout): cai no caminho de ack perdido', () {
      expect(
        FirestoreVisitRepository.defaultCommitTimeout,
        const Duration(seconds: 15),
      );
      return () async {
        final db = FakeFirebaseFirestore();
        var commits = 0;
        final repo = FirestoreVisitRepository(
          db,
          commitTimeout: const Duration(milliseconds: 50),
          commitBatch: (batch) async {
            commits++;
            await batch.commit();
            // A resposta nunca chega.
            await Completer<void>().future;
          },
        );
        await repo.createVisit(_newVisit());
        expect(commits, 1);
        expect((await db.collection('visits').get()).docs, hasLength(1));
      }();
    });

    test('ack perdido e releitura da visita indeterminada: a trava que aponta '
        'para esta tentativa confirma o sucesso', () async {
      final db = FakeFirebaseFirestore();
      String? id;
      final repo = FirestoreVisitRepository(
        db,
        commitBatch: (batch) async {
          await batch.commit();
          id = (await db.collection('visits').get()).docs.single.id;
          // A leitura da própria visita falha (rede instável). A partir
          // daqui o teste não lê mais `visits` (o fake lê cada doc).
          whenCalling(
            Invocation.method(#get, null),
          ).on(db.doc('visits/$id')).thenThrow(_unavailable());
          throw _unavailable();
        },
      );
      final result = await repo.createVisit(_newVisit());
      expect(result.placeCreated, isFalse);
      final lock = (await db.doc('users/alice/visitLocks/mangai').get())
          .data()!;
      expect(lock['visitId'], id);
    });

    test('commit negado sem gravar: o erro original sobe', () async {
      final db = FakeFirebaseFirestore();
      final repo = FirestoreVisitRepository(
        db,
        commitBatch: (batch) async => throw _denied(),
      );
      await expectLater(
        repo.createVisit(_newVisit()),
        throwsA(
          isA<FirebaseException>().having(
            (e) => e.code,
            'code',
            'permission-denied',
          ),
        ),
      );
      expect((await db.collection('visits').get()).docs, isEmpty);
    });

    test('corrida: o local nasce no meio → 1 visita, com o nome gravado, '
        'placeCreated false', () async {
      final db = FakeFirebaseFirestore();
      await db.doc('places/osm-n123').set({'name': 'Bar do Zé (de outra)'});
      final ref = db.doc('places/osm-n123');
      // A 1ª leitura não vê o doc; o create dentro do batch vira update:
      // negado, derrubando o batch.
      whenCalling(
        Invocation.method(#get, [null]),
      ).on(ref).thenThrow(_unavailable());
      whenCalling(Invocation.method(#set, null)).on(ref).thenThrow(_denied());
      final result = await FirestoreVisitRepository(
        db,
      ).createVisit(_newVisit(placeId: 'osm-n123'), newPlace: _discovered);
      expect(result.placeCreated, isFalse);
      final visits = (await db.collection('visits').get()).docs;
      expect(visits, hasLength(1));
      expect(visits.single.data()['placeName'], 'Bar do Zé (de outra)');
      final lock = (await db.doc('users/alice/visitLocks/osm-n123').get())
          .data()!;
      expect(lock['visitId'], visits.single.id);
    });

    test(
      'corrida com a releitura do local falhando: o erro original sobe',
      () async {
        final db = FakeFirebaseFirestore();
        final ref = db.doc('places/osm-n123');
        whenCalling(
          Invocation.method(#get, null),
        ).on(ref).thenThrow(_unavailable());
        whenCalling(Invocation.method(#set, null)).on(ref).thenThrow(_denied());
        await expectLater(
          FirestoreVisitRepository(
            db,
          ).createVisit(_newVisit(placeId: 'osm-n123'), newPlace: _discovered),
          throwsA(
            isA<FirebaseException>().having(
              (e) => e.code,
              'code',
              'permission-denied',
            ),
          ),
        );
        expect((await db.collection('visits').get()).docs, isEmpty);
      },
    );
  });

  group('FirestoreVisitRepository: trava e leituras', () {
    test('visitLockOf: null sem trava; lastAt com trava; por usuário e '
        'local', () async {
      final db = FakeFirebaseFirestore();
      final repo = FirestoreVisitRepository(db);
      expect(await repo.visitLockOf('alice', 'mangai'), isNull);
      final at = DateTime.utc(2030, 10, 12, 16);
      await db.doc('users/alice/visitLocks/mangai').set({
        'lastAt': Timestamp.fromDate(at),
        'visitId': 'v1',
        'placeId': 'mangai',
      });
      expect((await repo.visitLockOf('alice', 'mangai'))!.toUtc(), at);
      expect(await repo.visitLockOf('bob', 'mangai'), isNull);
      expect(await repo.visitLockOf('alice', 'camaroes'), isNull);
      await db.doc('users/bob/visitLocks/mangai').set({'lastAt': 'ontem'});
      expect(await repo.visitLockOf('bob', 'mangai'), isNull);
    });

    test('fetchVisitsByAuthors: só dos autores, mais recentes primeiro, '
        'com limit', () async {
      final db = FakeFirebaseFirestore();
      await _addVisit(db, id: 'a1', authorId: 'ana', createdAt: _t(1));
      await _addVisit(db, id: 'a2', authorId: 'ana', createdAt: _t(5));
      await _addVisit(db, id: 'b1', authorId: 'bia', createdAt: _t(3));
      await _addVisit(db, id: 'c1', authorId: 'caio', createdAt: _t(9));
      final repo = FirestoreVisitRepository(db);
      final all = (await repo.fetchVisitsByAuthors(['ana', 'bia'])).items;
      expect(all.map((v) => v.id), ['a2', 'b1', 'a1']);
      final two = (await repo.fetchVisitsByAuthors([
        'ana',
        'bia',
      ], limit: 2)).items;
      expect(two.map((v) => v.id), ['a2', 'b1']);
      expect((await repo.fetchVisitsByAuthors([])).items, isEmpty);
    });

    test('fetchVisitsByAuthors: mais de 30 autores em lotes, com corte '
        'consistente entre lotes cheios', () async {
      final db = FakeFirebaseFirestore();
      final authors = [for (var i = 0; i < 31; i++) 'u$i'];
      // Lote 1 (u0..u29): 2 visitas de u0, a mais antiga em t(1).
      await _addVisit(db, id: 'old', authorId: 'u0', createdAt: _t(1));
      await _addVisit(db, id: 'new', authorId: 'u0', createdAt: _t(10));
      // Lote 2 (u30): 1 visita em t(5).
      await _addVisit(db, id: 'mid', authorId: 'u30', createdAt: _t(5));
      final repo = FirestoreVisitRepository(db, perBatchLimit: 1);
      final result = (await repo.fetchVisitsByAuthors(authors)).items;
      // Lote 1 cheio com t(10); lote 2 cheio com t(5): corta antes de t(10).
      expect(result.map((v) => v.id), ['new']);
    });

    test('fetchVisitsForPlace: placeId == e autores, ignora docs fora do '
        'schema', () async {
      final db = FakeFirebaseFirestore();
      await _addVisit(db, id: 'x1', authorId: 'ana', createdAt: _t(1));
      await _addVisit(
        db,
        id: 'y1',
        authorId: 'ana',
        placeId: 'outro',
        createdAt: _t(2),
      );
      await _addVisit(db, id: 'x2', authorId: 'zé', createdAt: _t(3));
      await db.collection('visits').doc('ruim').set({
        'authorId': 'ana',
        'placeId': 'mangai',
        'createdAt': Timestamp.fromDate(_t(4)),
      });
      final repo = FirestoreVisitRepository(db);
      final found = await repo.fetchVisitsForPlace('mangai', ['ana', 'bia']);
      expect(found.map((v) => v.id), ['x1']);
      expect(found.single, isA<Visit>());
      expect(found.single.companion, isNull);
    });

    test('F27: lê priceBand; ausente (build antigo) ou null = não '
        'informado; inválido ignora o doc', () async {
      final db = FakeFirebaseFirestore();
      final cases = <(Object?, bool)>[
        (5, false),
        (null, false),
        (null, true),
        (0, false),
        (6, false),
        ('2', false),
        (2.5, false),
      ];
      for (var i = 0; i < cases.length; i++) {
        await _addVisit(
          db,
          id: 'p$i',
          authorId: 'ana',
          createdAt: _t(100 - i),
          priceBand: cases[i].$1,
          omitPriceBand: cases[i].$2,
        );
      }
      final found = (await FirestoreVisitRepository(
        db,
      ).fetchVisitsByAuthors(['ana'])).items;
      expect(found.map((v) => v.id), ['p0', 'p1', 'p2']);
      expect(found.map((v) => v.priceBand), [PriceBand.from150, null, null]);
    });
  });
}
