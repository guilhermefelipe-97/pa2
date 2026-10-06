import 'dart:math' as math;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/data/firebase/firestore_place_repository.dart';
import 'package:naarea/domain/geo.dart';

/// Ponta Negra (Natal).
const _here = (lat: -5.8817, lng: -35.1708);

/// Ponto a [meters] de [_here] na direção [bearingDeg] (0 = norte), na
/// mesma esfera do haversine.
LatLng _at(double meters, [double bearingDeg = 90]) {
  double rad(double d) => d * math.pi / 180;
  double deg(double r) => r * 180 / math.pi;
  final d = meters / earthRadiusMeters;
  final b = rad(bearingDeg);
  final lat1 = rad(_here.lat), lng1 = rad(_here.lng);
  final lat2 = math.asin(
    math.sin(lat1) * math.cos(d) + math.cos(lat1) * math.sin(d) * math.cos(b),
  );
  final lng2 =
      lng1 +
      math.atan2(
        math.sin(b) * math.sin(d) * math.cos(lat1),
        math.cos(d) - math.sin(lat1) * math.sin(lat2),
      );
  return (lat: deg(lat2), lng: deg(lng2));
}

Future<void> _place(
  FakeFirebaseFirestore db,
  String id, {
  LatLng? at,
  bool withGeohash = true,
  String? name,
}) => db.doc('places/$id').set({
  'name': name ?? id,
  'category': 'Restaurante',
  'neighborhood': 'Ponta Negra',
  'city': 'Natal',
  if (at != null) ...{
    'lat': at.lat,
    'lng': at.lng,
    if (withGeohash) 'geohash': geohashEncode(at.lat, at.lng),
  },
});

void main() {
  group('FirestorePlaceRepository.nearby', () {
    late FakeFirebaseFirestore db;
    late FirestorePlaceRepository repo;

    setUp(() async {
      db = FakeFirebaseFirestore();
      repo = FirestorePlaceRepository(db);
      await _place(db, 'b250', at: _at(250, 200));
      await _place(db, 'a80', at: _at(80, 10));
      await _place(db, 'c299', at: _at(299, 300));
      await _place(db, 'fora301', at: _at(301, 45));
      await _place(db, 'longe', at: _at(5000));
      await _place(db, 'curado-sem-coordenada');
      // Coordenadas sem geohash (não deveria existir após o seed): fica fora
      // da consulta por faixa.
      await _place(db, 'sem-geohash', at: _at(50), withGeohash: false);
    });

    test('só o que está no raio, ordenado por distância real', () async {
      final found = await repo.nearby(_here.lat, _here.lng, 300);
      expect(found.map((n) => n.place.id), ['a80', 'b250', 'c299']);
      expect(found[0].distanceMeters, closeTo(80, 0.01));
      expect(found[1].distanceMeters, closeTo(250, 0.01));
      expect(repo.nearbyRangeCount, inInclusiveRange(1, 9));
    });

    test('raio maior inclui o que estava fora', () async {
      final found = await repo.nearby(_here.lat, _here.lng, 1000);
      expect(found.map((n) => n.place.id), ['a80', 'b250', 'c299', 'fora301']);
    });

    test('local sem coordenada nunca aparece', () async {
      final found = await repo.nearby(_here.lat, _here.lng, 3000);
      final ids = found.map((n) => n.place.id);
      expect(ids, isNot(contains('curado-sem-coordenada')));
      expect(ids, isNot(contains('longe')));
    });

    test('nada por perto (fora de Natal): lista vazia', () async {
      final found = await repo.nearby(-6.24, -35.211, 3000);
      expect(found, isEmpty);
    });

    test('o que a consulta leu vai para o cache por id', () async {
      await repo.nearby(_here.lat, _here.lng, 300);
      await db.doc('places/a80').delete();
      final cached = await repo.getPlaces(['a80']);
      expect(cached.keys, ['a80']);
      expect(cached['a80']!.geohash, isNotNull);
    });
  });

  test('placeFromData: geohash só com coordenadas válidas', () {
    final ok = FirestorePlaceRepository.placeFromData('x', {
      'name': 'X',
      'lat': -5.88,
      'lng': -35.17,
      'geohash': '7nyyx9m2s',
    });
    expect(ok!.geohash, '7nyyx9m2s');
    expect(ok.hasCoordinates, isTrue);
    final noCoords = FirestorePlaceRepository.placeFromData('y', {
      'name': 'Y',
      'geohash': '7nyyx9m2s',
    });
    expect(noCoords!.geohash, isNull);
    expect(noCoords.hasCoordinates, isFalse);
  });
}
