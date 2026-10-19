import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';
import 'package:naarea/data/firebase/audit_log.dart';
import 'package:naarea/data/firebase/firestore_open_report_repository.dart';
import 'package:naarea/data/firebase/firestore_review_repository.dart';
import 'package:naarea/data/firebase/firestore_visit_repository.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/domain/models/review.dart';
import 'package:naarea/domain/models/scores.dart';
import 'package:naarea/domain/models/visit.dart';
import 'package:naarea/domain/open_status.dart';

import '../support/rules_source.dart';

FirebaseException _denied() =>
    FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');

FirebaseException _unavailable() =>
    FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');

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

NewReview _review({String placeId = 'mangai'}) => NewReview(
  authorId: 'alice',
  authorName: 'Alice',
  placeId: placeId,
  placeName: placeId == 'mangai' ? 'Mangai' : 'Bar do Zé',
  scores: Scores(food: 5),
  companion: null,
  comment: null,
);

NewVisit _visit({String placeId = 'mangai'}) => NewVisit(
  authorId: 'alice',
  authorName: 'Alice',
  placeId: placeId,
  placeName: placeId == 'mangai' ? 'Mangai' : 'Bar do Zé',
  companion: null,
);

NewOpenReport _report({String placeId = 'mangai'}) => NewOpenReport(
  authorId: 'alice',
  authorName: 'Alice',
  placeId: placeId,
  open: true,
);

/// A única entrada de auditoria gravada.
Future<QueryDocumentSnapshot<Map<String, dynamic>>> _singleEntry(
  FakeFirebaseFirestore db,
) async => (await db.collection(auditLogCollection).get()).docs.single;

void _expectEntry(
  QueryDocumentSnapshot<Map<String, dynamic>> entry, {
  required String collection,
  required String docId,
  required String placeId,
}) {
  expect(entry.id, '$collection-$docId');
  final data = entry.data();
  expect(data.keys.toSet(), {
    'actorUid',
    'action',
    'collection',
    'docId',
    'placeId',
    'at',
  });
  expect(data['actorUid'], 'alice');
  expect(data['action'], 'create');
  expect(data['collection'], collection);
  expect(data['docId'], docId);
  expect(data['placeId'], placeId);
  expect(data['at'], isA<Timestamp>());
}

