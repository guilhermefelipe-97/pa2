import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:naarea/data/photon/photon_client.dart';
import 'package:naarea/domain/geo.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/domain/osm_category.dart';

import '../support/photon_fixtures.dart';

void main() {
  const se = (lat: -23.5503, lng: -46.6339);

  group('placeFromFeature', () {
    test(
      'local do Photon vira Place descoberto, com id e categoria do OSM',
      () {
        final p = PhotonClient.placeFromFeature(
          photonFeature(
            osmType: 'N',
            osmId: 123,
            name: ' Bar do Zé ',
            value: 'bar',
            lat: -23.55031234,
            lng: -46.63391234,
            district: 'Sé',
            city: 'São Paulo',
            street: 'Praça da Sé',
            housenumber: '1',
          ),
        )!;
        expect(p.id, 'osm-n123');
        expect(p.osmId, 'node/123');
        expect(p.name, 'Bar do Zé');
        expect(p.category, 'Bar');
        expect(p.neighborhood, 'Sé');
        expect(p.city, 'São Paulo');
        expect(p.address, 'Praça da Sé, 1');
        expect(p.lat, -23.5503123);
        expect(p.lng, -46.6339123);
        expect(p.geohash, geohashEncode(p.lat!, p.lng!));
        expect(p.geohash, hasLength(9));
        expect(p.source, PlaceSource.osm);
        expect(p.discovered, isTrue);
        expect(p.inCatalog, isTrue);
        expect(p.hasOsmData, isTrue);
      },
    );

    test('way e relation; categoria pt-BR do vocabulário', () {
      expect(
        PhotonClient.placeFromFeature(
          photonFeature(osmType: 'W', osmId: 45, value: 'fast_food'),
        )!.id,
        'osm-w45',
      );
      final r = PhotonClient.placeFromFeature(
        photonFeature(osmType: 'R', osmId: 7, value: 'food_court'),
      )!;
      expect(r.id, 'osm-r7');
      expect(r.category, 'Praça de alimentação');
      for (final a in osmAmenities) {
        final p = PhotonClient.placeFromFeature(photonFeature(value: a))!;
        expect(osmCategories, contains(p.category));
      }
    });

    test('bairro: district; sem ele, locality; sem endereço = null', () {
      final p = PhotonClient.placeFromFeature(
        photonFeature(district: null, locality: 'Vila Madalena'),
      )!;
      expect(p.neighborhood, 'Vila Madalena');
      expect(p.address, isNull);
      final q = PhotonClient.placeFromFeature(
        photonFeature(district: null, street: 'Rua Augusta'),
      )!;
      expect(q.neighborhood, '');
      expect(q.address, 'Rua Augusta');
    });

    test('sem nome, fora do Brasil, não-amenity ou malformado: descartado', () {
      expect(PhotonClient.placeFromFeature(photonFeature(name: null)), isNull);
      expect(PhotonClient.placeFromFeature(photonFeature(name: '  ')), isNull);
      expect(
        PhotonClient.placeFromFeature(
          photonFeature(name: 'x' * (PhotonClient.maxNameLength + 1)),
        ),
        isNull,
      );
      expect(
        PhotonClient.placeFromFeature(
          photonFeature(countrycode: 'PT', lat: 38.72, lng: -9.14),
        ),
        isNull,
      );
      // countrycode BR mas coordenada fora do retângulo: não confia.
      expect(
        PhotonClient.placeFromFeature(photonFeature(lat: 38.72, lng: -9.14)),
        isNull,
      );
      expect(PhotonClient.placeFromFeature(photonFeature(key: 'shop')), isNull);
      expect(
        PhotonClient.placeFromFeature(photonFeature(value: 'nightclub')),
        isNull,
      );
      expect(
        PhotonClient.placeFromFeature(photonFeature(osmType: 'X')),
        isNull,
      );
      expect(PhotonClient.placeFromFeature(photonFeature(osmId: 0)), isNull);
      expect(PhotonClient.placeFromFeature({'properties': {}}), isNull);
      expect(PhotonClient.placeFromFeature('lixo'), isNull);
      final noCoords = photonFeature();
      (noCoords['geometry'] as Map)['coordinates'] = ['a', 'b'];
      expect(PhotonClient.placeFromFeature(noCoords), isNull);
    });

    test('countrycode em minúsculas também vale', () {
      expect(
        PhotonClient.placeFromFeature(photonFeature(countrycode: 'br')),
        isNotNull,
      );
    });
  });

  group('reverse (Perto)', () {
    test('monta a URL: raio em km, osm_tag de cada amenity, limite', () async {
      late Uri seen;
      late Map<String, String> headers;
      final client = PhotonClient(
        client: MockClient((req) async {
          seen = req.url;
          headers = req.headers;
          return photonResponse([photonFeature()]);
        }),
        sendIdentityHeaders: true,
      );
      final page = await client.reverse(se, 1000);
      expect(page.places.single.id, 'osm-n1');
      expect(page.capped, isFalse);
      // Só o centro da célula de geohash 7 sai do aparelho, com a folga.
      final center = geohashCenter(geohashEncode(se.lat, se.lng, precision: 7));
      expect(seen.host, 'photon.komoot.io');
      expect(seen.path, '/reverse');
      expect(seen.queryParameters['lat'], center.lat.toStringAsFixed(6));
      expect(seen.queryParameters['lon'], center.lng.toStringAsFixed(6));
      expect(seen.queryParameters['lat'], isNot('-23.550300'));
      expect(seen.queryParameters['radius'], '1.110');
      expect(seen.queryParameters['limit'], '${PhotonClient.reverseLimit}');
      expect(seen.queryParametersAll['osm_tag'], [
        for (final a in osmAmenities) 'amenity:$a',
      ]);
      expect(headers['User-Agent'], PhotonClient.userAgent);
      expect(headers['Referer'], PhotonClient.referer);
    });

    test(
      'endpoint configurável (PHOTON_URL), com ou sem barra final',
      () async {
        final urls = <Uri>[];
        final mock = MockClient((req) async {
          urls.add(req.url);
          return photonResponse(const []);
        });
        await PhotonClient(
          client: mock,
          baseUrl: 'http://10.0.0.5:2322/',
        ).reverse(se, 300);
        await PhotonClient(
          client: mock,
          baseUrl: 'https://geo.exemplo.br/photon',
        ).search('pizza');
        expect(urls[0].toString(), startsWith('http://10.0.0.5:2322/reverse?'));
        expect(
          urls[1].toString(),
          startsWith('https://geo.exemplo.br/photon/api?'),
        );
      },
    );

    test('filtra fora do Brasil, sem nome e repetidos', () async {
      final client = PhotonClient(
        client: MockClient(
          (_) async => photonResponse([
            photonFeature(osmId: 1),
            photonFeature(osmId: 1),
            photonFeature(osmId: 2, name: null),
            photonFeature(osmId: 3, countrycode: 'PY', lat: -25.3, lng: -57.6),
            photonFeature(osmId: 4, osmType: 'W'),
          ]),
        ),
      );
      final page = await client.reverse(se, 300);
      expect(page.places.map((p) => p.id), ['osm-n1', 'osm-w4']);
    });

    test(
      'cache por (célula de geohash 7, raio); falha não fica no cache',
      () async {
        var calls = 0;
        var fail = true;
        final client = PhotonClient(
          client: MockClient((_) async {
            calls++;
            if (fail) return http.Response('erro', 503);
            return photonResponse([photonFeature()]);
          }),
        );
        await expectLater(
          client.reverse(se, 300),
          throwsA(isA<PhotonException>()),
        );
        fail = false;
        await client.reverse(se, 300);
        // Mesma célula de ~150 m: do cache.
        await client.reverse((lat: se.lat + 0.0001, lng: se.lng), 300);
        expect(calls, 2);
        await client.reverse(se, 1000);
        expect(calls, 3);
        expect(client.requestCount, 3);
      },
    );

    test(
      'HTTP ≠ 200, JSON inválido e erro de rede viram PhotonException',
      () async {
        for (final mock in [
          MockClient((_) async => http.Response('x', 500)),
          MockClient((_) async => http.Response('<html>', 200)),
          MockClient((_) async => http.Response('{"type":"x"}', 200)),
          MockClient((_) async => throw http.ClientException('offline')),
        ]) {
          await expectLater(
            PhotonClient(client: mock).reverse(se, 300),
            throwsA(isA<PhotonException>()),
          );
        }
      },
    );

    test('tempo esgotado (10 s) vira PhotonException', () {
      fakeAsync((async) {
        final never = Completer<http.Response>();
        final client = PhotonClient(client: MockClient((_) => never.future));
        expect(client.timeout, const Duration(seconds: 10));
        Object? error;
        client
            .reverse(se, 300)
            .then<void>((_) {}, onError: (Object e) => error = e);
        async.elapse(const Duration(seconds: 9));
        expect(error, isNull);
        async.elapse(const Duration(seconds: 2));
        expect(error, isA<PhotonException>());
      });
    });
  });

  group('search (seletor)', () {
    test('q, viés pela posição e bbox do Brasil', () async {
      late Uri seen;
      final client = PhotonClient(
        client: MockClient((req) async {
          seen = req.url;
          return photonResponse([photonFeature(name: 'Pizzaria Bella')]);
        }),
      );
      const fortaleza = (lat: -3.7319, lng: -38.5267);
      final list = await client.search(' pizzaria ', near: fortaleza);
      expect(list.single.name, 'Pizzaria Bella');
      expect(seen.path, '/api');
      expect(seen.queryParameters['q'], 'pizzaria');
      // Viés arredondado a 3 casas (~100 m), nunca a posição exata.
      expect(seen.queryParameters['lat'], '-3.732');
      expect(seen.queryParameters['lon'], '-38.527');
      expect(seen.queryParameters['bbox'], '-74.0,-34.0,-28.5,5.5');
      expect(seen.queryParameters['limit'], '${PhotonClient.searchLimit}');
      expect(
        seen.queryParametersAll['osm_tag'],
        hasLength(osmAmenities.length),
      );
    });

    test('sem posição (ou fora do Brasil): viés no centro do Brasil', () async {
      final seen = <Uri>[];
      final client = PhotonClient(
        client: MockClient((req) async {
          seen.add(req.url);
          return photonResponse(const []);
        }),
      );
      await client.search('pizzaria');
      await client.search('bar', near: (lat: 38.72, lng: -9.14));
      for (final u in seen) {
        expect(u.queryParameters['lat'], brazilCenter.lat.toStringAsFixed(3));
        expect(u.queryParameters['lon'], brazilCenter.lng.toStringAsFixed(3));
      }
    });

    test(
      'consulta vazia não vai à rede; cache por consulta normalizada',
      () async {
        var calls = 0;
        final client = PhotonClient(
          client: MockClient((_) async {
            calls++;
            return photonResponse(const []);
          }),
        );
        expect(await client.search('   '), isEmpty);
        // Menos de 3 caracteres não vai ao Photon.
        expect(await client.search('ba'), isEmpty);
        expect(await client.search(' çá '), isEmpty);
        expect(calls, 0);
        await client.search('Café');
        await client.search('  cafe ');
        expect(calls, 1);
        await client.search('cafe', near: se);
        expect(calls, 2);
      },
    );
  });

  group('uso justo', () {
    test('HTTP 429: 60 s sem nenhuma requisição, depois volta', () async {
      var now = DateTime.utc(2026, 10, 12, 12);
      var calls = 0;
      var status = 429;
      final client = PhotonClient(
        clock: () => now,
        client: MockClient((_) async {
          calls++;
          return status == 200
              ? photonResponse([photonFeature()])
              : http.Response('', status);
        }),
      );
      await expectLater(
        client.reverse(se, 300),
        throwsA(isA<PhotonRateLimitedException>()),
      );
      expect(calls, 1);
      status = 200;
      now = now.add(const Duration(seconds: 59));
      await expectLater(
        client.search('pizzaria'),
        throwsA(isA<PhotonRateLimitedException>()),
      );
      await expectLater(
        client.reverse(se, 300),
        throwsA(isA<PhotonRateLimitedException>()),
      );
      expect(calls, 1);
      now = now.add(const Duration(seconds: 2));
      expect((await client.reverse(se, 300)).places, hasLength(1));
      expect(calls, 2);
      expect(
        PhotonRateLimitedException.userMessage,
        'Muitas buscas seguidas — tente de novo em instantes',
      );
    });

    test('limite de 50 no /reverse: capped', () async {
      final client = PhotonClient(
        client: MockClient(
          (_) async => photonResponse([
            for (var i = 1; i <= PhotonClient.reverseLimit; i++)
              photonFeature(osmId: i),
          ]),
        ),
      );
      final page = await client.reverse(se, 3000);
      expect(page.capped, isTrue);
      expect(page.places, hasLength(PhotonClient.reverseLimit));
    });

    test('cache expira em 30 min', () async {
      var now = DateTime.utc(2026, 10, 12, 12);
      var calls = 0;
      final client = PhotonClient(
        clock: () => now,
        client: MockClient((_) async {
          calls++;
          return photonResponse(const []);
        }),
      );
      await client.reverse(se, 300);
      now = now.add(const Duration(minutes: 29));
      await client.reverse(se, 300);
      expect(calls, 1);
      now = now.add(const Duration(minutes: 2));
      await client.reverse(se, 300);
      expect(calls, 2);
    });
  });

  test('textos cortados sem partir emoji (posição 120)', () {
    final p = PhotonClient.placeFromFeature(
      photonFeature(district: '${'x' * 119}😀 depois'),
    )!;
    expect(p.neighborhood, 'x' * 119);
  });
}
