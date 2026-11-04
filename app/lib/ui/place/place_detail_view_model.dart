import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/activity_batch.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/place_repository.dart';
import '../../data/repositories/review_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/repositories/visit_repository.dart';
import '../../domain/feed.dart';
import '../../data/repositories/food_tag_repository.dart';
import '../../domain/models/place.dart';
import '../../domain/models/place_activity.dart';
import '../../domain/models/scores.dart' as scores;
import '../../domain/price_summary.dart';
import '../../domain/review_lock.dart';
import '../../domain/visit_lock.dart';
import '../core/follow_events.dart';
import '../core/load_visits.dart';
import '../core/safe_change_notifier.dart';
import '../open/open_now_view_model.dart';

class PlaceDetailViewModel extends SafeChangeNotifier {
  PlaceDetailViewModel({
    required this.placeId,
    Object? initial,
    required AuthRepository authRepository,
    required UserRepository userRepository,
    required PlaceRepository placeRepository,
    required ReviewRepository reviewRepository,
    required FollowEvents followEvents,
    required VisitRepository visitRepository,
    this.openNow,
    this.foodTagRepository,
    DateTime Function()? clock,
  }) : _auth = authRepository,
       _users = userRepository,
       _places = placeRepository,
       _reviews = reviewRepository,
       _visits = visitRepository,
       _follow = FollowStaleness(followEvents),
       _clock = clock ?? DateTime.now {
    switch (initial) {
      case final FeedItem item when item.placeId == placeId:
        _place = item.place;
        _visibleReviews = item.reviews;
        _visibleVisits = item.visits;
      case final Place p when p.id == placeId:
        _place = p;
    }
  }

  static const errorText =
      'Não foi possível carregar o local. Verifique sua conexão.';

  static const youLabel = 'Você';

  final String placeId;
  final FoodTagRepository? foodTagRepository;
  Map<String, int> confirmedTags = {};
  bool tagsFailed = false;
  int _tagsSeq = 0;
  Future<void> loadTags() async {
    final seq = ++_tagsSeq;
    try {
      final tags = await foodTagRepository?.confirmedFor([placeId]);
      if (isDisposed || seq != _tagsSeq) return;
      confirmedTags = tags?[placeId] ?? {};
      tagsFailed = false;
    } on Object {
      if (isDisposed || seq != _tagsSeq) return;
      confirmedTags = {};
      tagsFailed = true;
    }
    notifyListeners();
  }

  final OpenNowViewModel? openNow;

  final AuthRepository _auth;
  final UserRepository _users;
  final PlaceRepository _places;
  final ReviewRepository _reviews;

  final VisitRepository _visits;
  final FollowStaleness _follow;
  final DateTime Function() _clock;

  bool get isStale => _follow.isStale;

  Future<void> reloadIfStale() => _follow.isStale ? load() : Future.value();

  DateTime now() => _clock();

  String? get currentUserId => _auth.currentUserId;

  bool isOwn(PlaceActivity r) {
    final uid = _auth.currentUserId;
    return uid != null && r.authorId == uid;
  }

  Place? _place;
  Place? get place => _place;

  List<Review>? _visibleReviews;

  List<Review> get reviews => _visibleReviews ?? const [];

  bool get reviewsKnown => _visibleReviews != null;

  List<Visit> _visibleVisits = const [];

  List<Visit> get visits => _visibleVisits;

  String? get recurrenceLabel {
    final i = item;
    if (i == null) return null;
    final uid = _auth.currentUserId;
    final own = i.sources.where((s) => s.authorId == uid).toList();
    return placeRecurrenceLabel(
      trips: i.trips,
      friends: i.sources.length - own.length,
      ownTrips: own.isEmpty ? 0 : own.single.trips,
      anyoneReturned: i.recurrent != null,
    );
  }

  bool get _hasOwnVisit {
    final uid = _auth.currentUserId;
    return uid != null && visits.any((v) => v.authorId == uid);
  }

  bool get hasOwnReview {
    final uid = _auth.currentUserId;
    return uid != null && reviews.any((r) => r.authorId == uid);
  }

