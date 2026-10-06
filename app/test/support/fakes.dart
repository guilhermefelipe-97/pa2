// Fakes escritos à mão (sem mocks gerados) para testar os ViewModels.
import 'dart:async';
import 'dart:typed_data';

import 'package:naarea/data/repositories/auth_repository.dart';
import 'package:naarea/data/repositories/lists_repository.dart';
import 'package:naarea/data/repositories/place_repository.dart';
import 'package:naarea/data/repositories/review_photo_repository.dart';
import 'package:naarea/data/repositories/review_repository.dart';
import 'package:naarea/data/repositories/saved_repository.dart';
import 'package:naarea/data/repositories/user_repository.dart';
import 'package:naarea/data/services/location_service.dart';
import 'package:naarea/data/services/photo_picker.dart';
import 'package:naarea/domain/geo.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/domain/models/place_list.dart';
import 'package:naarea/domain/models/review.dart';
import 'package:naarea/domain/models/user_profile.dart';
import 'package:naarea/domain/search_tokens.dart';

class FakeAuthRepository extends AuthRepository {
  FakeAuthRepository({String? uid, this.users, bool initialized = true})
    : _uid = uid,
      _initialized = initialized;

  final FakeUserRepository? users;
  String? _uid;
  bool _initialized;
  AuthException? nextError;
  final List<Map<String, String>> signUpCalls = [];
  final List<Map<String, String>> signInCalls = [];
  int _seq = 0;

  @override
  bool get isInitialized => _initialized;

  @override
  String? get currentUserId => _uid;

  void restoreSession(String? uid) {
    _uid = uid;
    _initialized = true;
    notifyListeners();
  }

  @override
  Future<void> signUp({
    required String displayName,
    required String email,
    required String password,
  }) async {
    signUpCalls.add({
      'displayName': displayName,
      'email': email,
      'password': password,
    });
    if (nextError != null) throw nextError!;
    final uid = 'new-${++_seq}';
    await users?.createProfile(uid: uid, displayName: displayName);
    _uid = uid;
    notifyListeners();
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    signInCalls.add({'email': email, 'password': password});
    if (nextError != null) throw nextError!;
    _uid = 'signed-in';
    notifyListeners();
  }

  @override
  Future<void> signOut() async {
    _uid = null;
    notifyListeners();
  }
}

class FakeUserRepository implements UserRepository {
  final Map<String, UserProfile> profiles = {};
  final Map<String, Set<String>> followingByUser = {};
  bool failGetFollowing = false;
  bool failFollow = false;
  bool failSearch = false;
  int getFollowingCalls = 0;

  /// Permite controlar quando/como cada chamada responde (ex.: Completer).
  Future<List<UserProfile>> Function(String query)? searchOverride;
  Future<Set<String>> Function(String uid)? getFollowingOverride;
  Completer<void>? followGate;

  void addUser(String uid, String name) {
    profiles[uid] = UserProfile(uid: uid, displayName: name);
  }

  @override
  Future<void> createProfile({
    required String uid,
    required String displayName,
  }) async {
    addUser(uid, UserProfile.normalizeName(displayName));
  }

  @override
  Future<UserProfile?> getProfile(String uid) async => profiles[uid];

  @override
  Future<List<UserProfile>> searchByName(String query, {int limit = 20}) async {
    if (searchOverride != null) return searchOverride!(query);
    if (failSearch) throw Exception('network');
    final q = query.trim().toLowerCase();
    return profiles.values
        .where((p) => p.displayName.toLowerCase().startsWith(q))
        .take(limit)
        .toList();
  }

  @override
  Future<Set<String>> getFollowing(String uid) async {
    getFollowingCalls++;
    if (getFollowingOverride != null) return getFollowingOverride!(uid);
    if (failGetFollowing) throw Exception('network');
    return {...?followingByUser[uid]};
  }

  @override
  Future<void> follow({required String uid, required String targetUid}) async {
    if (followGate != null) await followGate!.future;
    if (failFollow) throw Exception('permission-denied');
    followingByUser.putIfAbsent(uid, () => {}).add(targetUid);
  }

  @override
  Future<void> unfollow({
    required String uid,
    required String targetUid,
  }) async {
    if (failFollow) throw Exception('permission-denied');
    followingByUser[uid]?.remove(targetUid);
  }
}

class FakePlaceRepository implements PlaceRepository {
  FakePlaceRepository(this.places);

  final List<Place> places;
  bool fail = false;
  final List<String> searchCalls = [];
  int suggestionCalls = 0;
  final List<Set<String>> getCalls = [];
  final List<bool> refreshMissingCalls = [];

  /// Permite controlar quando/como cada busca responde (ex.: Completer).
  Future<List<Place>> Function(String query)? searchOverride;

