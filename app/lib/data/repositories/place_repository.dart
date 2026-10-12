import '../../domain/geo.dart';
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

/// Quantos gravados que casam com a busca vêm antes dos descobertos (G2): o
/// que amigos já avaliaram/salvaram não some atrás de 20 resultados do Photon.
const placeSearchStoredSlots = 10;

/// Resultado do "Perto".
class NearbyResult {
  const NearbyResult(this.places, {this.partial = false, this.capped = false});

  /// Do mais perto ao mais longe, todos dentro do raio.
  final List<NearbyPlace> places;

  /// A descoberta ao vivo (Photon) falhou: só os locais já gravados.
  final bool partial;

  /// A descoberta devolveu o máximo de resultados: pode haver mais em volta.
  final bool capped;
}

/// Catálogo de locais. Nenhuma operação lê a coleção inteira.
///
/// Desde o G2 o catálogo é o Brasil inteiro: locais gravados em `places`
/// (Natal pelo seed, os demais criados na 1ª interação) mais os descobertos
/// ao vivo pelo Photon/OSM ([Place.discovered]), que só viram documento
/// quando alguém avalia ou salva ([ensurePersisted]).
abstract class PlaceRepository {
  /// Até [placeSearchLimit] locais cujo nome casa com [query] (sem
  /// acento/caixa). [near] dá o viés da descoberta (o mais perto primeiro);
  /// ao Photon vai arredondado a 3 casas decimais (~100 m).
  /// Busca curta (nenhum termo com 2+ letras) devolve lista vazia.
  Future<List<Place>> search(String query, {LatLng? near});

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
  /// perto ao mais longe (F10). Gravados: faixas de `geohash` (no máximo 9,
  /// com `limit` cada); descobertos (G2): `/reverse` do Photon. Filtro final
  /// pela distância real. A posição nunca é gravada: o Firestore recebe só
  /// prefixos de geohash e o Photon, só o centro da célula de geohash 7
  /// (~150 m) — nunca a posição exata.
  Future<NearbyResult> nearby(double lat, double lng, double radiusMeters);

  /// Garante que `places/{place.id}` existe antes de avaliar/salvar um local
  /// descoberto (G2): cria o doc se ainda não existe; se outra pessoa criou
  /// antes (corrida), segue com o existente. Local já gravado: nada a fazer.
  /// Idempotente; falha (rede, Rules) sobe.
  Future<void> ensurePersisted(Place place, {required String uid});

  /// Local só descoberto nesta sessão (ainda sem doc em `places`), ou `null`.
  Place? discoveredPlace(String placeId);

  /// O app criou `places/{place.id}` por outro caminho (ex.: no mesmo batch
  /// da avaliação).
  void markPersisted(Place place);

  /// Esquece o que a sessão sabe de [placeId]: a próxima [getPlaces] relê.
  /// Ex.: a avaliação foi gravada num local que OUTRA pessoa criou.
  void invalidate(String placeId);
}

/// Antes de salvar no "Quero ir" (G2): as Rules exigem `places/{placeId}`.
/// Descoberto nesta sessão: cria o doc. Senão, confirma que ele existe
/// (lendo se preciso); se não existir, falha — e o salvo não é gravado.
Future<void> ensurePlaceForSave(
  PlaceRepository places, {
  required String uid,
  required String placeId,
}) async {
  final discovered = places.discoveredPlace(placeId);
  if (discovered != null) {
    await places.ensurePersisted(discovered, uid: uid);
    return;
  }
  final found = (await places.getPlaces([placeId]))[placeId];
  if (found == null) {
    throw StateError('local $placeId não está no catálogo');
  }
  if (found.discovered) await places.ensurePersisted(found, uid: uid);
}
