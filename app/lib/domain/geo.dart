/// Geometria do "Perto" (F10): geohash, faixas de consulta, distância real e
/// formatação. Puro (sem Flutter/Firebase).
///
/// O geohash segue o mesmo alfabeto e as mesmas regras de
/// `firebase/seed/osm/geo.js` (o seed grava `geohash` com precisão 9), e
/// [geohashQueryBounds] é o algoritmo do `geofire-common` (Firebase), travado
/// por vetores gerados com a própria biblioteca nos testes.
library;

import 'dart:math' as math;

const _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
const _bitsPerChar = 5;
const _maxBitsPrecision = 22 * _bitsPerChar;
const _earthMeriCircumference = 40007860.0;
const _metersPerDegreeLatitude = 110574.0;
const _earthEqRadius = 6378137.0;
const _e2 = 0.00669447819799;
const _epsilon = 1e-12;

/// Raio médio da Terra (mesmo do `geofire-common`).
const earthRadiusMeters = 6371000.0;

/// Ponto (lat, lng) em graus.
typedef LatLng = ({double lat, double lng});

/// Faixa `[start, end]` de geohash para `orderBy('geohash').startAt/endAt`.
typedef GeohashRange = ({String start, String end});

/// Geohash padrão (base32 de Niemeyer), igual ao do seed.
String geohashEncode(double lat, double lng, {int precision = 9}) {
  var latLo = -90.0, latHi = 90.0, lngLo = -180.0, lngHi = 180.0;
  final out = StringBuffer();
  var bit = 0;
  var ch = 0;
  var even = true; // bits pares = longitude
  var length = 0;
  while (length < precision) {
    if (even) {
      final mid = (lngLo + lngHi) / 2;
      if (lng >= mid) {
        ch = (ch << 1) | 1;
        lngLo = mid;
      } else {
        ch <<= 1;
        lngHi = mid;
      }
    } else {
      final mid = (latLo + latHi) / 2;
      if (lat >= mid) {
        ch = (ch << 1) | 1;
        latLo = mid;
      } else {
        ch <<= 1;
        latHi = mid;
      }
    }
    even = !even;
    if (++bit == _bitsPerChar) {
      out.write(_base32[ch]);
      length++;
      bit = 0;
      ch = 0;
    }
  }
  return out.toString();
}

/// Centro da célula de [geohash].
LatLng geohashCenter(String geohash) {
  var latLo = -90.0, latHi = 90.0, lngLo = -180.0, lngHi = 180.0;
  var even = true;
  for (final c in geohash.split('')) {
    final v = _base32.indexOf(c);
    if (v < 0) throw ArgumentError.value(geohash, 'geohash');
    for (var b = _bitsPerChar - 1; b >= 0; b--) {
      final on = (v >> b) & 1 == 1;
      if (even) {
        final mid = (lngLo + lngHi) / 2;
        on ? lngLo = mid : lngHi = mid;
      } else {
        final mid = (latLo + latHi) / 2;
        on ? latLo = mid : latHi = mid;
      }
      even = !even;
    }
  }
  return (lat: (latLo + latHi) / 2, lng: (lngLo + lngHi) / 2);
}

double _radians(double deg) => deg * math.pi / 180;

double _log2(double x) => math.log(x) / math.ln2;

double _metersToLongitudeDegrees(double distance, double latitude) {
  final rad = _radians(latitude);
  final num = math.cos(rad) * _earthEqRadius * math.pi / 180;
  final denom = 1 / math.sqrt(1 - _e2 * math.sin(rad) * math.sin(rad));
  final deltaDeg = num * denom;
  if (deltaDeg < _epsilon) return distance > 0 ? 360 : 0;
  return math.min(360, distance / deltaDeg);
}

double _longitudeBitsForResolution(double resolution, double latitude) {
  final degs = _metersToLongitudeDegrees(resolution, latitude);
  return degs.abs() > 0.000001 ? math.max(1, _log2(360 / degs)) : 1;
}

double _latitudeBitsForResolution(double resolution) => math.min(
  _log2(_earthMeriCircumference / 2 / resolution),
  _maxBitsPrecision.toDouble(),
);

double _wrapLongitude(double longitude) {
  if (longitude <= 180 && longitude >= -180) return longitude;
  final adjusted = longitude + 180;
  if (adjusted > 0) return (adjusted % 360) - 180;
  return 180 - (-adjusted % 360);
}

int _boundingBoxBits(LatLng c, double size) {
  final latDelta = size / _metersPerDegreeLatitude;
  final north = math.min(90.0, c.lat + latDelta);
  final south = math.max(-90.0, c.lat - latDelta);
  final bitsLat = _latitudeBitsForResolution(size).floor() * 2;
  final bitsLngNorth = _longitudeBitsForResolution(size, north).floor() * 2 - 1;
  final bitsLngSouth = _longitudeBitsForResolution(size, south).floor() * 2 - 1;
  return [
    bitsLat,
    bitsLngNorth,
    bitsLngSouth,
    _maxBitsPrecision,
  ].reduce(math.min);
}

