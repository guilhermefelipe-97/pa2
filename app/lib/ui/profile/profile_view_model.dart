import 'package:flutter/foundation.dart';

import '../../data/activity_batch.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/lists_repository.dart';
import '../../data/repositories/review_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/repositories/place_repository.dart';
import '../../data/repositories/profile_stats_repository.dart';
import '../../domain/models/place.dart';
import '../../data/repositories/visit_repository.dart';
import '../../domain/models/place_activity.dart';
import '../../domain/models/place_list.dart';
import '../../domain/models/user_profile.dart';
import '../core/follow_events.dart';
import '../core/load_visits.dart';
import '../core/safe_change_notifier.dart';

enum ProfileState { loading, ready, notFound, error, signedOut }

enum ProfileNotice { followFailed, unfollowed }

class ProfileViewModel extends SafeChangeNotifier {
  ProfileViewModel({
    required this.uid,
    required AuthRepository authRepository,
    required UserRepository userRepository,
    required ReviewRepository reviewRepository,
    required FollowEvents followEvents,
    required VisitRepository visitRepository,
    ListsRepository? listsRepository,
    PlaceRepository? placeRepository,
    ProfileStatsRepository? statsRepository,
    DateTime Function()? clock,
  }) : _auth = authRepository,
       _users = userRepository,
       _reviews = reviewRepository,
       _visits = visitRepository,
       _lists = listsRepository,
       _places = placeRepository,
       _stats = statsRepository,
       _follow = FollowStaleness(followEvents),
       _clock = clock ?? DateTime.now;

  static const loadErrorText =
      'Não foi possível carregar o perfil. Verifique sua conexão.';
  static const followErrorText = 'Não foi possível atualizar';
  static const youLabel = 'Você';
  static const unnamedLabel = 'Usuário';

  static const int maxReviews = 50;

  static const int maxVisits = 50;

  final String uid;
  final AuthRepository _auth;
  final UserRepository _users;
  final ReviewRepository _reviews;
  final VisitRepository _visits;
  final ListsRepository? _lists;
  final PlaceRepository? _places;
  final ProfileStatsRepository? _stats;
  Map<String, Place> places = const {};
  ProfileTotals totals = const ProfileTotals();
  final FollowStaleness _follow;
  final DateTime Function() _clock;

  DateTime now() => _clock();

  bool get isSelf => _auth.currentUserId == uid;

  ProfileState _state = ProfileState.loading;
  ProfileState get state => _state;

  UserProfile? _profile;
  String get username => _profile?.username ?? '';
  String get bio => _profile?.bio ?? '';
  String get instagram => _profile?.instagram ?? '';
  String get city => _profile?.city ?? '';

  Future<void> _loadExtra(int seq) async {
    try {
      final results = await Future.wait<Object?>([
        _places
                ?.getPlaces(_reviewList.map((r) => r.placeId))
                .timeout(const Duration(seconds: 10)) ??
            Future.value(null),
        _stats?.totals(uid) ?? Future.value(null),
      ]);
      if (isDisposed || seq != _seq) return;
      places = results[0] as Map<String, Place>? ?? const {};
      totals = results[1] as ProfileTotals? ?? const ProfileTotals();
      notifyListeners();
    } on Object {}
  }

  String get title {
    if (isSelf) return youLabel;
    final name = _profile?.displayName.trim() ?? '';
    return name.isEmpty ? unnamedLabel : name;
  }

  String get displayName {
    final name = _profile?.displayName.trim() ?? '';
    return name.isEmpty ? unnamedLabel : name;
  }

  List<Review> _reviewList = const [];

  List<Review> get reviews => _reviewList;

  List<PlaceActivity> _activities = const [];

  List<PlaceActivity> get activities => _activities;

  String get emptyText => isSelf
      ? 'Você ainda não avaliou nem registrou visita em nenhum lugar'
      : '$title ainda não avaliou nem registrou visita em nenhum lugar';

  bool _following = false;
  bool get isFollowing => _following;

  List<PlaceList> _visibleLists = const [];

  List<PlaceList> get lists => _visibleLists;

  int _listsSeq = 0;

  Future<void> _loadLists() async {
    final seq = ++_listsSeq;
    final repo = _lists;
    if (repo == null || isSelf || !_following) {
      _visibleLists = const [];
      return;
    }
    try {
      final found = await repo.listVisibleLists(uid);
      if (seq != _listsSeq || isDisposed) return;
      _visibleLists = found;
    } on Object catch (e) {
      if (seq != _listsSeq || isDisposed) return;
      debugPrint('Listas indisponíveis (perfil): $e');
      _visibleLists = const [];
    }
    notifyListeners();
  }

  bool _busy = false;
  bool get isBusy => _busy;

  ProfileNotice? _notice;

  ProfileNotice? takeNotice() {
    final n = _notice;
    _notice = null;
    return n;
  }

  bool get isStale => _follow.isStale;

  Future<void> reloadIfStale() => _follow.isStale ? load() : Future.value();

  int _seq = 0;

  Future<void> load() async {
    final me = _auth.currentUserId;
    final seq = ++_seq;
    _follow.clear();
    if (me == null) {
      _state = ProfileState.signedOut;
      notifyListeners();
      return;
    }
    _state = ProfileState.loading;
    notifyListeners();
    try {
      final self = me == uid;
      final results = await Future.wait<Object?>([
        _users.getProfile(uid),
        _reviews.fetchReviewsByAuthors([uid], limit: maxReviews),

        loadVisitsOrEmpty(
          'perfil',
          () => _visits.fetchVisitsByAuthors([uid], limit: maxVisits),
        ),
        if (!self) _users.getFollowing(me),
      ]);
      if (seq != _seq) return;
      final profile = results[0] as UserProfile?;
      if (profile == null && !self) {
        _state = ProfileState.notFound;
      } else {
        _profile = profile;
        _reviewList =
            ([...(results[1]! as ActivityBatch<Review>).items]
                  ..sort((a, b) => b.createdAt.compareTo(a.createdAt)))
                .take(maxReviews)
                .toList();
        final visits = (results[2]! as VisitsRead).batch.items.take(maxVisits);
        _activities = [..._reviewList, ...visits]
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        if (!self && !_busy) {
          _following = (results[3]! as Set<String>).contains(uid);
        }
        _state = ProfileState.ready;
        _loadExtra(seq);

        _loadLists();
      }
    } on Object {
      if (seq != _seq) return;
      _state = ProfileState.error;
    }
    notifyListeners();
  }

  Future<void> toggleFollow() async {
    final me = _auth.currentUserId;
    if (me == null || isSelf || _busy || _state != ProfileState.ready) return;
    final wasFollowing = _following;
    _following = !wasFollowing;
    _busy = true;
    _notice = null;
    notifyListeners();
    try {
      if (wasFollowing) {
        await _users.unfollow(uid: me, targetUid: uid);
      } else {
        await _users.follow(uid: me, targetUid: uid);
      }
      _follow.announce();
      if (wasFollowing) _notice = ProfileNotice.unfollowed;

      _loadLists();
    } on Object {
      _following = wasFollowing;
      _notice = ProfileNotice.followFailed;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> undoUnfollow() async {
    if (!_following) await toggleFollow();
  }

  @override
  void dispose() {
    _follow.dispose();
    super.dispose();
  }
}
