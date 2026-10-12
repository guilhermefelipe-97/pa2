import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/geo.dart';
import '../../domain/models/place.dart';
import '../../domain/osm_category.dart';
import '../../domain/osm_ids.dart';
import '../../domain/text_limits.dart';

/// Coleção do catálogo.
const placesCollection = 'places';

/// O app pode criar `places/{place.id}` (G2): local descoberto com id
/// `osm-[nwr][0-9]+`, nome de 1–120 caracteres, categoria do vocabulário e
/// coordenadas no Brasil — o mesmo que as Rules exigem.
bool canCreatePlace(Place place) {
  final name = place.name.trim();
  final lat = place.lat;
  final lng = place.lng;
  return isOsmPlaceId(place.id) &&
      name.isNotEmpty &&
      name.length <= 120 &&
      osmCategories.contains(place.category) &&
      lat != null &&
      lng != null &&
      inBrazilBounds((lat: lat, lng: lng));
}

/// Documento de criação de `places/{id}` com o schema EXATO das Rules
/// (`placeKeys()` em firebase/firestore.rules): geohash do seed,
/// `source: 'osm'`, quem criou e o timestamp do servidor. Sem campos de
/// busca (`nameLower`/`searchTokens`): o cliente não os grava; a busca de
/// locais criados vem do Photon.
Map<String, Object?> newPlaceData(Place place, {required String uid}) {
  if (!canCreatePlace(place)) {
    throw ArgumentError.value(place.id, 'place', 'local não pode ser criado');
  }
  final name = place.name.trim();
  // Corta sem partir caractere (emoji) no limite das Rules.
  String text(String? v) => truncateUtf16((v ?? '').trim(), 120);

  return {
    'name': name,
    'category': place.category,
    'neighborhood': text(place.neighborhood),
    'city': text(place.city),
    'address': text(place.address),
    'lat': place.lat,
    'lng': place.lng,
    // Recalculado das coordenadas (nunca confia no que veio).
    'geohash': geohashEncode(place.lat!, place.lng!),
    'osmId': osmIdOfPlaceId(place.id),
    'source': 'osm',
    'createdBy': uid,
    'createdAt': FieldValue.serverTimestamp(),
  };
}
