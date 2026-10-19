import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mock_exceptions/mock_exceptions.dart';
import 'package:naarea/data/catalog/catalog_place_repository.dart';
import 'package:naarea/data/firebase/firestore_place_repository.dart';
import 'package:naarea/data/firebase/firestore_review_repository.dart';
import 'package:naarea/data/firebase/place_doc.dart';
import 'package:naarea/data/photon/photon_client.dart';
import 'package:naarea/data/repositories/place_repository.dart';
import 'package:naarea/domain/geo.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/domain/models/review.dart';
import 'package:naarea/domain/models/scores.dart';
import 'package:naarea/domain/search_tokens.dart';
import 'package:naarea/ui/review/review_view_model.dart';

import '../support/fakes.dart';
import '../support/photon_fixtures.dart';

/// Praça da Sé (SP).
const _se = (lat: -23.5503, lng: -46.6339);

/// Ponto a ~[meters] a leste de [from].
LatLng _east(double meters, {LatLng from = _se}) =>
    (lat: from.lat, lng: from.lng + meters / (111320 * 0.917));

Map<String, Object?> _feature(
  int id,
  String name, {
  double meters = 50,
  String type = 'N',
  String value = 'bar',
  LatLng? at,
}) {
  final p = at ?? _east(meters);
  return photonFeature(
    osmType: type,
    osmId: id,
    name: name,
    value: value,
    lat: p.lat,
    lng: p.lng,
  );
}

/// Doc gravado em `places` (seed de Natal, com campos de busca).
Future<void> _stored(
  FakeFirebaseFirestore db,
  String id,
  String name, {
  double meters = 50,
  String? osmId,
  String source = 'osm',
}) {
  final at = _east(meters);
  return db.doc('places/$id').set({
    'name': name,
    'category': 'Bar',
    'neighborhood': 'Sé',
    'city': 'São Paulo',
    'lat': at.lat,
    'lng': at.lng,
    'geohash': geohashEncode(at.lat, at.lng),
    'source': source,
    'osmId': ?osmId,
    'nameLower': nameLower(name),
    'searchTokens': searchTokens(name),
  });
}

FirebaseException _denied() =>
    FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');

FirebaseException _unavailable() =>
    FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');

