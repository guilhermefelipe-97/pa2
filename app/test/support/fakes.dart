import 'package:naarea/data/repositories/candidate_reviews_repository.dart';
import 'package:naarea/data/repositories/dietary_repository.dart';
import 'package:naarea/data/repositories/owner_repository.dart';
import 'package:naarea/data/repositories/food_tag_repository.dart';
import 'package:naarea/domain/food_tags.dart';

import 'dart:async';
import 'dart:typed_data';

import 'package:naarea/data/activity_batch.dart';
import 'package:naarea/data/chunk.dart';
import 'package:naarea/data/repositories/auth_repository.dart';
import 'package:naarea/data/repositories/lists_repository.dart';
import 'package:naarea/data/repositories/open_report_repository.dart';
import 'package:naarea/data/repositories/place_repository.dart';
import 'package:naarea/data/repositories/review_photo_repository.dart';
import 'package:naarea/data/repositories/review_repository.dart';
import 'package:naarea/data/repositories/saved_repository.dart';
import 'package:naarea/data/repositories/user_repository.dart';
import 'package:naarea/data/repositories/visit_repository.dart';
import 'package:naarea/data/services/location_service.dart';
import 'package:naarea/data/services/photo_picker.dart';
import 'package:naarea/domain/geo.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/domain/open_status.dart';
import 'package:naarea/domain/models/place_activity.dart';
import 'package:naarea/domain/models/place_list.dart';
import 'package:naarea/domain/models/user_profile.dart';
import 'package:naarea/domain/review_lock.dart';
import 'package:naarea/domain/search_tokens.dart';
import 'package:naarea/domain/visit_lock.dart';

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

  final List<LatLng?> searchNear = [];

  Future<List<Place>> Function(String query)? searchOverride;

  final Map<String, Place> discovered = {};

  final List<String> persistCalls = [];
  final List<String> markedPersisted = [];
  Object? persistError;

  Completer<void>? persistGate;

  @override
  Future<void> ensurePersisted(Place place, {required String uid}) async {
    persistCalls.add('$uid:${place.id}');
    final gate = persistGate;
    if (gate != null) await gate.future;
    if (persistError != null) throw persistError!;
    discovered.remove(place.id);
  }

  @override
  Place? discoveredPlace(String placeId) => discovered[placeId];

  final List<String> invalidated = [];

  @override
  void invalidate(String placeId) {
    invalidated.add(placeId);
    discovered.remove(placeId);
  }

  @override
  void markPersisted(Place place) {
    markedPersisted.add(place.id);
    discovered.remove(place.id);
  }

  Completer<void>? getGate;

  @override
  Future<List<Place>> search(String query, {LatLng? near}) async {
    searchCalls.add(query);
    searchNear.add(near);
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

  final List<({double lat, double lng, double radius})> nearbyCalls = [];

  Completer<void>? nearbyGate;

  bool nearbyPartial = false;
  bool nearbyCapped = false;

  Object? nearbyError;

  @override
  Future<NearbyResult> nearby(
    double lat,
    double lng,
    double radiusMeters,
  ) async {
    nearbyCalls.add((lat: lat, lng: lng, radius: radiusMeters));
    final gate = nearbyGate;
    if (gate != null) await gate.future;
    if (nearbyError != null) throw nearbyError!;
    if (fail) throw Exception('network');
    final center = (lat: lat, lng: lng);
    final list =
        [
            for (final p in places)
              if (p.hasCoordinates)
                (
                  place: p,
                  distanceMeters: distanceMeters(center, (
                    lat: p.lat!,
                    lng: p.lng!,
                  )),
                ),
          ].where((n) => n.distanceMeters <= radiusMeters).toList()
          ..sort(compareNearby);
    return NearbyResult(list, partial: nearbyPartial, capped: nearbyCapped);
  }
}

class FakeLocationService implements LocationService {
  FakeLocationService({this.position, this.granted = false});

  LatLng? position;
  bool granted;

