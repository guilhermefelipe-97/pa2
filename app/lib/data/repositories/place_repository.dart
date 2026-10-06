import '../../domain/models/place.dart';

/// Local do "Perto" com a distância real (haversine) até a consulta.
typedef NearbyPlace = ({Place place, double distanceMeters});

/// Mais perto primeiro; empate pelo nome e depois pelo id (ordem estável).
int compareNearby(NearbyPlace a, NearbyPlace b) {
  final byDistance = a.distanceMeters.compareTo(b.distanceMeters);
  if (byDistance != 0) return byDistance;
  final byName = a.place.name.compareTo(b.place.name);
  return byName != 0 ? byName : a.place.id.compareTo(b.place.id);
}

/// Máximo de resultados de [PlaceRepository.search].
const placeSearchLimit = 20;

/// Catálogo de locais (~600 docs). Nenhuma operação lê a coleção inteira.
abstract class PlaceRepository {
  /// Até [placeSearchLimit] locais cujo nome tem uma palavra começando por cada termo de
  /// [query] (sem acento/caixa), ordenados por nome. Busca curta (nenhum
  /// termo com 2+ letras) devolve lista vazia.
  Future<List<Place>> search(String query);

  /// Sugestões para a busca vazia/curta: locais curados com foto.
  Future<List<Place>> suggestions();

  /// Locais por id (ids ausentes no catálogo ficam de fora do mapa).
  /// [refreshMissing]: ids que a sessão já sabe ausentes são lidos de novo
  /// (ex.: "Tentar de novo"/puxar para atualizar na aba "Quero ir").
  Future<Map<String, Place>> getPlaces(
    Iterable<String> ids, {
    bool refreshMissing = false,
  });

  /// Locais com coordenadas a até [radiusMeters] de ([lat], [lng]), do mais
  /// perto ao mais longe (F10). Consulta por faixas de `geohash` (no máximo 9,
  /// com `limit` cada) e filtro final pela distância real. A posição só é
  /// usada em memória: ao servidor vão apenas os prefixos de geohash.
  Future<List<NearbyPlace>> nearby(double lat, double lng, double radiusMeters);
}
