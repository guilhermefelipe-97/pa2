import 'dart:convert';

import 'package:http/http.dart' as http;

/// Feature GeoJSON no formato do Photon (`/api` e `/reverse`). Passar `null`
/// tira a propriedade.
Map<String, Object?> photonFeature({
  Object? osmType = 'N',
  Object? osmId = 1,
  Object? key = 'amenity',
  Object? value = 'restaurant',
  Object? name = 'Bar do Zé',
  double lat = -23.5503,
  double lng = -46.6339,
  Object? countrycode = 'BR',
  Object? district = 'Sé',
  Object? locality,
  Object? city = 'São Paulo',
  Object? street,
  Object? housenumber,
}) {
  final props = <String, Object?>{
    'osm_type': osmType,
    'osm_id': osmId,
    'osm_key': key,
    'osm_value': value,
    'name': name,
    'countrycode': countrycode,
    'country': 'Brasil',
    'district': district,
    'locality': locality,
    'city': city,
    'street': street,
    'housenumber': housenumber,
    'type': 'house',
  }..removeWhere((_, v) => v == null);
  return {
    'type': 'Feature',
    'geometry': {
      'type': 'Point',
      'coordinates': [lng, lat],
    },
    'properties': props,
  };
}

/// Resposta 200 do Photon com [features] (UTF-8, como o servidor manda).
http.Response photonResponse(List<Map<String, Object?>> features) =>
    http.Response.bytes(
      utf8.encode(
        jsonEncode({'type': 'FeatureCollection', 'features': features}),
      ),
      200,
      headers: {'content-type': 'application/json;charset=utf-8'},
    );
