import 'dart:async';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/place_repository.dart';
import '../../data/repositories/review_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/services/location_service.dart';
import '../../domain/geo.dart';
import '../../domain/models/place.dart';
import '../core/follow_events.dart';
import '../core/safe_change_notifier.dart';
import '../feed/widgets/trust_sources.dart' show displayAuthorName;
import '../saved/saved_places_store.dart';

/// Raios do "Perto": 300 m · 1 km · 3 km.
enum NearbyRadius {
  m300(300, '300 m'),
  km1(1000, '1 km'),
  km3(3000, '3 km');

  const NearbyRadius(this.meters, this.label);

  final double meters;
  final String label;

  /// Próximo raio maior ("Ampliar para 1 km"), ou `null` no maior.
  NearbyRadius? get wider {
    final i = index + 1;
    return i < values.length ? values[i] : null;
  }
}

/// Em que ponto a aba está.
enum NearbyPhase {
  /// Vendo se a permissão já existe (sem pedido do sistema).
  checking,

  /// Permissão ainda não concedida: tela explicativa antes do pedido.
  explain,

  /// Obtendo a posição.
  locating,

  denied,
  deniedForever,
  serviceOff,

  /// Não conseguiu a posição (tempo esgotado, sem sinal...).
  locationError,

  /// Consultando os locais.
  loading,

  /// Lista pronta (pode estar vazia).
  ready,

  /// Falha de rede ao consultar os locais.
  loadError,
}

/// Item da lista: local, distância e quem o usuário segue que foi lá.
class NearbyItem {
  const NearbyItem({
    required this.place,
    required this.distanceMeters,
    this.friends = const [],
  });

  final Place place;
  final double distanceMeters;

  /// Nomes de quem o usuário segue que avaliou o local (mais recente
  /// primeiro, sem repetição).
  final List<String> friends;

  /// "Ana foi aqui", "Ana e Bia foram aqui", "Ana e mais 2 foram aqui".
  String? get friendsLabel => friendsWentLabel(friends);
}

/// "Ana foi aqui", "Ana e Bia foram aqui", "Ana e mais 2 foram aqui".
String? friendsWentLabel(List<String> names) => switch (names.length) {
  0 => null,
  1 => '${names[0]} foi aqui',
  2 => '${names[0]} e ${names[1]} foram aqui',
  _ => '${names[0]} e mais ${names.length - 1} foram aqui',
};

/// Por que a sugestão foi escolhida.
enum SuggestionReason {
  /// O mais perto que alguém que o usuário segue avaliou.
  friend,

  /// O mais perto salvo no "Quero ir".
  saved,

  /// O mais perto de todos.
  nearest,
}

typedef NearbySuggestion = ({NearbyItem item, SuggestionReason reason});

/// Sugestão do topo: o mais perto que um amigo avaliou; sem nenhum, o mais
/// perto salvo no "Quero ir"; sem nenhum, o mais perto. [items] já vem
/// ordenada por distância.
NearbySuggestion? pickSuggestion(
  List<NearbyItem> items,
  bool Function(String placeId) isSaved,
) {
  if (items.isEmpty) return null;
  for (final i in items) {
    if (i.friends.isNotEmpty) return (item: i, reason: SuggestionReason.friend);
  }
  for (final i in items) {
    if (isSaved(i.place.id)) return (item: i, reason: SuggestionReason.saved);
  }
  return (item: items.first, reason: SuggestionReason.nearest);
}

/// Aba "Perto" (F10): o que está a 300 m / 1 km / 3 km de onde a pessoa
/// está agora, com uma sugestão em 1 toque.
///
/// A posição fica só em memória ([position]); ao servidor vão apenas os
/// prefixos de geohash da consulta.
class NearbyViewModel extends SafeChangeNotifier {
  NearbyViewModel({
    required LocationService locationService,
    required PlaceRepository placeRepository,
    required AuthRepository authRepository,
    required UserRepository userRepository,
    required ReviewRepository reviewRepository,
    FollowEvents? followEvents,
    SavedPlacesStore? savedStore,
  }) : _location = locationService,
       _places = placeRepository,
       _auth = authRepository,
       _users = userRepository,
       _reviews = reviewRepository,
       _follow = followEvents == null ? null : FollowStaleness(followEvents),
       _saved = savedStore {
    _saved?.addListener(notifyListeners);
  }

