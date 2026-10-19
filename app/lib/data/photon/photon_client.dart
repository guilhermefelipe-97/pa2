import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:http/http.dart' as http;

import '../../domain/geo.dart';
import '../../domain/models/place.dart';
import '../../domain/osm_category.dart';
import '../../domain/osm_ids.dart';
import '../../domain/search_tokens.dart';
import '../../domain/text_limits.dart';
import '../lru_ttl_cache.dart';

/// Falha ao consultar o Photon (rede, tempo esgotado, HTTP ≠ 200, JSON
/// inválido).
class PhotonException implements Exception {
  const PhotonException(this.message);

  final String message;

  @override
  String toString() => 'PhotonException: $message';
}

/// O Photon pediu para diminuir o ritmo (HTTP 429): nenhuma requisição sai
/// até [PhotonClient.rateLimitBackoff] depois da resposta.
class PhotonRateLimitedException extends PhotonException {
  const PhotonRateLimitedException() : super('HTTP 429');

  /// Mensagem para a pessoa.
  static const userMessage =
      'Muitas buscas seguidas — tente de novo em instantes';
}

/// Resposta do `/reverse`: locais e se o Photon devolveu o máximo pedido
/// ([PhotonClient.reverseLimit]): pode haver mais em volta.
typedef PhotonPage = ({List<Place> places, bool capped});

/// Descoberta ao vivo de locais de comer/beber no Brasil pelo Photon
/// (photon.komoot.io, dados do OpenStreetMap, sem chave; G2).
///
/// - `/reverse` com raio: o "Perto";
/// - `/api` com `q`: a busca do seletor, com viés pela posição (sem posição,
///   o centro do Brasil) e restrita ao retângulo do Brasil.
///
/// Os dois filtram por `osm_tag=amenity:<valor>` ([osmAmenities]) e só
/// devolvem features com nome, no Brasil (`countrycode == BR`).
///
/// Privacidade: a posição exata nunca sai do aparelho. O `/reverse` recebe o
/// CENTRO da célula de geohash 7 (~150 m) da posição, e a busca recebe o viés
/// arredondado a 3 casas decimais (~100 m). Nada é gravado.
///
/// Uso justo: cache LRU (200 entradas, 30 min) por (célula, raio) e por
/// (consulta, célula do viés); busca só com [minQueryLength]+ caracteres;
/// HTTP 429 suspende as requisições por [rateLimitBackoff].
class PhotonClient {
  PhotonClient({
    http.Client? client,
    String baseUrl = defaultBaseUrl,
    this.timeout = const Duration(seconds: 10),
    bool? sendIdentityHeaders,
    DateTime Function()? clock,
  }) : _client = client ?? http.Client(),
       _base = Uri.parse(
         baseUrl.endsWith('/')
             ? baseUrl.substring(0, baseUrl.length - 1)
             : baseUrl,
       ),
       // No navegador User-Agent e Referer são cabeçalhos proibidos (o
       // próprio navegador manda o Referer da página).
       _identity = sendIdentityHeaders ?? !kIsWeb,
       _clock = clock ?? DateTime.now {
    _cache = LruTtlCache(clock: _clock);
  }

  /// Instância pública. Outra via `--dart-define=PHOTON_URL=...`.
  static const defaultBaseUrl = 'https://photon.komoot.io';

  /// Identificação pedida pela política de uso do Photon público.
  static const userAgent =
      'NaArea/1.0 (app de avaliações entre amigos; '
      '+https://naarea-natal.firebaseapp.com)';
  static const referer = 'https://naarea-natal.firebaseapp.com/';

  /// Máximo de features por consulta ao `/reverse`.
  static const reverseLimit = 50;

  /// Máximo de features por busca.
  static const searchLimit = 20;

  /// Busca mais curta que isso não vai ao Photon.
  static const minQueryLength = 3;

  /// Célula de geohash do `/reverse` (~150 m): a consulta parte do centro
  /// dela com [cellSlackMeters] de folga (meia diagonal), então cobre o raio
  /// a partir de qualquer ponto da célula.
  static const reverseCellPrecision = 7;
  static const cellSlackMeters = 110.0;

  /// Célula do viés da busca na chave do cache.
  static const searchCachePrecision = 5;

  /// Pausa depois de um HTTP 429.
  static const rateLimitBackoff = Duration(seconds: 60);

  final http.Client _client;
  final Uri _base;
  final Duration timeout;
  final bool _identity;
  final DateTime Function() _clock;

  late final LruTtlCache<String, Future<PhotonPage>> _cache;

  DateTime? _blockedUntil;

  /// Requisições HTTP feitas (para testes do cache).
  @visibleForTesting
  int requestCount = 0;

  /// Locais em volta de [position] num raio que cobre [radiusMeters] a
  /// partir dela (o Photon recebe só o centro da célula, com folga). O filtro
  /// final pela distância real, a partir de [position], é de quem chama.
  Future<PhotonPage> reverse(LatLng position, double radiusMeters) {
    final cell = geohashEncode(
      position.lat,
      position.lng,
      precision: reverseCellPrecision,
    );
    final center = geohashCenter(cell);
    final key = 'reverse|$cell|${radiusMeters.round()}';
    return _cached(key, () {
      return _get('reverse', {
        'lat': _coord6(center.lat),
        'lon': _coord6(center.lng),
        // O Photon recebe o raio em km.
        'radius': ((radiusMeters + cellSlackMeters) / 1000).toStringAsFixed(3),
        'limit': '$reverseLimit',
      }, reverseLimit);
    });
  }

