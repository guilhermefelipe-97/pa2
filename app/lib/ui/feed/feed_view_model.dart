import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/place_repository.dart';
import '../../data/repositories/review_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/repositories/visit_repository.dart';
import '../../domain/feed.dart';
import '../../domain/food_tags.dart';
import '../../data/repositories/food_tag_repository.dart';
import '../dietary/dietary_store.dart';
import '../../domain/models/place.dart';
import '../core/follow_events.dart';
import '../core/load_visits.dart';
import '../core/safe_change_notifier.dart';

class FeedViewModel extends SafeChangeNotifier {
  FeedViewModel({
    required AuthRepository authRepository,
    required UserRepository userRepository,
    required ReviewRepository reviewRepository,
    required PlaceRepository placeRepository,
    required FollowEvents followEvents,
    required VisitRepository visitRepository,
    this.dietary,
    this.foodTagRepository,
    DateTime Function()? clock,
  }) : _auth = authRepository,
       _users = userRepository,
       _reviews = reviewRepository,
       _places = placeRepository,
       _visits = visitRepository,
       _follow = FollowStaleness(followEvents),
       _clock = clock ?? DateTime.now {
    _auth.addListener(_sessionChanged);
    dietary?.addListener(_preferencesChanged);
  }
  final DietaryStore? dietary;
  final FoodTagRepository? foodTagRepository;
  int _generation = 0;
  int _dietaryRevision = -1;
  Map<String, Map<String, int>> confirmedTags = {};
  bool get hasFoodFilter => dietary?.tags.isNotEmpty ?? false;
  void _sessionChanged() {
    _generation++;
    _items = const [];
    confirmedTags = {};
    _loadedOnce = false;
    _loadedUid = null;
    _following = const {};
    notifyListeners();
    load();
  }

  void _preferencesChanged() {
    final store = dietary!;

    if (!store.ready || store.loading || store.revision != _dietaryRevision) {
      _generation++;
      _items = const [];
      notifyListeners();
    }
    if (store.error != null) {
      _errorMessage = store.error;
      _isLoading = false;
      notifyListeners();
      return;
    }
    if (!store.loading && store.revision != _dietaryRevision) {
      _dietaryRevision = store.revision;
      load();
    }
  }

  final AuthRepository _auth;
  final UserRepository _users;
  final ReviewRepository _reviews;
  final PlaceRepository _places;
  final VisitRepository _visits;
  final FollowStaleness _follow;
  final DateTime Function() _clock;

  DateTime now() => _clock();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  List<FeedItem> _items = const [];
  List<FeedItem> get items => _items;

  bool _followsNobody = false;

  Set<String> _following = const {};

  bool isFollowing(String uid) => _following.contains(uid);

  String? _loadedUid;

  bool get isStale => _follow.isStale;

  Future<void> reloadIfStale() => _follow.isStale ? load() : Future.value();

  bool get followsNobody => _followsNobody;

  bool _loadedOnce = false;
  bool get loadedOnce => _loadedOnce;

  bool _reloadPending = false;
  Future<void>? _inFlight;

  Future<void> load() {
    if (_inFlight != null) {
      _reloadPending = true;
      return _inFlight!;
    }
    final run = _loadLoop();
    _inFlight = run;
    return run;
  }

  Future<void> _loadLoop() async {
    try {
      do {
        _reloadPending = false;
        await _loadOnce();
      } while (_reloadPending && !isDisposed);
    } finally {
      _inFlight = null;
    }
  }

  Future<void> _loadOnce() async {
    final uid = _auth.currentUserId;
    final generation = _generation;
    if (uid != _loadedUid) {
      _following = const {};
      _items = const [];
      _followsNobody = false;
      _loadedOnce = false;
      _loadedUid = null;
    }
    if (uid == null) return;

    _follow.clear();
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final preferences = dietary;
      if (preferences != null &&
          (!preferences.ready ||
              preferences.loading ||
              preferences.error != null)) {
        _items = const [];
        throw StateError('preferências indisponíveis');
      }
      final selected = {...?preferences?.tags};

      final following = {...await _users.getFollowing(uid)}..remove(uid);
      var items = const <FeedItem>[];
      if (following.isNotEmpty) {
        final read = await loadFriendActivities(
          reviews: _reviews,
          visits: _visits,
          authors: following.toList(),
          where: 'feed',
          publicOnly: true,
        );

        final places = await _loadPlaces({
          for (final a in read.activities) a.placeId,
        });
        items = groupPublicActivitiesIntoFeed(read.activities, places: places);
      }
      final tags = foodTagRepository == null
          ? <String, Map<String, int>>{}
          : await foodTagRepository!.confirmedFor(items.map((i) => i.placeId));
      if (generation != _generation ||
          uid != _auth.currentUserId ||
          isDisposed) {
        return;
      }
      confirmedTags = tags;
      items = items
          .where((i) => matchesFoodTags(selected, tags[i.placeId] ?? {}))
          .toList();

      _following = following;
      _followsNobody = following.isEmpty;
      _items = items;
      _loadedOnce = true;
      _loadedUid = uid;
    } on Object {
      if (generation != _generation ||
          uid != _auth.currentUserId ||
          isDisposed) {
        return;
      }
      if (dietary != null || foodTagRepository != null) _items = const [];
      _errorMessage =
          'Não foi possível carregar o feed. Verifique sua conexão.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, Place>> _loadPlaces(Set<String> ids) async {
    if (ids.isEmpty) return const {};
    try {
      return await _places.getPlaces(ids);
    } on Object {
      return const {};
    }
  }

  Future<void> retry() async {
    if (dietary?.error != null) await dietary!.load();
    await load();
  }

  Future<void> signOut() => _auth.signOut();

  String? get currentUserId => _auth.currentUserId;

  @override
  void dispose() {
    _auth.removeListener(_sessionChanged);
    dietary?.removeListener(_preferencesChanged);
    _generation++;
    _follow.dispose();
    super.dispose();
  }
}