  final LocationService _location;
  final PlaceRepository _places;
  final AuthRepository _auth;
  final UserRepository _users;
  final ReviewRepository _reviews;
  final FollowStaleness? _follow;
  final SavedPlacesStore? _saved;

  /// Lado da célula de geohash de precisão 7 é ~153 m: a consulta em cache
  /// parte do centro da célula com esta folga (meia diagonal, arredondada
  /// para cima), então cobre o raio a partir de qualquer ponto da célula.
  static const cacheCellPrecision = 7;
  static const cacheCellSlackMeters = 110.0;

  NearbyPhase _phase = NearbyPhase.checking;
  NearbyPhase get phase => _phase;

  NearbyRadius _radius = NearbyRadius.m300;
  NearbyRadius get radius => _radius;

  LatLng? _position;

  /// Posição atual (só em memória).
  LatLng? get position => _position;

  List<NearbyItem> _items = const [];
  List<NearbyItem> get items => _items;

  /// A posição está fora da área que o catálogo cobre.
  bool get outOfArea {
    final p = _position;
    return p != null && !inServiceArea(p);
  }

  NearbySuggestion? get suggestion =>
      pickSuggestion(_items, _saved?.isSaved ?? (_) => false);

  bool isSaved(String placeId) => _saved?.isSaved(placeId) ?? false;

  /// Resultados por (geohash 7 da posição, raio), durante a sessão.
  final Map<String, List<NearbyPlace>> _cache = {};

  /// placeId → nomes de quem o usuário segue que foi lá. `null`: ainda não
  /// carregado (ou falhou: tenta de novo na próxima carga).
  Map<String, List<String>>? _friends;
  String? _friendsUid;

  /// Muda a cada carga: respostas antigas são descartadas.
  int _generation = 0;

  bool _started = false;