/// `get()` sem opções (a 1ª leitura) falha; a releitura no servidor
/// (`GetOptions(source: server)`) funciona.
void _failFirstRead(DocumentReference<Object?> ref) {
  whenCalling(
    Invocation.method(#get, [null]),
  ).on(ref).thenThrow(_unavailable());
}

/// Toda leitura falha.
void _failAllReads(DocumentReference<Object?> ref) {
  whenCalling(Invocation.method(#get, null)).on(ref).thenThrow(_unavailable());
}

void _denyWrites(DocumentReference<Object?> ref) {
  whenCalling(Invocation.method(#set, null)).on(ref).thenThrow(_denied());
}

class _Env {
  _Env({List<Map<String, Object?>> features = const []})
    : _features = features {
    db = FakeFirebaseFirestore();
    firestore = FirestorePlaceRepository(db);
    photon = PhotonClient(
      client: MockClient((req) async {
        requests.add(req.url);
        if (photonFails) return http.Response('erro', 504);
        return photonResponse(_features);
      }),
    );
    repo = CatalogPlaceRepository(persisted: firestore, photon: photon);
  }

  List<Map<String, Object?>> _features;
  set features(List<Map<String, Object?>> f) => _features = f;
  late final FakeFirebaseFirestore db;
  late final FirestorePlaceRepository firestore;
  late final PhotonClient photon;
  late final CatalogPlaceRepository repo;
  final List<Uri> requests = [];
  bool photonFails = false;

  /// Descobre [id] pelo "Perto" e devolve o Place descoberto.
  Future<Place> discover(String id) async {
    await repo.nearby(_se.lat, _se.lng, 300);
    return repo.discoveredPlace(id)!;
  }
}

NewReview _review(String placeId, String placeName) => NewReview(
  authorId: 'bianca',
  authorName: 'Bianca',
  placeId: placeId,
  placeName: placeName,
  scores: Scores(food: 5),
);

void main() {
  group('nearby: Photon + gravados', () {
    test('lista do Photon por distância, como descobertos', () async {
      final env = _Env(
        features: [
          _feature(2, 'Boteco', meters: 200),
          _feature(1, 'Bar do Zé', meters: 80),
          _feature(3, 'Longe', meters: 600),
        ],
      );
      final result = await env.repo.nearby(_se.lat, _se.lng, 300);
      final list = result.places;
      expect(list.map((n) => n.place.id), ['osm-n1', 'osm-n2']);
      expect(list.first.distanceMeters, closeTo(80, 2));
      expect(list.every((n) => n.place.discovered), isTrue);
      expect(result.partial, isFalse);
      expect(result.capped, isFalse);
      expect(env.repo.discoveredPlace('osm-n1')?.name, 'Bar do Zé');
      expect(env.requests.single.path, '/reverse');
    });

    test(
      'local também no Firestore: um item só, com os dados gravados',
      () async {
        final env = _Env(
          features: [_feature(1, 'Bar do Zé (OSM)', meters: 80)],
        );
        await _stored(env.db, 'osm-n1', 'Bar do Zé', meters: 80);
        final list = (await env.repo.nearby(_se.lat, _se.lng, 300)).places;
        expect(list, hasLength(1));
        expect(list.single.place.id, 'osm-n1');
        expect(list.single.place.name, 'Bar do Zé');
        expect(list.single.place.discovered, isFalse);
        expect(env.repo.discoveredPlace('osm-n1'), isNull);
      },
    );

    test(
      'curado casado (osmId) e node/way unificado pelo seed não duplicam',
      () async {
        final env = _Env(
          features: [
            _feature(10, 'Mangai', meters: 100, type: 'W'),
            _feature(11, 'Camarões', meters: 150),
            _feature(12, 'Só no Photon', meters: 200),
          ],
        );
        await _stored(
          env.db,
          'mangai-natal',
          'Mangai',
          meters: 100,
          osmId: 'way/10',
          source: 'curated',
        );
        // O seed ficou com o way; o Photon devolveu o node, mesmo nome e célula.
        await _stored(env.db, 'osm-w99', 'Camarões', meters: 152);
        final list = (await env.repo.nearby(_se.lat, _se.lng, 300)).places;
        expect(list.map((n) => n.place.id), [
          'mangai-natal',
          'osm-w99',
          'osm-n12',
        ]);
      },
    );

    test(
      'Photon falha: mostra os gravados (haversine), marcado como parcial',
      () async {
        final env = _Env()..photonFails = true;
        await _stored(env.db, 'osm-n1', 'Bar do Zé', meters: 100);
        await _stored(env.db, 'osm-n2', 'Longe', meters: 400);
        final result = await env.repo.nearby(_se.lat, _se.lng, 300);
        expect(result.places.map((n) => n.place.id), ['osm-n1']);
        expect(result.partial, isTrue);
      },
    );

    test('Photon e Firestore falham: erro de tela inteira', () async {
      final env = _Env()..photonFails = true;
      final failing = CatalogPlaceRepository(
        persisted: FakePlaceRepository([])..fail = true,
        photon: env.photon,
      );
      await expectLater(
        failing.nearby(_se.lat, _se.lng, 300),
        throwsA(isA<PhotonException>()),
      );
    });

    test('Firestore falha e Photon responde: lista do Photon', () async {
      final env = _Env(features: [_feature(1, 'Bar do Zé', meters: 80)]);
      final repo = CatalogPlaceRepository(
        persisted: FakePlaceRepository([])..fail = true,
        photon: env.photon,
      );
      final result = await repo.nearby(_se.lat, _se.lng, 300);
      expect(result.places.single.place.id, 'osm-n1');
      expect(result.partial, isFalse);
    });

    test(
      'mesma célula: 1 consulta no centro dela (raio + 110 m); filtro pela posição exata',
      () async {
        final cell = geohashEncode(_se.lat, _se.lng, precision: 7);
        final center = geohashCenter(cell);
        // Dois pontos da mesma célula, a ~120 m um do outro.
        final a = (lat: center.lat, lng: center.lng - 0.0006);
        final b = (lat: center.lat, lng: center.lng + 0.0006);
        expect(geohashEncode(a.lat, a.lng, precision: 7), cell);
        expect(geohashEncode(b.lat, b.lng, precision: 7), cell);
        // A 290 m a leste de B: dentro de 300 m de B, fora de 300 m de A.
        final edge = _east(290, from: b);
        final env = _Env(features: [_feature(7, 'Borda', at: edge)]);
        final fromB = await env.repo.nearby(b.lat, b.lng, 300);
        final fromA = await env.repo.nearby(a.lat, a.lng, 300);
        expect(fromB.places.map((n) => n.place.id), ['osm-n7']);
        expect(fromB.places.single.distanceMeters, closeTo(290, 3));
        expect(fromA.places, isEmpty);
        expect(env.requests, hasLength(1));
        final q = env.requests.single.queryParameters;
        expect(q['lat'], center.lat.toStringAsFixed(6));
        expect(q['lon'], center.lng.toStringAsFixed(6));
        expect(q['radius'], '0.410');
      },
    );

    test('50 do Photon: capped', () async {
      final env = _Env(
        features: [
          for (var i = 1; i <= PhotonClient.reverseLimit; i++)
            _feature(i, 'Bar $i', meters: 10.0 + i),
        ],
      );
      final result = await env.repo.nearby(_se.lat, _se.lng, 300);
      expect(result.capped, isTrue);
      expect(result.places, hasLength(PhotonClient.reverseLimit));
    });
  });

  group('search: gravados primeiro, depois Photon', () {
    test(
      '20 do Photon + 3 gravados: os 3 gravados primeiro, total 20',
      () async {
        final env = _Env(
          features: [
            for (var i = 1; i <= 20; i++) _feature(i, 'Pizzaria Photon $i'),
          ],
        );
        for (final n in ['Pizzaria Amiga', 'Pizzaria Bela', 'Pizzaria Casa']) {
          await _stored(env.db, 'g-${n.split(' ').last}', n);
        }
        final list = await env.repo.search('pizzaria', near: _se);
        expect(list, hasLength(placeSearchLimit));
        expect(list.take(3).map((p) => p.id), ['g-Amiga', 'g-Bela', 'g-Casa']);
        expect(list.skip(3).every((p) => p.discovered), isTrue);
        expect(list.map((p) => p.id).toSet(), hasLength(20));
      },
    );

    test('mescla por id mantendo os dados gravados', () async {
      final env = _Env(
        features: [_feature(1, 'Pizzaria Bella'), _feature(2, 'Pizza Hut')],
      );
      // Gravado, mas a busca por tokens não o acha ("pizzaria" ≠ "pizza").
      await _stored(env.db, 'osm-n2', 'Pizza Hut Sé');
      final list = await env.repo.search('pizzaria', near: _se);
      expect(list.map((p) => p.id), ['osm-n1', 'osm-n2']);
      expect(list[1].name, 'Pizza Hut Sé');
      expect(list[1].discovered, isFalse);
      expect(list[0].discovered, isTrue);
    });

    test('menos de 3 caracteres: Photon não é consultado', () async {
      final env = _Env(features: [_feature(1, 'Bar')]);
      await _stored(env.db, 'g', 'Bar do Zé');
      final list = await env.repo.search('ba');
      expect(list.map((p) => p.id), ['g']);
      expect(env.requests, isEmpty);
    });

    test('Photon falha: devolve o que está gravado; sem nada, erro', () async {
      final env = _Env()..photonFails = true;
      await expectLater(
        env.repo.search('pizzaria'),
        throwsA(isA<PhotonException>()),
      );
      await _stored(env.db, 'p', 'Pizzaria Natal');
      final list = await env.repo.search('pizzaria');
      expect(list.single.id, 'p');
    });

    test(
      'Firestore falha e Photon vazio: erro (não "nenhum resultado")',
      () async {
        final env = _Env();
        final repo = CatalogPlaceRepository(
          persisted: FakePlaceRepository([])..fail = true,
          photon: env.photon,
        );
        await expectLater(repo.search('pizzaria'), throwsException);
        env.features = [_feature(1, 'Pizzaria Bella')];
        // Com resultados do Photon, mostra.
        final list = await repo.search('pizzaria bella');
        expect(list.single.id, 'osm-n1');
      },
    );
  });

  group('ensurePersisted (salvar/avaliar local novo)', () {
    test(
      'cria places/osm-… com o schema exato das Rules (sem campos de busca)',
      () async {
        final env = _Env(features: [_feature(123, 'Bar do Zé', meters: 80)]);
        final place = await env.discover('osm-n123');
        await env.repo.ensurePersisted(place, uid: 'bianca');
        final data = (await env.db.doc('places/osm-n123').get()).data()!;
        expect(data.keys.toSet(), {
          'name',
          'category',
          'neighborhood',
          'city',
          'address',
          'lat',
          'lng',
          'geohash',
          'osmId',
          'source',
          'createdBy',
          'createdAt',
        });
        expect(data['name'], 'Bar do Zé');
        expect(data['category'], 'Bar');
        expect(data['osmId'], 'node/123');
        expect(data['source'], 'osm');
        expect(data['createdBy'], 'bianca');
        expect(data['geohash'], geohashEncode(place.lat!, place.lng!));
        expect(data['createdAt'], isA<Timestamp>());
        expect(env.repo.discoveredPlace('osm-n123'), isNull);
        final got = await env.repo.getPlaces(['osm-n123']);
        expect(got['osm-n123']!.discovered, isFalse);
      },
    );

    test(
      'idempotente: chamadas simultâneas e repetidas criam uma vez',
      () async {
        final env = _Env(features: [_feature(123, 'Bar do Zé')]);
        final place = await env.discover('osm-n123');
        await Future.wait([
          env.repo.ensurePersisted(place, uid: 'a'),
          env.repo.ensurePersisted(place, uid: 'a'),
        ]);
        await env.repo.ensurePersisted(place, uid: 'a');
        expect(env.firestore.createCount, 1);
      },
    );

    test('outra pessoa já criou → segue sem gravar de novo', () async {
      final env = _Env(features: [_feature(123, 'Bar do Zé')]);
      final place = await env.discover('osm-n123');
      await _stored(env.db, 'osm-n123', 'Bar do Zé (de outra pessoa)');
      await env.repo.ensurePersisted(place, uid: 'bianca');
      expect(env.firestore.createCount, 0);
      final data = (await env.db.doc('places/osm-n123').get()).data()!;
      expect(data['name'], 'Bar do Zé (de outra pessoa)');
    });

    test(
      'corrida: set negado, mas o doc já existe (releitura no servidor) → sucesso',
      () async {
        final env = _Env(features: [_feature(123, 'Bar do Zé')]);
        final place = await env.discover('osm-n123');
        await _stored(env.db, 'osm-n123', 'Bar do Zé (de outra pessoa)');
        final ref = env.db.doc('places/osm-n123');
        _failFirstRead(ref); // a 1ª leitura não vê o doc
        _denyWrites(ref); // o create vira update: negado
        await env.repo.ensurePersisted(place, uid: 'bianca');
        expect(env.firestore.createCount, 1);
        expect(env.repo.discoveredPlace('osm-n123'), isNull);
        final got = await env.repo.getPlaces(['osm-n123']);
        expect(got['osm-n123']!.name, 'Bar do Zé (de outra pessoa)');
      },
    );

    test('set negado e o doc não existe: o erro sobe', () async {
      final env = _Env(features: [_feature(123, 'Bar do Zé')]);
      final place = await env.discover('osm-n123');
      _denyWrites(env.db.doc('places/osm-n123'));
      await expectLater(
        env.repo.ensurePersisted(place, uid: 'bianca'),
        throwsA(
          isA<FirebaseException>().having(
            (e) => e.code,
            'code',
            'permission-denied',
          ),
        ),
      );
      expect(env.repo.discoveredPlace('osm-n123'), isNotNull);
    });

    test('releitura também falha: sobe o erro ORIGINAL do set', () async {
      final env = _Env(features: [_feature(123, 'Bar do Zé')]);
      final place = await env.discover('osm-n123');
      final ref = env.db.doc('places/osm-n123');
      _failAllReads(ref);
      _denyWrites(ref);
      await expectLater(
        env.repo.ensurePersisted(place, uid: 'bianca'),
        throwsA(
          isA<FirebaseException>().having(
            (e) => e.code,
            'code',
            'permission-denied',
          ),
        ),
      );
    });

    test(
      'doc existente porém malformado: não cria, e o cache do id é limpo',
      () async {
        final env = _Env(features: [_feature(123, 'Bar do Zé')]);
        final place = await env.discover('osm-n123');
        // Lido antes como ausente (cache de "não existe").
        expect(await env.firestore.getPlaces(['osm-n123']), isEmpty);
        await env.db.doc('places/osm-n123').set({'name': 42});
        await env.repo.ensurePersisted(place, uid: 'bianca');
        expect(env.firestore.createCount, 0);
        // Conserto do doc: a próxima leitura relê (não ficou "ausente").
        await env.db.doc('places/osm-n123').set({'name': 'Bar do Zé'});
        final got = await env.firestore.getPlaces(['osm-n123']);
        expect(got['osm-n123']?.name, 'Bar do Zé');
      },
    );

    test('local já gravado (não descoberto): nada a fazer', () async {
      final env = _Env();
      await env.repo.ensurePersisted(
        const Place(
          id: 'mangai-natal',
          name: 'Mangai',
          category: 'Restaurante',
          neighborhood: 'Tirol',
          city: 'Natal',
        ),
        uid: 'a',
      );
      expect(env.firestore.createCount, 0);
      expect((await env.db.collection('places').get()).docs, isEmpty);
    });
  });

  group('ensurePlaceForSave', () {
    test('descoberto: cria o local', () async {
      final env = _Env(features: [_feature(123, 'Bar do Zé')]);
      await env.discover('osm-n123');
      await ensurePlaceForSave(env.repo, uid: 'bianca', placeId: 'osm-n123');
      expect(
        (await env.db.doc('places/osm-n123').get()).data()!['createdBy'],
        'bianca',
      );
    });

    test('gravado: só confirma, sem escrever', () async {
      final env = _Env();
      await _stored(env.db, 'osm-n5', 'Bar');
      await ensurePlaceForSave(env.repo, uid: 'bianca', placeId: 'osm-n5');
      expect(env.firestore.createCount, 0);
    });

    test('nem descoberto nem gravado: falha', () async {
      final env = _Env();
      await expectLater(
        ensurePlaceForSave(env.repo, uid: 'bianca', placeId: 'osm-n404'),
        throwsStateError,
      );
    });
  });

  group('canCreatePlace / newPlaceData', () {
    Place discovered({
      String id = 'osm-n1',
      String name = 'Bar',
      String category = 'Bar',
      double lat = -23.55,
      double lng = -46.63,
      String neighborhood = '',
    }) => Place(
      id: id,
      name: name,
      category: category,
      neighborhood: neighborhood,
      city: '',
      lat: lat,
      lng: lng,
      source: PlaceSource.osm,
      discovered: true,
    );

    test('só o que as Rules aceitam', () {
      expect(canCreatePlace(discovered()), isTrue);
      expect(canCreatePlace(discovered(id: 'mangai-natal')), isFalse);
      expect(canCreatePlace(discovered(id: 'osm-n0123')), isFalse);
      expect(canCreatePlace(discovered(category: 'Local')), isFalse);
      expect(canCreatePlace(discovered(lat: 38.7, lng: -9.1)), isFalse);
      expect(canCreatePlace(discovered(name: 'x' * 121)), isFalse);
      expect(
        () => newPlaceData(discovered(category: 'Local'), uid: 'a'),
        throwsArgumentError,
      );
    });

    test('textos cortados sem partir emoji (posição 120)', () {
      final data = newPlaceData(
        discovered(neighborhood: '${'x' * 119}😀 resto'),
        uid: 'a',
      );
      expect(data['neighborhood'], 'x' * 119);
      expect(data.containsKey('searchTokens'), isFalse);
      expect(data.containsKey('nameLower'), isFalse);
    });
  });

  group('FirestoreReviewRepository.createReview com local novo (G2)', () {
    test('local ausente: batch cria places/osm-… e a avaliação', () async {
      final env = _Env(features: [_feature(123, 'Bar do Zé')]);
      final place = await env.discover('osm-n123');
      final result = await FirestoreReviewRepository(env.db).createReview(
        _review(place.id, place.name),
        newPlace: place,
        photo: Uint8List.fromList([0xFF, 0xD8, 0xFF, 1]),
      );
      expect(result.placeCreated, isTrue);
      final created = (await env.db.doc('places/osm-n123').get()).data()!;
      expect(created['createdBy'], 'bianca');
      final review = (await env.db.collection('reviews').get()).docs.single;
      expect(review.data()['placeId'], 'osm-n123');
      expect(review.data()['placeName'], 'Bar do Zé');
      expect(
        (await env.db.collection('reviewPhotos').get()).docs,
        hasLength(1),
      );
    });

    test(
      'local já existe com outro nome: a avaliação usa o nome gravado',
      () async {
        final env = _Env(features: [_feature(123, 'Bar do Zé')]);
        final place = await env.discover('osm-n123');
        await _stored(env.db, 'osm-n123', 'Bar do Zé (nome antigo)');
        _denyWrites(env.db.doc('places/osm-n123'));
        final result = await FirestoreReviewRepository(
          env.db,
        ).createReview(_review(place.id, place.name), newPlace: place);
        expect(result.placeCreated, isFalse);
        final review = (await env.db.collection('reviews').get()).docs.single;
        expect(review.data()['placeName'], 'Bar do Zé (nome antigo)');
        final data = (await env.db.doc('places/osm-n123').get()).data()!;
        expect(data.containsKey('createdBy'), isFalse);
      },
    );

    test(
      'corrida: 1º commit falha com o local nascendo no meio → 1 review, local pré-existente',
      () async {
        final env = _Env(features: [_feature(123, 'Bar do Zé')]);
        final place = await env.discover('osm-n123');
        // Outra pessoa criou o local; a 1ª leitura não o viu (falhou) e o
        // create dentro do batch vira update: negado, derrubando o batch.
        await _stored(env.db, 'osm-n123', 'Bar do Zé (de outra pessoa)');
        final ref = env.db.doc('places/osm-n123');
        _failFirstRead(ref);
        _denyWrites(ref);
        final result = await FirestoreReviewRepository(
          env.db,
        ).createReview(_review(place.id, place.name), newPlace: place);
        expect(result.placeCreated, isFalse);
        final reviews = (await env.db.collection('reviews').get()).docs;
        expect(reviews, hasLength(1));
        expect(
          reviews.single.data()['placeName'],
          'Bar do Zé (de outra pessoa)',
        );
        // (a leitura sem opções está "falhando" neste teste)
        final data = (await ref.get(
          const GetOptions(source: Source.server),
        )).data()!;
        expect(data['name'], 'Bar do Zé (de outra pessoa)');
        expect(data.containsKey('createdBy'), isFalse);
        // F03: o retry grava a trava apontando para a mesma review.
        final lock =
            (await env.db.doc('users/bianca/reviewLocks/osm-n123').get())
                .data()!;
        expect(lock['reviewId'], reviews.single.id);
        expect(lock['placeId'], 'osm-n123');
      },
    );

    test(
      'commit falha e a releitura também: sobe o erro ORIGINAL, nada gravado',
      () async {
        final env = _Env(features: [_feature(123, 'Bar do Zé')]);
        final place = await env.discover('osm-n123');
        final ref = env.db.doc('places/osm-n123');
        _failAllReads(ref);
        _denyWrites(ref);
        await expectLater(
          FirestoreReviewRepository(
            env.db,
          ).createReview(_review(place.id, place.name), newPlace: place),
          throwsA(
            isA<FirebaseException>().having(
              (e) => e.code,
              'code',
              'permission-denied',
            ),
          ),
        );
        expect((await env.db.collection('reviews').get()).docs, isEmpty);
      },
    );

    test('local gravado (não descoberto): não lê nem cria places', () async {
      final db = FakeFirebaseFirestore();
      final result = await FirestoreReviewRepository(db).createReview(
        _review('mangai', 'Mangai'),
        newPlace: const Place(
          id: 'mangai',
          name: 'Mangai',
          category: 'Restaurante',
          neighborhood: 'Tirol',
          city: 'Natal',
        ),
      );
      expect(result.placeCreated, isFalse);
      expect((await db.collection('places').get()).docs, isEmpty);
      expect((await db.collection('reviews').get()).docs, hasLength(1));
    });

    test('newPlace de outro local é erro de programação', () {
      final db = FakeFirebaseFirestore();
      expect(
        () => FirestoreReviewRepository(db).createReview(
          _review('osm-n1', 'A'),
          newPlace: const Place(
            id: 'osm-n2',
            name: 'B',
            category: 'Bar',
            neighborhood: '',
            city: '',
            discovered: true,
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  group('ponta a ponta: buscar → avaliar → getPlaces (repositórios reais)', () {
    ReviewViewModel vmFor(_Env env, Place place) {
      final users = FakeUserRepository()..addUser('bianca', 'Bianca');
      return ReviewViewModel(
        place: place,
        authRepository: FakeAuthRepository(uid: 'bianca'),
        userRepository: users,
        reviewRepository: FirestoreReviewRepository(env.db),
        photoPicker: FakePhotoPicker(),
        placeRepository: env.repo,
        compress: (b) async => b,
      )..setFood(5);
    }

    test(
      'criou o local: getPlaces devolve gravado (discovered false)',
      () async {
        final env = _Env(features: [_feature(123, 'Bar do Zé')]);
        final place = (await env.repo.search(
          'bar do',
          near: _se,
        )).singleWhere((p) => p.id == 'osm-n123');
        expect(place.discovered, isTrue);
        expect(await vmFor(env, place).submit(), isTrue);
        final got = await env.repo.getPlaces(['osm-n123']);
        expect(got['osm-n123']!.discovered, isFalse);
        expect(
          (await env.db.doc('places/osm-n123').get()).data()!['createdBy'],
          'bianca',
        );
      },
    );

    test(
      'outra pessoa criou antes: cache invalidado, getPlaces relê o doc gravado',
      () async {
        final env = _Env(features: [_feature(123, 'Bar do Zé')]);
        final place = (await env.repo.search(
          'bar do',
          near: _se,
        )).singleWhere((p) => p.id == 'osm-n123');
        // A busca já registrou o id como ausente no cache do Firestore.
        await _stored(env.db, 'osm-n123', 'Bar do Zé (gravado)');
        expect(await vmFor(env, place).submit(), isTrue);
        final got = await env.repo.getPlaces(['osm-n123']);
        expect(got['osm-n123']!.discovered, isFalse);
        expect(got['osm-n123']!.name, 'Bar do Zé (gravado)');
      },
    );
  });
}