  /// Segura cada `getPlaces` até ser liberado.
  Completer<void>? getGate;

  @override
  Future<List<Place>> search(String query) async {
    searchCalls.add(query);
    if (searchOverride != null) return searchOverride!(query);
    if (fail) throw Exception('network');
    final terms = normalizeQuery(query);
    if (serverTerm(terms) == null) return const [];
    final found = places.where((p) => nameMatchesTerms(p.name, terms)).toList()
      ..sort((a, b) => nameLower(a.name).compareTo(nameLower(b.name)));
    return found.take(20).toList();
  }

  @override
  Future<List<Place>> suggestions() async {
    suggestionCalls++;
    if (fail) throw Exception('network');
    return places
        .where((p) => p.source == PlaceSource.curated && p.photoUrl != null)
        .toList()
      ..sort((a, b) => nameLower(a.name).compareTo(nameLower(b.name)));
  }

  @override
  Future<Map<String, Place>> getPlaces(
    Iterable<String> ids, {
    bool refreshMissing = false,
  }) async {
    final wanted = ids.toSet();
    getCalls.add(wanted);
    refreshMissingCalls.add(refreshMissing);
    final gate = getGate;
    if (gate != null) await gate.future;
    if (fail) throw Exception('network');
    return {
      for (final p in places)
        if (wanted.contains(p.id)) p.id: p,
    };
  }

  /// (lat, lng, raio) de cada [nearby].
  final List<({double lat, double lng, double radius})> nearbyCalls = [];

  /// Segura cada `nearby` até ser liberado.
  Completer<void>? nearbyGate;

  @override
  Future<List<NearbyPlace>> nearby(
    double lat,
    double lng,
    double radiusMeters,
  ) async {
    nearbyCalls.add((lat: lat, lng: lng, radius: radiusMeters));
    final gate = nearbyGate;
    if (gate != null) await gate.future;
    if (fail) throw Exception('network');
    final center = (lat: lat, lng: lng);
    return [
      for (final p in places)
        if (p.hasCoordinates)
          (
            place: p,
            distanceMeters: distanceMeters(center, (lat: p.lat!, lng: p.lng!)),
          ),
    ].where((n) => n.distanceMeters <= radiusMeters).toList()..sort(
      compareNearby,
    );
  }
}

/// Localização controlada pelo teste. Por padrão: sem permissão até o
/// primeiro [locate], que a concede e devolve [position].
class FakeLocationService implements LocationService {
  FakeLocationService({this.position, this.granted = false});

  LatLng? position;
  bool granted;

  /// Próximo status de [locate] (diferente de `ok` não devolve posição).
  LocationStatus status = LocationStatus.ok;
  int locateCalls = 0;
  int hasPermissionCalls = 0;
  int openAppSettingsCalls = 0;
  int openLocationSettingsCalls = 0;

  /// Segura cada `locate` até ser liberado.
  Completer<void>? locateGate;

  @override
  Future<bool> hasPermission() async {
    hasPermissionCalls++;
    return granted;
  }

  @override
  Future<LocationResult> locate() async {
    locateCalls++;
    final gate = locateGate;
    if (gate != null) await gate.future;
    if (status != LocationStatus.ok || position == null) {
      return (
        status: status == LocationStatus.ok
            ? LocationStatus.unavailable
            : status,
        position: null,
      );
    }
    granted = true;
    return (status: LocationStatus.ok, position: position);
  }

  @override
  Future<bool> openAppSettings() async {
    openAppSettingsCalls++;
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    openLocationSettingsCalls++;
    return true;
  }
}

class FakeReviewRepository implements ReviewRepository {
  final List<Review> stored = [];
  final List<NewReview> created = [];

  /// Foto enviada com cada avaliação de [created] (mesma posição).
  final List<Uint8List?> createdPhotos = [];

  /// Fotos gravadas, por id da avaliação (simula `reviewPhotos`).
  final Map<String, Uint8List> photos = {};
  final List<List<String>> fetchCalls = [];
  Object? createError;
  Object? fetchError;
  DateTime Function() clock = () =>
      DateTime.utc(2026, 9, 10, 23); // 20h em Natal

  @override
  Future<void> createReview(NewReview review, {Uint8List? photo}) async {
    if (createError != null) throw createError!;
    created.add(review);
    createdPhotos.add(photo);
    final id = 'r${stored.length + 1}';
    if (photo != null) photos[id] = photo;
    stored.add(
      Review(
        id: id,
        authorId: review.authorId,
        authorName: review.authorName,
        placeId: review.placeId,
        placeName: review.placeName,
        scores: review.scores,
        companion: review.companion,
        comment: review.comment,
        createdAt: clock(),
        hasPhoto: photo != null,
      ),
    );
  }