  DateTime? _lockLastAt;
  Timer? _unlockTimer;
  int _lockSeq = 0;

  DateTime? get reviewBlockedSince =>
      isReviewBlocked(_lockLastAt, now()) ? _lockLastAt : null;

  String? get reviewAgainLabel {
    final since = reviewBlockedSince;
    return since == null ? null : reviewAgainFromLabel(since);
  }

  void _setLock(DateTime? lastAt) {
    _lockLastAt = lastAt;
    _unlockTimer?.cancel();
    _unlockTimer = null;
    if (lastAt == null || !isReviewBlocked(lastAt, now())) return;

    _unlockTimer = Timer(
      reviewAllowedAt(lastAt).difference(now()),
      notifyListeners,
    );
  }

  Future<void> _loadLock(String uid) async {
    final seq = ++_lockSeq;
    DateTime? lastAt;
    try {
      lastAt = await _reviews
          .reviewLockOf(uid, placeId)
          .timeout(reviewLockTimeout);
    } on Object catch (e) {
      debugPrint('Trava de avaliação indisponível no detalhe: $e');
      lastAt = null;
    }
    if (seq != _lockSeq) return;
    _setLock(lastAt);
    notifyListeners();
  }

  String get reviewCountLabel {
    final n = reviews.length;
    final v = visits.length;
    final reviewPart = hasOwnReview
        ? scores.reviewCountLabel(n)
        : scores.countLabel(n, 'avaliação de amigo', 'avaliações de amigos');
    if (v == 0) return reviewPart;
    final visitPart = _hasOwnVisit
        ? scores.countLabel(v, 'visita', 'visitas')
        : scores.countLabel(v, 'visita de amigo', 'visitas de amigos');
    return n == 0 ? visitPart : '$reviewPart · $visitPart';
  }

  Place? _itemPlace;
  List<Review>? _itemReviews;
  List<Visit>? _itemVisits;
  FeedItem? _item;

  FeedItem? get item {
    final p = _place;
    final r = _visibleReviews;
    final v = _visibleVisits;
    if (identical(p, _itemPlace) &&
        identical(r, _itemReviews) &&
        identical(v, _itemVisits)) {
      return _item;
    }
    _itemPlace = p;
    _itemReviews = r;
    _itemVisits = v;
    _item = (p == null || r == null || (r.isEmpty && v.isEmpty))
        ? null
        : FeedItem(place: p, activities: [...r, ...v]);
    return _item;
  }

  FeedItem? _priceItem;
  PriceSummary? _price;

  PriceSummary? get price {
    final i = item;
    if (!identical(i, _priceItem)) {
      _priceItem = i;
      _price = i?.priceAt(now());
    }
    return _price;
  }

  String? get priceCountLabel {
    final p = price;
    if (p == null) return null;
    final own = p.reports.any(isOwn);
    final n = p.count;
    if (!own) {
      return scores.countLabel(n, 'relato de amigo', 'relatos de amigos');
    }
    if (n == 1) return '1 relato seu';
    return '$n relatos (seu e de amigos)';
  }

  DateTime? _visitLockLastAt;
  Timer? _visitUnlockTimer;
  int _visitLockSeq = 0;

  DateTime? _localVisitAt;

  String? get visitBlockedLabel {
    final lastAt = _visitLockLastAt;
    return isVisitBlocked(lastAt, now()) ? visitBlockedMessage(lastAt!) : null;
  }

  void markVisited() {
    _visitLockSeq++;
    _localVisitAt = now();
    _setVisitLock(_localVisitAt);
    notifyListeners();
  }

  void _setVisitLock(DateTime? read) {
    final local = _localVisitAt;
    final lastAt = local != null && (read == null || local.isAfter(read))
        ? local
        : read;
    _visitLockLastAt = lastAt;
    _visitUnlockTimer?.cancel();
    _visitUnlockTimer = null;
    if (lastAt == null || !isVisitBlocked(lastAt, now())) return;
    _visitUnlockTimer = Timer(
      visitAllowedAt(lastAt).difference(now()),
      notifyListeners,
    );
  }

