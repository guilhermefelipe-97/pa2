// Fakes escritos à mão (sem mocks gerados) para testar os ViewModels.
import 'dart:async';

import 'package:naarea/data/repositories/auth_repository.dart';
import 'package:naarea/data/repositories/place_repository.dart';
import 'package:naarea/data/repositories/review_repository.dart';
import 'package:naarea/data/repositories/user_repository.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/domain/models/review.dart';
import 'package:naarea/domain/models/user_profile.dart';

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
    signUpCalls.add({'displayName': displayName, 'email': email, 'password': password});
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
  Future<void> createProfile({required String uid, required String displayName}) async {
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
  Future<void> unfollow({required String uid, required String targetUid}) async {
    if (failFollow) throw Exception('permission-denied');
    followingByUser[uid]?.remove(targetUid);
  }
}

class FakePlaceRepository implements PlaceRepository {
  FakePlaceRepository(this.places);

  final List<Place> places;
  bool fail = false;

  @override
  Future<List<Place>> listPlaces() async {
    if (fail) throw Exception('network');
    return places;
  }
}

class FakeReviewRepository implements ReviewRepository {
  final List<Review> stored = [];
  final List<NewReview> created = [];
  final List<List<String>> fetchCalls = [];
  Object? createError;
  Object? fetchError;
  DateTime Function() clock = () => DateTime.utc(2026, 9, 10, 23); // 20h em Natal

  @override
  Future<void> createReview(NewReview review) async {
    if (createError != null) throw createError!;
    created.add(review);
    stored.add(Review(
      id: 'r${stored.length + 1}',
      authorId: review.authorId,
      authorName: review.authorName,
      placeId: review.placeId,
      placeName: review.placeName,
      scores: review.scores,
      companion: review.companion,
      createdAt: clock(),
    ));
  }

  @override
  Future<List<Review>> fetchReviewsByAuthors(List<String> authorIds) async {
    fetchCalls.add(authorIds);
    if (fetchError != null) throw fetchError!;
    final ids = authorIds.toSet();
    return stored.where((r) => ids.contains(r.authorId)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }
}