  final List<String> placeFetchCalls = [];
  Object? placeFetchError;

  @override
  Future<List<Review>> fetchReviewsForPlace(
    String placeId,
    List<String> authorIds,
  ) async {
    placeFetchCalls.add(placeId);
    if (placeFetchError != null) throw placeFetchError!;
    final ids = authorIds.toSet();
    return stored
        .where((r) => r.placeId == placeId && ids.contains(r.authorId))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<List<Review>> fetchReviewsByAuthors(
    List<String> authorIds, {
    int? limit,
  }) async {
    fetchCalls.add(authorIds);
    fetchLimits.add(limit);
    if (fetchError != null) throw fetchError!;
    final ids = authorIds.toSet();
    final found = stored.where((r) => ids.contains(r.authorId)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return limit == null ? found : found.take(limit).toList();
  }

  /// `limit` de cada chamada de [fetchReviewsByAuthors] (mesma posição).
  final List<int?> fetchLimits = [];
}

class FakeSavedRepository implements SavedRepository {
  /// uid → (placeId → savedAt).
  final Map<String, Map<String, DateTime>> byUser = {};
  DateTime Function() clock = () => DateTime.utc(2026, 9, 28, 15);

  Object? listError;
  Object? writeError;
  int listCalls = 0;
  final List<String> writes = [];

  /// Escritas em voo agora (para provar que nunca há 2 do mesmo id).
  final Map<String, int> inFlight = {};
  int maxConcurrentPerId = 0;

  /// Segura cada escrita até ser liberada (ex.: Completer).
  Completer<void>? writeGate;
  Future<List<SavedPlace>> Function(String uid)? listOverride;

  void seed(String uid, String placeId, DateTime savedAt) {
    byUser.putIfAbsent(uid, () => {})[placeId] = savedAt;
  }

  @override
  Future<List<SavedPlace>> listSaved(String uid) async {
    listCalls++;
    if (listOverride != null) return listOverride!(uid);
    if (listError != null) throw listError!;
    final list = [
      for (final e in (byUser[uid] ?? const <String, DateTime>{}).entries)
        SavedPlace(placeId: e.key, savedAt: e.value),
    ]..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return list;
  }

  Future<void> _write(String placeId, String op, void Function() apply) async {
    writes.add('$op:$placeId');
    final n = (inFlight[placeId] ?? 0) + 1;
    inFlight[placeId] = n;
    if (n > maxConcurrentPerId) maxConcurrentPerId = n;
    try {
      final gate = writeGate;
      if (gate != null) await gate.future;
      if (writeError != null) throw writeError!;
      apply();
    } finally {
      inFlight[placeId] = inFlight[placeId]! - 1;
    }
  }

  Object? savedAtOfError;
  int savedAtOfCalls = 0;

  /// Como as Rules: `set` num doc que já existe vira update, negado.
  @override
  Future<void> save({required String uid, required String placeId}) =>
      _write(placeId, 'save', () {
        if (byUser[uid]?.containsKey(placeId) ?? false) {
          throw Exception('permission-denied: update');
        }
        seed(uid, placeId, clock());
      });

  @override
  Future<DateTime?> savedAtOf({
    required String uid,
    required String placeId,
  }) async {
    savedAtOfCalls++;
    if (savedAtOfError != null) throw savedAtOfError!;
    return byUser[uid]?[placeId];
  }

  @override
  Future<void> remove({required String uid, required String placeId}) =>
      _write(placeId, 'remove', () => byUser[uid]?.remove(placeId));
}

class FakeListsRepository implements ListsRepository {
  FakeListsRepository({this.saved});

  /// Para o batch "remover de tudo" apagar o salvo junto.
  final FakeSavedRepository? saved;

  /// uid → (listId → lista).
  final Map<String, Map<String, PlaceList>> byUser = {};
  DateTime Function() clock = () => DateTime.utc(2026, 9, 28, 15);

  Object? listError;
  Object? writeError;

  /// Falha só as escritas cujo rótulo (ex.: `add:a:mangai`) casar.
  bool Function(String op)? failWhen;
  int listCalls = 0;
  int _ids = 0;
  final List<String> writes = [];

  /// Segura cada escrita até ser liberada.
  Completer<void>? writeGate;

  PlaceList seed(
    String uid,
    String id,
    String name, {
    String? emoji,
    List<String> placeIds = const [],
    DateTime? createdAt,
  }) {
    final list = PlaceList(
      id: id,
      name: name,
      emoji: emoji,
      placeIds: [...placeIds],
      createdAt:
          createdAt ??
          DateTime.utc(
            2026,
            9,
            1,
          ).add(Duration(minutes: byUser[uid]?.length ?? 0)),
    );
    byUser.putIfAbsent(uid, () => {})[id] = list;
    return list;
  }

  PlaceList? get(String uid, String id) => byUser[uid]?[id];

  @override
  String newListId(String uid) => 'list-${++_ids}';

  @override
  Future<List<PlaceList>> listLists(String uid) async {
    listCalls++;
    if (listError != null) throw listError!;
    return [...(byUser[uid] ?? const <String, PlaceList>{}).values]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<void> _write(String op, void Function() apply) async {
    writes.add(op);
    final gate = writeGate;
    if (gate != null) await gate.future;
    if (writeError != null) throw writeError!;
    if (failWhen?.call(op) ?? false) throw Exception('permission-denied');
    apply();
  }

  PlaceList _existing(String uid, String listId) {
    final l = byUser[uid]?[listId];
    if (l == null) throw Exception('not-found: $listId');
    return l;
  }

  @override
  Future<void> createList({
    required String uid,
    required String listId,
    required String name,
    required String? emoji,
    required List<String> placeIds,
  }) => _write('create:$listId', () {
    if (byUser[uid]?.containsKey(listId) ?? false) {
      throw Exception('permission-denied: update');
    }
    byUser.putIfAbsent(uid, () => {})[listId] = PlaceList(
      id: listId,
      name: name,
      emoji: emoji,
      placeIds: [...placeIds],
      createdAt: clock(),
    );
  });

  @override
  Future<void> updateList({
    required String uid,
    required String listId,
    required String name,
    required String? emoji,
  }) => _write('update:$listId', () {
    byUser[uid]![listId] = _existing(
      uid,
      listId,
    ).copyWith(name: name, emoji: () => emoji);
  });

  @override
  Future<void> deleteList({required String uid, required String listId}) =>
      _write('delete:$listId', () => byUser[uid]?.remove(listId));

  @override
  Future<void> setMembership({
    required String uid,
    required String listId,
    required String placeId,
    required bool member,
  }) => _write('${member ? 'add' : 'drop'}:$listId:$placeId', () {
    final l = _existing(uid, listId);
    final ids = [...l.placeIds]..remove(placeId);
    if (member) ids.add(placeId);
    if (ids.length > PlaceList.maxPlaces) throw Exception('permission-denied');
    byUser[uid]![listId] = l.copyWith(placeIds: ids);
  });

  @override
  Future<void> removeEverywhere({
    required String uid,
    required String placeId,
    required Iterable<String> listIds,
  }) {
    final ids = listIds.toList();
    return _write('removeEverywhere:$placeId:${ids.join(',')}', () {
      // Batch: valida tudo antes de aplicar.
      for (final id in ids) {
        _existing(uid, id);
      }
      saved?.byUser[uid]?.remove(placeId);
      for (final id in ids) {
        final l = _existing(uid, id);
        byUser[uid]![id] = l.copyWith(
          placeIds: [...l.placeIds]..remove(placeId),
        );
      }
    });
  }
}

/// Mesmo contrato da implementação real (cache LRU, dedupe, backoff): só a
/// fonte é um Map em memória.
class FakeReviewPhotoRepository extends CachedReviewPhotoRepository {
  FakeReviewPhotoRepository([
    Map<String, Uint8List>? photos,
    DateTime Function()? clock,
  ]) : photos = photos ?? {},
       super(clock: clock);

  final Map<String, Uint8List> photos;

  /// Leituras na fonte (depois do cache).
  final List<String> calls = [];

  /// Ids cuja leitura falha (ex.: sem rede).
  final Set<String> failing = {};

  /// Segura as respostas até completar (testes de "carregando").
  Completer<void>? gate;

  @override
  Future<Uint8List?> fetch(String reviewId) async {
    calls.add(reviewId);
    if (gate != null) await gate!.future;
    if (failing.contains(reviewId)) throw Exception('network');
    return photos[reviewId];
  }
}

class FakePhotoPicker implements PhotoPicker {
  /// Próxima resposta: bytes, `null` (cancelou) ou erro em [error].
  Uint8List? next;
  Object? error;
  final List<PhotoSource> calls = [];

  /// Segura o seletor "aberto" até completar.
  Completer<void>? gate;

  /// Foto pendente para [retrieveLost] (Android).
  Uint8List? lost;
  int retrieveLostCalls = 0;

  @override
  Future<Uint8List?> pick(PhotoSource source) async {
    calls.add(source);
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    return next;
  }

  @override
  Future<Uint8List?> retrieveLost() async {
    retrieveLostCalls++;
    final l = lost;
    lost = null;
    return l;
  }
}