  Future<void> _loadVisitLock(String uid) async {
    final seq = ++_visitLockSeq;
    DateTime? lastAt;
    try {
      lastAt = await _visits
          .visitLockOf(uid, placeId)
          .timeout(visitLockTimeout);
    } on Object catch (e) {
      debugPrint('Trava de visita indisponível no detalhe: $e');
      lastAt = null;
    }
    if (seq != _visitLockSeq) return;
    _setVisitLock(lastAt);
    notifyListeners();
  }

  Future<VisitsRead> _fetchVisits(List<String> authors) => loadVisitsOrEmpty(
    'detalhe',
    () async =>
        ActivityBatch(await _visits.fetchVisitsForPlace(placeId, authors)),
  );

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _notFound = false;

  bool get notFound => _notFound;

  String? _errorMessage;

  String? get errorMessage => _errorMessage;

  int _seq = 0;

  Future<void> load() async {
    final seq = ++_seq;
    unawaited(loadTags());
    _follow.clear();
    _errorMessage = null;
    _notFound = false;
    final uid = _auth.currentUserId;
    if (uid == null) {
      _lockSeq++;
      _setLock(null);
      _visitLockSeq++;
      _localVisitAt = null;
      _setVisitLock(null);

      _isLoading = false;
      if (_place == null || _visibleReviews == null) _errorMessage = errorText;
      notifyListeners();
      return;
    }
    _isLoading = true;
    notifyListeners();
    final lock = _loadLock(uid);
    final visitLock = _loadVisitLock(uid);
    try {
      final results = await Future.wait([
        _places.getPlaces([placeId]),
        _users.getFollowing(uid),
      ]);
      if (seq != _seq) return;
      final found = (results[0] as Map<String, Place>)[placeId];

      final authors = {...results[1] as Set<String>, uid};
      final fetchedVisits = _fetchVisits(authors.toList());
      final fetched = await _reviews.fetchReviewsForPlace(
        placeId,
        authors.toList(),
      );
      final visitsRead = await fetchedVisits;
      if (seq != _seq) return;
      if (found != null) {
        _place = found;
      } else if (_place == null) {
        _notFound = true;
      }
      _visibleReviews = [
        for (final r in fetched) r.authorId == uid ? _asYou(r) : r,
      ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (visitsRead.ok) {
        _visibleVisits = [
          for (final v in visitsRead.batch.items)
            v.authorId == uid ? _visitAsYou(v) : v,
        ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      }
    } on Object {
      if (seq != _seq) return;
      if (_place == null || _visibleReviews == null) _errorMessage = errorText;
    } finally {
      if (seq == _seq) {
        _isLoading = false;
        notifyListeners();
      }
    }

    await lock;
    await visitLock;
  }

  static Review _asYou(Review r) => Review(
    silent: r.silent,
    id: r.id,
    authorId: r.authorId,
    authorName: youLabel,
    placeId: r.placeId,
    placeName: r.placeName,
    scores: r.scores,
    tags: r.tags,
    companion: r.companion,
    comment: r.comment,
    createdAt: r.createdAt,
    hasPhoto: r.hasPhoto,
    priceBand: r.priceBand,
    couvert: r.couvert,
    serviceFee: r.serviceFee,
  );

  static Visit _visitAsYou(Visit v) => Visit(
    silent: v.silent,
    id: v.id,
    authorId: v.authorId,
    authorName: youLabel,
    placeId: v.placeId,
    placeName: v.placeName,
    companion: v.companion,
    createdAt: v.createdAt,
    priceBand: v.priceBand,
    couvert: v.couvert,
    serviceFee: v.serviceFee,
  );

  @override
  void dispose() {
    openNow?.dispose();
    _visitUnlockTimer?.cancel();
    _visitLockSeq++;
    _unlockTimer?.cancel();
    _lockSeq++;
    _follow.dispose();
    super.dispose();
  }
}