  LocationStatus status = LocationStatus.ok;
  int locateCalls = 0;
  int hasPermissionCalls = 0;
  int openAppSettingsCalls = 0;
  int openLocationSettingsCalls = 0;

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

  int lastKnownCalls = 0;

  LatLng? lastKnown;
  bool useLastKnown = false;

  @override
  Future<LatLng?> lastKnownPositionIfGranted() async {
    lastKnownCalls++;
    if (!granted) return null;
    return useLastKnown ? lastKnown : position;
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

class FakeReviewRepository
    implements ReviewRepository, CandidateReviewsRepository {
  final candidateFetches = <({List<String> places, List<String> authors})>[];
  @override
  Future<List<Review>> reviewsForCandidates(
    List<String> placeIds,
    List<String> authorIds, {
    bool Function()? cancelled,
  }) async {
    candidateFetches.add((
      places: List.of(placeIds),
      authors: List.of(authorIds),
    ));
    if (fetchError != null) throw fetchError!;
    if (cancelled?.call() ?? false) return [];
    return stored
        .where(
          (r) => placeIds.contains(r.placeId) && authorIds.contains(r.authorId),
        )
        .toList();
  }

  final List<Review> stored = [];
  final List<NewReview> created = [];

  final List<Uint8List?> createdPhotos = [];

  final Map<String, Uint8List> photos = {};
  final List<List<String>> fetchCalls = [];
  Object? createError;
  Object? fetchError;
  DateTime Function() clock = () => DateTime.utc(2026, 9, 10, 23);

  final List<Place?> createdNewPlaces = [];

  bool? placeCreated;

  final Map<String, DateTime> locks = {};

  Object? lockError;

  Future<DateTime?>? pendingLock;

  final List<String> lockCalls = [];

  void lock(String uid, String placeId, DateTime lastAt) =>
      locks['$uid/$placeId'] = lastAt;

  @override
  Future<DateTime?> reviewLockOf(String uid, String placeId) async {
    lockCalls.add('$uid/$placeId');
    if (pendingLock != null) return pendingLock!;
    if (lockError != null) throw lockError!;
    return locks['$uid/$placeId'];
  }

  Completer<void>? createGate;

  @override
  Future<CreateReviewResult> createReview(
    NewReview review, {
    Uint8List? photo,
    Place? newPlace,
  }) async {
    if (createGate != null) await createGate!.future;
    if (createError != null) throw createError!;
    final lockId = '${review.authorId}/${review.placeId}';
    final now = clock();
    if (isReviewBlocked(locks[lockId], now)) {
      throw StateError('permission-denied: trava do F03');
    }
    locks[lockId] = now;
    created.add(review);
    createdPhotos.add(photo);
    createdNewPlaces.add(newPlace);
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
        priceBand: review.priceBand,
        couvert: review.couvert,
        serviceFee: review.serviceFee,
        tags: review.tags,
      ),
    );
    return (placeCreated: placeCreated ?? newPlace != null);
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
  Future<ActivityBatch<Review>> fetchReviewsByAuthors(
    List<String> authorIds, {
    int? limit,
  }) async {
    fetchCalls.add(authorIds);
    fetchLimits.add(limit);
    if (fetchError != null) throw fetchError!;
    return fakeAuthorBatches(stored, authorIds, perBatchLimit, limit);
  }

  int perBatchLimit = 100;

  final List<int?> fetchLimits = [];
}

class FakeSavedRepository implements SavedRepository {
  final Map<String, Map<String, DateTime>> byUser = {};
  DateTime Function() clock = () => DateTime.utc(2026, 9, 28, 15);

  Object? listError;
  Object? writeError;
  int listCalls = 0;
  final List<String> writes = [];

  final Map<String, int> inFlight = {};
  int maxConcurrentPerId = 0;

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

  final Set<String> failSaveIds = {};