  /// Primeira abertura da aba: sem permissão, mostra a explicação; com
  /// permissão, já busca a posição.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    final gen = ++_generation;
    _phase = NearbyPhase.checking;
    notifyListeners();
    final granted = await _location.hasPermission();
    if (gen != _generation) return;
    if (granted) {
      await _locateAndLoad();
    } else {
      _phase = NearbyPhase.explain;
      notifyListeners();
    }
  }

  /// "Usar minha localização" / "Tentar de novo": pede a permissão (se
  /// preciso), pega a posição e consulta.
  Future<void> useMyLocation() => _locateAndLoad();

  /// Puxar para atualizar: nova posição e sinal de amigos relido.
  Future<void> refresh() {
    _friends = null;
    return _locateAndLoad();
  }

  /// "Tentar de novo" de uma falha de rede: mesma posição.
  Future<void> retry() {
    final p = _position;
    return p == null ? _locateAndLoad() : _load(p, ++_generation);
  }

  /// Troca o raio e refaz a consulta (a sugestão é recalculada).
  Future<void> selectRadius(NearbyRadius radius) {
    if (radius == _radius && _phase == NearbyPhase.ready) {
      return Future.value();
    }
    _radius = radius;
    final p = _position;
    if (p == null) {
      notifyListeners();
      return Future.value();
    }
    return _load(p, ++_generation);
  }

  /// Ao voltar para a aba: seguir/deixar de seguir em outra tela muda o
  /// "foi aqui" e a sugestão.
  Future<void> reloadIfStale() {
    final follow = _follow;
    if (follow == null || !follow.isStale) return Future.value();
    final p = _position;
    if (p == null || _phase != NearbyPhase.ready) return Future.value();
    _friends = null;
    return _load(p, ++_generation);
  }

  Future<bool> openAppSettings() => _location.openAppSettings();

  Future<bool> openLocationSettings() => _location.openLocationSettings();

  Future<void> _locateAndLoad() async {
    final gen = ++_generation;
    _phase = NearbyPhase.locating;
    notifyListeners();
    final LocationResult result;
    try {
      result = await _location.locate();
    } on Object {
      if (gen != _generation) return;
      _phase = NearbyPhase.locationError;
      notifyListeners();
      return;
    }
    if (gen != _generation) return;
    final position = result.position;
    if (result.status != LocationStatus.ok || position == null) {
      _phase = switch (result.status) {
        LocationStatus.denied => NearbyPhase.denied,
        LocationStatus.deniedForever => NearbyPhase.deniedForever,
        LocationStatus.serviceOff => NearbyPhase.serviceOff,
        _ => NearbyPhase.locationError,
      };
      notifyListeners();
      return;
    }
    _position = position;
    await _load(position, gen);
  }

  Future<void> _load(LatLng position, int gen) async {
    final radius = _radius;
    _phase = NearbyPhase.loading;
    notifyListeners();
    _follow?.clear();
    try {
      final results = await Future.wait([
        _nearby(position, radius),
        _loadFriends(),
      ]);
      if (gen != _generation) return;
      final found = results[0] as List<NearbyPlace>;
      final friends = results[1] as Map<String, List<String>>;
      _items = [
        for (final n in found)
          NearbyItem(
            place: n.place,
            distanceMeters: n.distanceMeters,
            friends: friends[n.place.id] ?? const [],
          ),
      ];
      _phase = NearbyPhase.ready;
    } on Object {
      if (gen != _generation) return;
      _items = const [];
      _phase = NearbyPhase.loadError;
    }
    notifyListeners();
  }

  /// Locais a até [radius] de [position], do cache quando a posição cai na
  /// mesma célula de geohash 7 já consultada com esse raio.
  Future<List<NearbyPlace>> _nearby(
    LatLng position,
    NearbyRadius radius,
  ) async {
    final cell = geohashEncode(
      position.lat,
      position.lng,
      precision: cacheCellPrecision,
    );
    final key = '$cell|${radius.meters}';
    var candidates = _cache[key];
    if (candidates == null) {
      final center = geohashCenter(cell);
      candidates = await _places.nearby(
        center.lat,
        center.lng,
        radius.meters + cacheCellSlackMeters,
      );
      _cache[key] = candidates;
    }
    // Filtro final pela distância real a partir da posição exata.
    final out = <NearbyPlace>[];
    for (final c in candidates) {
      final p = c.place;
      if (!p.hasCoordinates) continue;
      final d = distanceMeters(position, (lat: p.lat!, lng: p.lng!));
      if (d <= radius.meters) out.add((place: p, distanceMeters: d));
    }
    return out..sort(compareNearby);
  }

  /// Sinal "foi aqui": avaliações de quem o usuário segue (mesma fonte do
  /// feed). Falha não derruba a lista: fica sem o sinal e tenta de novo na
  /// próxima carga.
  Future<Map<String, List<String>>> _loadFriends() async {
    final uid = _auth.currentUserId;
    if (uid == null) return const {};
    final cached = _friends;
    if (cached != null && _friendsUid == uid) return cached;
    try {
      final following = {...await _users.getFollowing(uid)}..remove(uid);
      final byPlace = <String, List<String>>{};
      if (following.isNotEmpty) {
        final reviews = await _reviews.fetchReviewsByAuthors(
          following.toList(),
        );
        final seen = <String, Set<String>>{};
        // Mais recentes primeiro (contrato do repositório).
        for (final r in reviews) {
          if (!following.contains(r.authorId)) continue;
          if (!(seen[r.placeId] ??= {}).add(r.authorId)) continue;
          (byPlace[r.placeId] ??= []).add(displayAuthorName(r.authorName));
        }
      }
      _friends = byPlace;
      _friendsUid = uid;
      return byPlace;
    } on Object {
      return const {};
    }
  }

  @override
  void dispose() {
    _saved?.removeListener(notifyListeners);
    _follow?.dispose();
    super.dispose();
  }
}
