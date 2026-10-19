import '../../domain/geo.dart';
import '../../domain/models/place.dart';
import '../../domain/osm_ids.dart';
import '../../domain/search_tokens.dart';
import '../lru_ttl_cache.dart';
import '../photon/photon_client.dart';
import '../repositories/place_repository.dart';

/// Catálogo do Brasil inteiro sob demanda (G2): descoberta ao vivo pelo
/// Photon/OSM + os locais gravados em `places` (Natal pelo seed e os criados
/// na 1ª interação).
///
/// - Busca e "Perto" consultam os dois e mesclam por local: o que já está
///   gravado vence (dados do Firestore, sinal de amigos); o resto entra como
///   [Place.discovered].
/// - Nada é gravado só por ter sido visto: [ensurePersisted] cria o doc
///   quando alguém avalia ou salva.
class CatalogPlaceRepository implements PlaceRepository {
  CatalogPlaceRepository({
    required PlaceRepository persisted,
    required PhotonClient photon,
    DateTime Function()? clock,
  }) : _persisted = persisted,
       _photon = photon,
       _discovered = LruTtlCache(clock: clock);

  final PlaceRepository _persisted;
  final PhotonClient _photon;

  /// Descobertos recentes (LRU 200, 30 min) que ainda não têm doc em
  /// `places`: o salvar/avaliar cria o doc a partir daqui.
  final LruTtlCache<String, Place> _discovered;

  @override
  Future<List<Place>> search(String query, {LatLng? near}) async {
    if (serverTerm(normalizeQuery(query)) == null) return const [];
    final results = await Future.wait([
      _attempt(() => _persisted.search(query, near: near)),
      // Menos de 3 caracteres: o PhotonClient devolve vazio sem ir à rede.
      _attempt(() => _photon.search(query, near: near)),
    ]);
    final stored = results[0];
    final found = results[1];
    // Uma fonte falhou e a outra não tem nada: erro ("Tentar de novo"), não
    // "nenhum resultado".
    if (found.error != null && (stored.error != null || stored.value.isEmpty)) {
      throw found.error!;
    }
    if (stored.error != null && found.value.isEmpty) throw stored.error!;
    // Descobertos que já estão gravados mas a busca por tokens não trouxe
    // (o Photon é tolerante a erro de digitação): os dados gravados vencem.
    // Uma consulta por lote de ids, com cache da sessão; falha não derruba.
    var storedPlaces = stored.value;
    final known = {for (final p in storedPlaces) p.id};
    final unknown = [
      for (final p in found.value)
        if (!known.contains(p.id)) p.id,
    ];
    if (stored.error == null && unknown.isNotEmpty) {
      try {
        final extra = await _persisted.getPlaces(unknown);
        storedPlaces = [...storedPlaces, ...extra.values];
      } on Object {
        // Segue só com o que já tem.
      }
    }
    final merged = _merge(storedPlaces, found.value);
    // Gravados que casam com a busca primeiro (até 10: o que amigos já
    // avaliaram/salvaram não some atrás do Photon), depois os descobertos,
    // depois o resto dos gravados; sem repetir, até 20.
    final seen = <String>{};
    return [
      for (final p in [
        ...stored.value.take(placeSearchStoredSlots),
        ...merged.discovery,
        ...stored.value.skip(placeSearchStoredSlots),
        ...merged.storedOnly,
      ])
        if (seen.add(p.id)) p,
    ].take(placeSearchLimit).toList();
  }

  @override
  Future<List<Place>> suggestions() => _persisted.suggestions();

  @override
  Future<Map<String, Place>> getPlaces(
    Iterable<String> ids, {
    bool refreshMissing = false,
  }) async {
    final wanted = ids.toSet();
    final found = await _persisted.getPlaces(
      wanted,
      refreshMissing: refreshMissing,
    );
    final out = {...found};
    for (final id in wanted) {
      if (out.containsKey(id)) continue;
      final d = _discovered[id];
      if (d != null) out[id] = d;
    }
    return out;
  }

