import '../../domain/models/place.dart';

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
}
