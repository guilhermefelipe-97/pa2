import 'dart:math' as math;

import 'package:naarea/domain/geo.dart';
import 'package:naarea/domain/models/place.dart';

/// Ponta Negra (Natal): onde a Bianca está nos testes do "Perto".
const pontaNegra = (lat: -5.8817, lng: -35.1708);

/// Ponto a [meters] de [from] na direção [bearingDeg] (0 = norte), na mesma
/// esfera do haversine do app.
LatLng destination(LatLng from, double meters, [double bearingDeg = 90]) {
  double rad(double d) => d * math.pi / 180;
  double deg(double r) => r * 180 / math.pi;
  final d = meters / earthRadiusMeters;
  final b = rad(bearingDeg);
  final lat1 = rad(from.lat), lng1 = rad(from.lng);
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

/// Local do catálogo a [meters] de [from] (com geohash, como no seed).
Place placeNear(
  String id,
  double meters, {
  LatLng from = pontaNegra,
  double bearingDeg = 90,
  String? name,
  String category = 'Restaurante',
}) {
  final p = destination(from, meters, bearingDeg);
  return Place(
    id: id,
    name: name ?? id,
    category: category,
    neighborhood: 'Ponta Negra',
    city: 'Natal',
    lat: p.lat,
    lng: p.lng,
    geohash: geohashEncode(p.lat, p.lng),
    source: PlaceSource.osm,
  );
}
