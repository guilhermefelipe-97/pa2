/// Ids de locais do OpenStreetMap (G0/G2): `osm-n123`, `osm-w456`,
/// `osm-r789` — mesmo esquema de `placeId()` em `firebase/seed/osm/places.js`
/// e do padrão aceito pelas Rules ao criar `places/{id}`.
library;

const _prefixByType = {'node': 'n', 'way': 'w', 'relation': 'r'};
const _typeByPrefix = {'n': 'node', 'w': 'way', 'r': 'relation'};

/// Id numérico do OSM: positivo e sem zero à esquerda (mesmo padrão das
/// Rules: `osm-[nwr][1-9][0-9]*`).
final _placeIdPattern = RegExp(r'^osm-([nwr])([1-9][0-9]*)$');
final _osmNumber = RegExp(r'^[1-9][0-9]*$');

/// Id do local a partir do tipo do OSM (`node`/`way`/`relation`, ou a letra
/// `N`/`W`/`R` do Photon) e do id numérico; `null` se algum for inválido.
String? osmPlaceId(String? type, Object? id) {
  final t = (type ?? '').trim().toLowerCase();
  final prefix = _prefixByType[t] ?? (_typeByPrefix.containsKey(t) ? t : null);
  final n = switch (id) {
    final int v when v > 0 => '$v',
    final String v when _osmNumber.hasMatch(v) => v,
    _ => null,
  };
  if (prefix == null || n == null) return null;
  return 'osm-$prefix$n';
}

/// `osm-n123` está no padrão que as Rules aceitam criar.
bool isOsmPlaceId(String id) => _placeIdPattern.hasMatch(id);

/// `osm-n123` → `node/123` (formato de `Place.osmId`); `null` fora do padrão.
String? osmIdOfPlaceId(String id) {
  final m = _placeIdPattern.firstMatch(id);
  if (m == null) return null;
  return '${_typeByPrefix[m.group(1)]}/${m.group(2)}';
}

/// `node/123` → `osm-n123`; `null` fora do padrão.
String? placeIdOfOsmId(String? osmId) {
  final parts = (osmId ?? '').split('/');
  if (parts.length != 2) return null;
  return osmPlaceId(parts[0], parts[1]);
}