  @override
  Future<void> save({required String uid, required String placeId}) =>
      _write(placeId, 'save', () {
        if (failSaveIds.contains(placeId)) {
          throw Exception('permission-denied: $placeId');
        }
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

  final FakeSavedRepository? saved;

  final Map<String, Map<String, PlaceList>> byUser = {};
  DateTime Function() clock = () => DateTime.utc(2026, 9, 28, 15);

  Object? listError;
  Object? writeError;

  bool Function(String op)? failWhen;
  int listCalls = 0;
  int _ids = 0;
  final List<String> writes = [];

  Completer<void>? writeGate;

  PlaceList seed(
    String uid,
    String id,
    String name, {
    String? emoji,
    List<String> placeIds = const [],
    DateTime? createdAt,
    bool visible = false,
    ListCredit? copiedFrom,
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
      visible: visible,
      copiedFrom: copiedFrom,
    );
    byUser.putIfAbsent(uid, () => {})[id] = list;
    return list;
  }

  final Map<String, Set<String>> copies = {};

  FakeUserRepository? users;

  FakeAuthRepository? auth;

  Object? visibleListsError;
  Object? copyCountError;
  Object? recordCopyError;
  final List<String> visibleListsCalls = [];

  int deniedCopies = 0;

  Completer<void>? copyCountGate;

  Completer<void>? listGate;

  PlaceList? get(String uid, String id) => byUser[uid]?[id];

  @override
  String newListId(String uid) => 'list-${++_ids}';

  @override
  Future<List<PlaceList>> listLists(String uid) async {
    listCalls++;
    final gate = listGate;
    if (gate != null) await gate.future;
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
    ListCredit? copiedFrom,
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
      copiedFrom: copiedFrom,
    );
  });

  @override
  Future<void> setVisible({
    required String uid,
    required String listId,
    required bool visible,
  }) => _write('visible:$listId:$visible', () {
    byUser[uid]![listId] = _existing(uid, listId).copyWith(visible: visible);
  });

  bool _follows(String follower, String owner) =>
      users == null ||
      (users!.followingByUser[follower]?.contains(owner) ?? false);