/// Corrida do G2: a 1ª leitura do local falha e o create dele no batch é
/// negado (vira update), então o 1º commit falha e o retry grava sem ele.
void _placeRace(FakeFirebaseFirestore db) {
  final ref = db.doc('places/osm-n123');
  whenCalling(
    Invocation.method(#get, [null]),
  ).on(ref).thenThrow(_unavailable());
  whenCalling(Invocation.method(#set, null)).on(ref).thenThrow(_denied());
}

void main() {
  test('id determinístico {coleção}-{docId}', () {
    expect(auditLogId('reviews', 'abc'), 'reviews-abc');
    expect(auditLogId('openReports', 'x1'), 'openReports-x1');
  });

  test('coleções auditadas: as mesmas das Rules', () {
    final rules = readFirestoreRules();
    expect(
      rules,
      contains(
        "data.collection in "
        "[${auditedCollections.map((c) => "'$c'").join(', ')}]",
      ),
    );
  });

  group('avaliação (F04)', () {
    test(
      'entrada no mesmo batch, com chaves exatas e at do servidor',
      () async {
        final db = FakeFirebaseFirestore();
        await FirestoreReviewRepository(db).createReview(_review());
        final review = (await db.collection('reviews').get()).docs.single;
        _expectEntry(
          await _singleEntry(db),
          collection: 'reviews',
          docId: review.id,
          placeId: 'mangai',
        );
      },
    );

    test('com foto: uma entrada só, da avaliação', () async {
      final db = FakeFirebaseFirestore();
      await FirestoreReviewRepository(
        db,
      ).createReview(_review(), photo: Uint8List.fromList([0xFF, 0xD8, 0xFF]));
      final review = (await db.collection('reviews').get()).docs.single;
      expect((await _singleEntry(db)).id, 'reviews-${review.id}');
    });

    test('retry depois de falha: mesmo id, uma entrada só', () async {
      final db = FakeFirebaseFirestore();
      await db.doc('places/osm-n123').set({'name': 'Bar do Zé'});
      _placeRace(db);
      await FirestoreReviewRepository(
        db,
      ).createReview(_review(placeId: 'osm-n123'), newPlace: _discovered);
      final review = (await db.collection('reviews').get()).docs.single;
      _expectEntry(
        await _singleEntry(db),
        collection: 'reviews',
        docId: review.id,
        placeId: 'osm-n123',
      );
    });
  });

  group('avaliação (F04): ack perdido', () {
    test('batch gravado sem resposta: conclui sem reenviar e sem 2ª '
        'entrada', () async {
      final db = FakeFirebaseFirestore();
      // O fake grava o batch em ordem: review e auditoria entram e a trava
      // (última escrita) lança, como um commit que chegou sem ack.
      whenCalling(
        Invocation.method(#set, null),
      ).on(db.doc('users/alice/reviewLocks/mangai')).thenThrow(_unavailable());
      await FirestoreReviewRepository(db).createReview(_review());
      final review = (await db.collection('reviews').get()).docs.single;
      _expectEntry(
        await _singleEntry(db),
        collection: 'reviews',
        docId: review.id,
        placeId: 'mangai',
      );
    });
  });

  group('visita (F04)', () {
    test(
      'entrada no mesmo batch, com chaves exatas e at do servidor',
      () async {
        final db = FakeFirebaseFirestore();
        await FirestoreVisitRepository(db).createVisit(_visit());
        final visit = (await db.collection('visits').get()).docs.single;
        _expectEntry(
          await _singleEntry(db),
          collection: 'visits',
          docId: visit.id,
          placeId: 'mangai',
        );
      },
    );

    test('retry depois de falha: mesmo id, uma entrada só', () async {
      final db = FakeFirebaseFirestore();
      await db.doc('places/osm-n123').set({'name': 'Bar do Zé'});
      _placeRace(db);
      await FirestoreVisitRepository(
        db,
      ).createVisit(_visit(placeId: 'osm-n123'), newPlace: _discovered);
      final visit = (await db.collection('visits').get()).docs.single;
      _expectEntry(
        await _singleEntry(db),
        collection: 'visits',
        docId: visit.id,
        placeId: 'osm-n123',
      );
    });

    test('ack perdido: conclui sem reenviar e sem 2ª entrada', () async {
      final db = FakeFirebaseFirestore();
      var commits = 0;
      await FirestoreVisitRepository(
        db,
        commitBatch: (batch) async {
          commits++;
          await batch.commit();
          throw _unavailable();
        },
      ).createVisit(_visit());
      expect(commits, 1);
      expect(
        (await db.collection(auditLogCollection).get()).docs,
        hasLength(1),
      );
    });
  });

  group('relato (F04)', () {
    test(
      'entrada no mesmo batch, com chaves exatas e at do servidor',
      () async {
        final db = FakeFirebaseFirestore();
        await FirestoreOpenReportRepository(db).createReport(_report());
        final report = (await db.collection('openReports').get()).docs.single;
        _expectEntry(
          await _singleEntry(db),
          collection: 'openReports',
          docId: report.id,
          placeId: 'mangai',
        );
      },
    );

    test('retry depois de falha: mesmo id, uma entrada só', () async {
      final db = FakeFirebaseFirestore();
      await db.doc('places/osm-n123').set({'name': 'Bar do Zé'});
      _placeRace(db);
      await FirestoreOpenReportRepository(
        db,
      ).createReport(_report(placeId: 'osm-n123'), newPlace: _discovered);
      final report = (await db.collection('openReports').get()).docs.single;
      _expectEntry(
        await _singleEntry(db),
        collection: 'openReports',
        docId: report.id,
        placeId: 'osm-n123',
      );
    });

    test('ack perdido: conclui sem reenviar e sem 2ª entrada', () async {
      final db = FakeFirebaseFirestore();
      var commits = 0;
      await FirestoreOpenReportRepository(
        db,
        commitBatch: (batch) async {
          commits++;
          await batch.commit();
          throw _unavailable();
        },
      ).createReport(_report());
      expect(commits, 1);
      final report = (await db.collection('openReports').get()).docs.single;
      _expectEntry(
        await _singleEntry(db),
        collection: 'openReports',
        docId: report.id,
        placeId: 'mangai',
      );
    });

    test('commit negado sem gravar: nenhuma entrada', () async {
      final db = FakeFirebaseFirestore();
      await expectLater(
        FirestoreOpenReportRepository(
          db,
          commitBatch: (batch) async => throw _denied(),
        ).createReport(_report()),
        throwsA(isA<FirebaseException>()),
      );
      expect((await db.collection(auditLogCollection).get()).docs, isEmpty);
    });
  });
}
