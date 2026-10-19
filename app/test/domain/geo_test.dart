import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/geo.dart';

/// Vetores gerados com o próprio `geofire-common` (ver `_comment` no
/// arquivo); `firebase/tests/osm.test.js` confere o geohash do seed contra os
/// mesmos.
final _fixture =
    jsonDecode(File('../firebase/tests/fixtures/geo.json').readAsStringSync())
        as Map<String, dynamic>;

List<Map<String, dynamic>> _cases(String key) =>
    (_fixture[key] as List).cast<Map<String, dynamic>>();

double _d(Object? v) => (v as num).toDouble();

void main() {
  group('geohashEncode', () {
    for (final c in _cases('geohash')) {
      test('(${c['lat']}, ${c['lng']}) = geofire-common', () {
        final lat = _d(c['lat']), lng = _d(c['lng']);
        final expected = c['expected'] as String;
        expect(
          geohashEncode(lat, lng, precision: c['precision'] as int),
          expected,
        );
        // O seed grava precisão 9 (prefixo do mesmo hash).
        expect(geohashEncode(lat, lng), expected.substring(0, 9));
      });
    }

    test('mesmo valor que o seed grava (osm.test.js)', () {
      expect(geohashEncode(57.64911, 10.40744, precision: 11), 'u4pruydqqvj');
      expect(geohashEncode(-5.8031189, -35.2199833), '7nyyyx9d6');
    });

    test('geohashCenter fica dentro da própria célula', () {
      for (final c in _cases('geohash')) {
        final hash = geohashEncode(_d(c['lat']), _d(c['lng']), precision: 7);
        final center = geohashCenter(hash);
        expect(geohashEncode(center.lat, center.lng, precision: 7), hash);
      }
      expect(() => geohashCenter('7a'), throwsArgumentError);
    });
  });

  group('geohashQueryBounds (algoritmo do geofire-common)', () {
    for (final c in _cases('bounds')) {
      test('(${c['lat']}, ${c['lng']}) raio ${c['radius']} m', () {
        final bounds = geohashQueryBounds((
          lat: _d(c['lat']),
          lng: _d(c['lng']),
        ), _d(c['radius']));
        final expected = [
          for (final b in c['expected'] as List)
            (start: (b as List)[0] as String, end: b[1] as String),
        ];
        expect(bounds, expected);
        expect(bounds.length, lessThanOrEqualTo(9));
      });
    }

    test('toda posição dentro do raio cai em alguma faixa', () {
      const center = (lat: -5.8817, lng: -35.1708);
      for (final radius in [300.0, 1000.0, 3000.0]) {
        final bounds = geohashQueryBounds(center, radius);
        // Pontos na borda do círculo, em 16 direções.
        for (var i = 0; i < 16; i++) {
          final angle = i * math.pi / 8;
          final dLat = radius * 0.999 / 110574 * math.cos(angle);
          final dLng = radius * 0.999 / (111320 * 0.99474) * math.sin(angle);
          final p = (lat: center.lat + dLat, lng: center.lng + dLng);
          if (distanceMeters(center, p) > radius) continue;
          final hash = geohashEncode(p.lat, p.lng);
          expect(
            bounds.any(
              (b) => hash.compareTo(b.start) >= 0 && hash.compareTo(b.end) <= 0,
            ),
            isTrue,
            reason: 'raio $radius, direção $i ($hash)',
          );
        }
      }
    });
  });

  group('distanceMeters (haversine)', () {
    for (final c in _cases('distance')) {
      test('${c['a']} → ${c['b']}', () {
        final a = c['a'] as List, b = c['b'] as List;
        expect(
          distanceMeters(
            (lat: _d(a[0]), lng: _d(a[1])),
            (lat: _d(b[0]), lng: _d(b[1])),
          ),
          closeTo(_d(c['expectedMeters']), 0.01),
        );
      });
    }

    test('mesmo ponto = 0; simétrica', () {
      const a = (lat: -5.88, lng: -35.17);
      const b = (lat: -5.87, lng: -35.16);
      expect(distanceMeters(a, a), 0);
      expect(distanceMeters(a, b), closeTo(distanceMeters(b, a), 1e-9));
    });
  });

  group('formatDistance / spokenDistance', () {
    test('metros de 10 em 10 abaixo de 1 km', () {
      expect(formatDistance(80), '80 m');
      expect(formatDistance(83), '80 m');
      expect(formatDistance(250), '250 m');
      expect(formatDistance(950), '950 m');
      expect(formatDistance(3), '10 m');
      expect(formatDistance(0), '10 m');
    });

    test('km com uma casa e vírgula', () {
      expect(formatDistance(1240), '1,2 km');
      expect(formatDistance(996), '1 km');
      expect(formatDistance(1000), '1 km');
      expect(formatDistance(2960), '3 km');
      expect(formatDistance(9940), '9,9 km');
      expect(formatDistance(12400), '12 km');
    });

    test('falada', () {
      expect(spokenDistance(120), 'a 120 metros');
      expect(spokenDistance(1000), 'a 1 quilômetro');
      expect(spokenDistance(1240), 'a 1,2 quilômetros');
    });
  });

  test('área atendida (G2): o Brasil inteiro; Lisboa e Montevidéu não', () {
    expect(inServiceArea((lat: -5.8817, lng: -35.1708)), isTrue); // Natal
    expect(inServiceArea((lat: -23.5503, lng: -46.6339)), isTrue); // SP, Sé
    expect(inServiceArea((lat: -3.8549, lng: -32.4243)), isTrue); // Noronha
    expect(inServiceArea((lat: -33.6866, lng: -53.4567)), isTrue); // Chuí
    expect(inServiceArea((lat: 38.7223, lng: -9.1393)), isFalse); // Lisboa
    expect(inServiceArea((lat: -34.9011, lng: -56.1645)), isFalse);
    expect(inBrazilBounds(brazilCenter), isTrue);
  });

  test('brazilBounds = inBrazilBounds() das Rules (paridade)', () {
    final rules = File('../firebase/firestore.rules').readAsStringSync();
    final fn = RegExp(
      r'function inBrazilBounds\(lat, lng\) \{([\s\S]*?)\}',
    ).firstMatch(rules);
    expect(fn, isNotNull, reason: 'inBrazilBounds() não está nas Rules');
    double bound(String v, String op) {
      final m = RegExp('$v $op (-?[0-9.]+)').firstMatch(fn!.group(1)!);
      expect(m, isNotNull, reason: '$v $op ausente');
      return double.parse(m!.group(1)!);
    }

    expect(bound('lat', '>='), brazilBounds.south);
    expect(bound('lat', '<='), brazilBounds.north);
    expect(bound('lng', '>='), brazilBounds.west);
    expect(bound('lng', '<='), brazilBounds.east);
  });
}