List<LatLng> _boundingBoxCoordinates(LatLng c, double radius) {
  final latDegrees = radius / _metersPerDegreeLatitude;
  final north = math.min(90.0, c.lat + latDegrees);
  final south = math.max(-90.0, c.lat - latDegrees);
  final lngDegs = math.max(
    _metersToLongitudeDegrees(radius, north),
    _metersToLongitudeDegrees(radius, south),
  );
  final west = _wrapLongitude(c.lng - lngDegs);
  final east = _wrapLongitude(c.lng + lngDegs);
  return [
    (lat: c.lat, lng: c.lng),
    (lat: c.lat, lng: west),
    (lat: c.lat, lng: east),
    (lat: north, lng: c.lng),
    (lat: north, lng: west),
    (lat: south, lng: c.lng),
    (lat: north, lng: east),
    (lat: south, lng: west),
    (lat: south, lng: east),
  ];
}

GeohashRange _geohashQuery(String geohash, int bits) {
  final precision = (bits / _bitsPerChar).ceil();
  if (geohash.length < precision) return (start: geohash, end: '$geohash~');
  final ghash = geohash.substring(0, precision);
  final base = ghash.substring(0, ghash.length - 1);
  final lastValue = _base32.indexOf(ghash[ghash.length - 1]);
  final significantBits = bits - base.length * _bitsPerChar;
  final unusedBits = _bitsPerChar - significantBits;
  final startValue = (lastValue >> unusedBits) << unusedBits;
  final endValue = startValue + (1 << unusedBits);
  return endValue > 31
      ? (start: '$base${_base32[startValue]}', end: '$base~')
      : (
          start: '$base${_base32[startValue]}',
          end: '$base${_base32[endValue]}',
        );
}

/// Faixas de geohash que cobrem o círculo de [radiusMeters] em volta de
/// [center] (no máximo 9, sem repetidas). Algoritmo do `geofire-common`:
/// a união das faixas contém todo ponto do círculo, mas também pontos fora
/// dele — o filtro final é sempre por [distanceMeters].
List<GeohashRange> geohashQueryBounds(LatLng center, double radiusMeters) {
  final queryBits = math.max(1, _boundingBoxBits(center, radiusMeters));
  final precision = (queryBits / _bitsPerChar).ceil();
  final out = <GeohashRange>[];
  for (final c in _boundingBoxCoordinates(center, radiusMeters)) {
    final q = _geohashQuery(
      geohashEncode(c.lat, c.lng, precision: precision),
      queryBits,
    );
    if (!out.any((o) => o.start == q.start && o.end == q.end)) out.add(q);
  }
  return out;
}

/// Distância real (haversine) em metros.
double distanceMeters(LatLng a, LatLng b) {
  final dLat = _radians(b.lat - a.lat);
  final dLng = _radians(b.lng - a.lng);
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(_radians(a.lat)) *
          math.cos(_radians(b.lat)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * earthRadiusMeters * math.asin(math.min(1, math.sqrt(h)));
}

/// Abaixo de 1 km: metros arredondados de 10 em 10 (mínimo 10). Senão, km com
/// uma casa e vírgula ("1,2 km"; "2 km" sem ",0"); de 10 km em diante, inteiro.
({int meters, String km}) _rounded(double meters) {
  final m = meters.isFinite && meters > 0 ? meters : 0.0;
  final tens = math.max(10, (m / 10).round() * 10);
  if (tens < 1000) return (meters: tens, km: '');
  if (m >= 9950) return (meters: 0, km: '${(m / 1000).round()}');
  final km = (m / 1000).toStringAsFixed(1).replaceAll('.', ',');
  return (
    meters: 0,
    km: km.endsWith(',0') ? km.substring(0, km.length - 2) : km,
  );
}

/// "80 m", "950 m", "1,2 km".
String formatDistance(double meters) {
  final r = _rounded(meters);
  return r.km.isEmpty ? '${r.meters} m' : '${r.km} km';
}

/// Para leitor de tela: "a 120 metros", "a 1 quilômetro", "a 1,2 quilômetros".
String spokenDistance(double meters) {
  final r = _rounded(meters);
  if (r.km.isEmpty) return 'a ${r.meters} metros';
  return r.km == '1' ? 'a 1 quilômetro' : 'a ${r.km} quilômetros';
}

/// Centro de Natal/RN: referência para "Ainda não temos lugares por aqui".
const LatLng natalCenter = (lat: -5.7945, lng: -35.2110);

/// Raio em volta de [natalCenter] que o catálogo cobre (o município tem
/// ~20 km de norte a sul; folga para a Grande Natal).
const double serviceAreaRadiusMeters = 25000;

/// [position] está na área que o catálogo cobre.
bool inServiceArea(LatLng position) =>
    distanceMeters(position, natalCenter) <= serviceAreaRadiusMeters;