  @override
  Future<List<PlaceList>> listVisibleLists(String ownerUid) async {
    visibleListsCalls.add(ownerUid);
    if (visibleListsError != null) throw visibleListsError!;

    final reader = auth?.currentUserId;
    if (reader != null && reader != ownerUid && !_follows(reader, ownerUid)) {
      throw const ListAccessDeniedException();
    }
    return [
      for (final l in (byUser[ownerUid] ?? const <String, PlaceList>{}).values)
        if (l.visible) l,
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  @override
  Future<int> copyCount({
    required String ownerUid,
    required String listId,
  }) async {
    final gate = copyCountGate;
    if (gate != null) await gate.future;
    if (copyCountError != null) throw copyCountError!;
    return copies['$ownerUid/$listId']?.length ?? 0;
  }

  @override
  Future<void> recordCopy({
    required String ownerUid,
    required String listId,
    required String copierUid,
    required String copiedListId,
  }) async {
    writes.add('copy:$ownerUid/$listId:$copierUid');
    if (recordCopyError != null) throw recordCopyError!;

    final list = byUser[ownerUid]?[listId];
    final key = '$ownerUid/$listId';
    final target = byUser[copierUid]?[copiedListId];
    if (target?.copiedFrom?.uid != ownerUid ||
        target?.copiedFrom?.listId != listId) {
      throw StateError('Cópia sem comprovação');
    }
    if (list == null ||
        !list.visible ||
        !_follows(copierUid, ownerUid) ||
        (copies[key]?.contains(copierUid) ?? false)) {
      deniedCopies++;
      return;
    }
    copies.putIfAbsent(key, () => {}).add(copierUid);
  }

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
      _write('delete:$listId', () {
        byUser[uid]?.remove(listId);

        copies.remove('$uid/$listId');
      });

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

class FakeReviewPhotoRepository extends CachedReviewPhotoRepository {
  FakeReviewPhotoRepository([
    Map<String, Uint8List>? photos,
    DateTime Function()? clock,
  ]) : photos = photos ?? {},
       super(clock: clock);

  final Map<String, Uint8List> photos;

  final List<String> calls = [];

  final Set<String> failing = {};

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
  Uint8List? next;
  Object? error;
  final List<PhotoSource> calls = [];

  Completer<void>? gate;

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

class FakeVisitRepository implements VisitRepository {
  final List<Visit> stored = [];
  final List<NewVisit> created = [];
  final List<Place?> createdNewPlaces = [];
  Object? createError;
  Object? fetchError;
  Object? lockError;

  Completer<void>? createGate;

  Future<DateTime?>? pendingLock;

  DateTime Function() clock = () => DateTime.utc(2026, 9, 10, 23);

  final Map<String, DateTime> locks = {};
  final List<String> lockCalls = [];
  final List<List<String>> fetchCalls = [];
  final List<String> placeFetchCalls = [];

  bool? placeCreated;

  void lock(String uid, String placeId, DateTime lastAt) =>
      locks['$uid/$placeId'] = lastAt;

  @override
  Future<DateTime?> visitLockOf(String uid, String placeId) async {
    lockCalls.add('$uid/$placeId');
    if (pendingLock != null) return pendingLock!;
    if (lockError != null) throw lockError!;
    return locks['$uid/$placeId'];
  }

  @override
  Future<CreateVisitResult> createVisit(
    NewVisit visit, {
    Place? newPlace,
  }) async {
    if (createGate != null) await createGate!.future;
    if (createError != null) throw createError!;
    final lockId = '${visit.authorId}/${visit.placeId}';
    final now = clock();
    if (isVisitBlocked(locks[lockId], now)) {
      throw StateError('permission-denied: trava do F15');
    }
    locks[lockId] = now;
    created.add(visit);
    createdNewPlaces.add(newPlace);
    stored.add(
      Visit(
        id: 'v${stored.length + 1}',
        authorId: visit.authorId,
        authorName: visit.authorName,
        placeId: visit.placeId,
        placeName: visit.placeName,
        companion: visit.companion,
        createdAt: now,
        priceBand: visit.priceBand,
        couvert: visit.couvert,
        serviceFee: visit.serviceFee,
      ),
    );
    return (placeCreated: placeCreated ?? newPlace != null);
  }

  @override
  Future<ActivityBatch<Visit>> fetchVisitsByAuthors(
    List<String> authorIds, {
    int? limit,
  }) async {
    fetchCalls.add(authorIds);
    if (fetchError != null) throw fetchError!;
    return fakeAuthorBatches(stored, authorIds, perBatchLimit, limit);
  }

  int perBatchLimit = 100;

  @override
  Future<List<Visit>> fetchVisitsForPlace(
    String placeId,
    List<String> authorIds,
  ) async {
    placeFetchCalls.add(placeId);
    if (fetchError != null) throw fetchError!;
    final ids = authorIds.toSet();
    return stored
        .where((v) => v.placeId == placeId && ids.contains(v.authorId))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }
}

ActivityBatch<T> fakeAuthorBatches<T extends PlaceActivity>(
  List<T> stored,
  List<String> authorIds,
  int perBatchLimit,
  int? limit,
) {
  final batchLimit = limit == null || limit > perBatchLimit
      ? perBatchLimit
      : limit;
  return mergeAuthorBatches(
    [
      for (final batch in chunked(authorIds.toSet().toList(), whereInLimit))
        () {
          final ids = batch.toSet();
          final items =
              (stored.where((a) => ids.contains(a.authorId)).toList()
                    ..sort((a, b) => b.createdAt.compareTo(a.createdAt)))
                  .take(batchLimit)
                  .toList();
          return (
            items: items,
            createdAts: [for (final a in items) a.createdAt],
            docCount: items.length,
          );
        }(),
    ],
    batchLimit: batchLimit,
    limit: limit,
  );
}

class FakeOpenReportRepository implements OpenReportRepository {
  final List<OpenReport> stored = [];
  final List<NewOpenReport> created = [];
  final List<Place?> createdNewPlaces = [];
  Object? createError;
  Object? fetchError;
  Object? lockError;

  Completer<void>? createGate;

  DateTime Function() clock = () => DateTime.utc(2026, 9, 10, 23);

  final Map<String, DateTime> locks = {};
  final List<String> placeFetchCalls = [];
  final List<List<String>> placesFetchCalls = [];

  void lock(String uid, String placeId, DateTime lastAt) =>
      locks['$uid/$placeId'] = lastAt;

  void add(
    String placeId, {
    required bool open,
    required DateTime at,
    String authorId = 'ana',
    String authorName = 'Ana',
  }) => stored.add(
    OpenReport(
      id: 'o${stored.length + 1}',
      authorId: authorId,
      authorName: authorName,
      placeId: placeId,
      open: open,
      createdAt: at,
    ),
  );

  @override
  Future<DateTime?> openReportLockOf(String uid, String placeId) async {
    if (lockError != null) throw lockError!;
    return locks['$uid/$placeId'];
  }

  @override
  Future<CreateOpenReportResult> createReport(
    NewOpenReport report, {
    Place? newPlace,
  }) async {
    if (createGate != null) await createGate!.future;
    if (createError != null) throw createError!;
    final lockId = '${report.authorId}/${report.placeId}';
    final now = clock();
    if (isOpenReportBlocked(locks[lockId], now)) {
      throw StateError('permission-denied: trava do F20');
    }
    locks[lockId] = now;
    created.add(report);
    createdNewPlaces.add(newPlace);
    add(
      report.placeId,
      open: report.open,
      at: now,
      authorId: report.authorId,
      authorName: report.authorName,
    );
    return (placeCreated: newPlace != null);
  }

  @override
  Future<List<OpenReport>> fetchForPlace(
    String placeId, {
    required DateTime since,
  }) async {
    placeFetchCalls.add(placeId);
    if (fetchError != null) throw fetchError!;
    return stored
        .where((r) => r.placeId == placeId && !r.createdAt.isBefore(since))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<List<OpenReport>> fetchForPlaces(
    List<String> placeIds, {
    required DateTime since,
  }) async {
    placesFetchCalls.add(placeIds);
    if (fetchError != null) throw fetchError!;
    final ids = placeIds.toSet();
    return stored
        .where((r) => ids.contains(r.placeId) && !r.createdAt.isBefore(since))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }
}

class FakeDietaryRepository implements DietaryRepository {
  final stored = <String, Set<String>>{};
  Future<Set<String>> Function(String uid)? read;
  bool fail = false;
  @override
  Future<Set<String>> load(String uid) async {
    if (read != null) return read!(uid);
    if (fail) throw StateError('rede');
    return {...?stored[uid]};
  }

  @override
  Future<void> save(String uid, Set<String> tags) async {
    if (fail) throw StateError('rede');
    stored[uid] = {...tags};
  }
}

class FakeOwnerRepository implements OwnerRepository {
  final owners = <String, String>{};
  final requests = <String, List<OwnershipRequest>>{};
  @override
  Future<String?> ownerOf(String placeId) async => owners[placeId];
  @override
  Future<List<OwnershipRequest>> requestsOf(String uid) async =>
      requests[uid] ?? [];
  @override
  Future<OwnershipRequest> request(String uid, String placeId) async {
    final list = requests.putIfAbsent(uid, () => []);
    for (final r in list) {
      if (r.placeId == placeId) return r;
    }
    final r = OwnershipRequest(placeId, 'pending');
    list.add(r);
    return r;
  }
}

class FakeFoodTagRepository implements FoodTagRepository {
  FakeFoodTagRepository(this.reviews, this.owners);
  final FakeReviewRepository reviews;
  final FakeOwnerRepository owners;
  bool fail = false;
  @override
  Future<Map<String, Map<String, int>>> confirmedFor(
    Iterable<String> placeIds,
  ) async {
    if (fail) throw StateError('rede');
    return {
      for (final id in placeIds)
        id: confirmedFoodTags(
          reviews.stored.where((r) => r.placeId == id),
          ownerUid: owners.owners[id],
        ),
    };
  }
}