  @override
  Future<NearbyResult> nearby(
    double lat,
    double lng,
    double radiusMeters,
  ) async {
    final position = (lat: lat, lng: lng);
    final storedFuture = _attemptAny(
      () => _persisted.nearby(lat, lng, radiusMeters),
    );
    // O Photon recebe o centro da célula da posição (com folga); o filtro
    // final é a distância real a partir da posição.
    final foundFuture = _attemptAny(
      () => _photon.reverse(position, radiusMeters),
    );
    final stored = await storedFuture;
    final found = await foundFuture;
    // Erro de tela inteira só se as duas fontes falharem.
    if (stored.error != null && found.error != null) throw found.error!;
    final storedList = stored.value?.places ?? const <NearbyPlace>[];
    final page = found.value;
    final discovered = <NearbyPlace>[
      if (page != null)
        for (final p in page.places)
          if (p.hasCoordinates)
            (
              place: p,
              distanceMeters: distanceMeters(position, (
                lat: p.lat!,
                lng: p.lng!,
              )),
            ),
    ].where((n) => n.distanceMeters <= radiusMeters).toList();
    final merged = _merge(
      [for (final n in storedList) n.place],
      [for (final n in discovered) n.place],
    );
    final keep = {
      for (final p in merged.discovery)
        if (p.discovered) p.id,
    };
    final out = <NearbyPlace>[
      ...storedList,
      for (final n in discovered)
        if (keep.remove(n.place.id)) n,
    ];
    return NearbyResult(
      out..sort(compareNearby),
      partial: found.error != null,
      capped: page?.capped ?? false,
    );
  }

  @override
  Future<void> ensurePersisted(Place place, {required String uid}) async {
    final target = _discovered[place.id] ?? place;
    if (!target.discovered) return;
    await _persisted.ensurePersisted(target, uid: uid);
    _discovered.remove(place.id);
  }

  @override
  Place? discoveredPlace(String placeId) => _discovered[placeId];

  @override
  void markPersisted(Place place) {
    _discovered.remove(place.id);
    _persisted.markPersisted(place);
  }

  @override
  void invalidate(String placeId) {
    _discovered.remove(placeId);
    _persisted.invalidate(placeId);
  }

  /// Mescla gravados e descobertos: um descoberto que é o mesmo local de um
  /// gravado (mesmo id; mesmo `osmId`, caso dos curados casados com o OSM;
  /// ou mesmo nome na mesma célula de ~150 m, caso do node/way que o seed
  /// unificou) dá lugar ao gravado, na posição do descoberto.
  ({List<Place> discovery, List<Place> storedOnly}) _merge(
    List<Place> stored,
    List<Place> found,
  ) {
    final byKey = <String, Place>{};
    for (final p in stored) {
      for (final k in _keys(p)) {
        byKey.putIfAbsent(k, () => p);
      }
    }
    final used = <String>{};
    final discovery = <Place>[];
    for (final p in found) {
      Place? match;
      for (final k in _keys(p)) {
        match = byKey[k];
        if (match != null) break;
      }
      if (match != null) {
        _discovered.remove(p.id);
        if (used.add(match.id)) discovery.add(match);
        continue;
      }
      if (!used.add(p.id)) continue;
      _discovered[p.id] = p;
      discovery.add(p);
    }
    return (
      discovery: discovery,
      storedOnly: [
        for (final p in stored)
          if (!used.contains(p.id)) p,
      ],
    );
  }

  static List<String> _keys(Place p) {
    final fromOsmId = placeIdOfOsmId(p.osmId);
    final gh =
        p.geohash ?? (p.hasCoordinates ? geohashEncode(p.lat!, p.lng!) : null);
    final name = nameLower(p.name);
    return [
      'id:${p.id}',
      if (fromOsmId != null) 'id:$fromOsmId',
      if (gh != null && gh.length >= 7 && name.isNotEmpty)
        'cell:$name|${gh.substring(0, 7)}',
    ];
  }

  static Future<({T? value, Object? error})> _attemptAny<T>(
    Future<T> Function() run,
  ) async {
    try {
      return (value: await run(), error: null);
    } on Object catch (e) {
      return (value: null, error: e);
    }
  }

  static Future<({List<Place> value, Object? error})> _attempt(
    Future<List<Place>> Function() run,
  ) async {
    try {
      return (value: await run(), error: null);
    } on Object catch (e) {
      return (value: const <Place>[], error: e);
    }
  }
}