  /// Até [searchLimit] locais cujo nome casa com [query], com viés por
  /// [near] (sem posição: [brazilCenter]). Menos de [minQueryLength]
  /// caracteres: lista vazia sem ir à rede.
  Future<List<Place>> search(String query, {LatLng? near}) async {
    final q = query.trim();
    if (q.runes.length < minQueryLength) return const [];
    final raw = near != null && inBrazilBounds(near) ? near : brazilCenter;
    // ~100 m: o bastante para o viés, sem mandar a posição exata.
    final bias = (lat: _round3(raw.lat), lng: _round3(raw.lng));
    final cell = geohashEncode(
      bias.lat,
      bias.lng,
      precision: searchCachePrecision,
    );
    final key = 'search|${normalizeQuery(q).join(' ')}|$cell';
    final page = await _cached(key, () {
      return _get('api', {
        'q': q,
        'lat': bias.lat.toStringAsFixed(3),
        'lon': bias.lng.toStringAsFixed(3),
        'limit': '$searchLimit',
        'bbox': [
          brazilBounds.west,
          brazilBounds.south,
          brazilBounds.east,
          brazilBounds.north,
        ].join(','),
      }, searchLimit);
    });
    return page.places;
  }

  /// Só respostas boas ficam no cache (falha tenta de novo na próxima).
  Future<PhotonPage> _cached(String key, Future<PhotonPage> Function() run) {
    final hit = _cache[key];
    if (hit != null) return hit;
    final future = run();
    _cache[key] = future;
    future.then<void>(
      (_) {},
      onError: (Object _) {
        _cache.removeIfSame(key, future);
      },
    );
    return future;
  }

  static String _coord6(double v) => v.toStringAsFixed(6);

  static double _round3(double v) => (v * 1000).roundToDouble() / 1000;

  Future<PhotonPage> _get(
    String path,
    Map<String, String> params,
    int limit,
  ) async {
    final blocked = _blockedUntil;
    if (blocked != null) {
      if (_clock().isBefore(blocked)) {
        throw const PhotonRateLimitedException();
      }
      _blockedUntil = null;
    }
    final uri = _base.replace(
      path: '${_base.path}/$path',
      queryParameters: {
        ...params,
        'lang': 'default',
        'osm_tag': [for (final a in osmAmenities) 'amenity:$a'],
      },
    );
    requestCount++;
    final http.Response res;
    try {
      res = await _client
          .get(
            uri,
            headers: _identity
                ? const {'User-Agent': userAgent, 'Referer': referer}
                : null,
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const PhotonException('tempo esgotado');
    } on Object catch (e) {
      throw PhotonException('rede: $e');
    }
    if (res.statusCode == 429) {
      _blockedUntil = _clock().add(rateLimitBackoff);
      throw const PhotonRateLimitedException();
    }
    if (res.statusCode != 200) {
      throw PhotonException('HTTP ${res.statusCode}');
    }
    final Object? body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      throw const PhotonException('resposta inválida');
    }
    final features = body is Map ? body['features'] : null;
    if (features is! List) throw const PhotonException('resposta inválida');
    final seen = <String>{};
    final out = <Place>[];
    for (final f in features) {
      final place = placeFromFeature(f);
      if (place != null && seen.add(place.id)) out.add(place);
    }
    return (
      places: List<Place>.unmodifiable(out),
      capped: features.length >= limit,
    );
  }

  /// Máximo (unidades UTF-16, como o `size()` das Rules) dos textos do local.
  static const maxNameLength = 120;

  /// Feature GeoJSON do Photon → [Place] descoberto; `null` quando não é
  /// local de comer/beber, não tem nome, está fora do Brasil ou vem
  /// malformada.
  static Place? placeFromFeature(Object? feature) {
    if (feature is! Map) return null;
    final props = feature['properties'];
    final geometry = feature['geometry'];
    if (props is! Map || geometry is! Map) return null;

    String text(String key) {
      final v = props[key];
      return v is String ? v.trim() : '';
    }

    if (text('countrycode').toUpperCase() != 'BR') return null;
    if (text('osm_key') != 'amenity') return null;
    final amenity = text('osm_value');
    if (!osmAmenities.contains(amenity)) return null;
    final name = text('name');
    // Nome maior que o limite das Rules: descartado (cortar mudaria o nome).
    if (name.isEmpty || name.length > maxNameLength) return null;
    final id = osmPlaceId(text('osm_type'), props['osm_id']);
    if (id == null) return null;

    final coords = geometry['coordinates'];
    if (coords is! List || coords.length < 2) return null;
    final lngRaw = coords[0];
    final latRaw = coords[1];
    if (lngRaw is! num || latRaw is! num) return null;
    final lat = _round7(latRaw.toDouble());
    final lng = _round7(lngRaw.toDouble());
    if (!lat.isFinite ||
        !lng.isFinite ||
        !inBrazilBounds((lat: lat, lng: lng))) {
      return null;
    }

    final street = text('street');
    final number = text('housenumber');
    final address = street.isEmpty
        ? ''
        : number.isEmpty
        ? street
        : '$street, $number';
    final district = text('district');

    return Place(
      id: id,
      name: name,
      // O Photon não traz `cuisine`: a categoria sai só do `amenity`.
      category: osmCategoryFor(amenity),
      neighborhood: _limit(district.isNotEmpty ? district : text('locality')),
      city: _limit(text('city')),
      address: address.isEmpty ? null : _limit(address),
      lat: lat,
      lng: lng,
      geohash: geohashEncode(lat, lng),
      osmId: osmIdOfPlaceId(id),
      source: PlaceSource.osm,
      discovered: true,
    );
  }

  /// Textos opcionais também têm teto nas Rules; corta sem partir caractere.
  static String _limit(String s) => truncateUtf16(s, maxNameLength);

  /// 7 casas (~1 cm), como o seed.
  static double _round7(double v) => (v * 1e7).roundToDouble() / 1e7;

  void close() => _client.close();
}
