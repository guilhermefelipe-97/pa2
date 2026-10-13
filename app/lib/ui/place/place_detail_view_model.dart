import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/activity_batch.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/place_repository.dart';
import '../../data/repositories/review_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/repositories/visit_repository.dart';
import '../../domain/feed.dart';
import '../../domain/models/place.dart';
import '../../domain/models/place_activity.dart';
import '../../domain/models/scores.dart' as scores;
import '../../domain/review_lock.dart';
import '../../domain/visit_lock.dart';
import '../core/follow_events.dart';
import '../core/load_visits.dart';
import '../core/safe_change_notifier.dart';

/// Detalhe do local, autônomo por `placeId` (F11): carrega o local e as
/// avaliações e visitas ("Voltei aqui", F15) de quem o usuário segue ali (e
/// as dele, como "Você"). Quando a navegação traz dados prontos (`FeedItem` do feed ou `Place` da aba
/// "Quero ir"/seletor), eles aparecem já e a carga só atualiza.
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

  /// Nome mostrado nas avaliações do próprio usuário.
  static const youLabel = 'Você';

  final String placeId;
  final AuthRepository _auth;
  final UserRepository _users;
  final PlaceRepository _places;
  final ReviewRepository _reviews;

  final VisitRepository _visits;
  final FollowStaleness _follow;
  final DateTime Function() _clock;

  /// Alguém foi seguido/deixado de seguir em outra tela desde a última carga
  /// (muda quais avaliações aparecem aqui).
  bool get isStale => _follow.isStale;

  /// Ao voltar a ficar visível (ex.: do perfil de quem avaliou).
  Future<void> reloadIfStale() => _follow.isStale ? load() : Future.value();

  DateTime now() => _clock();

  /// Usuário logado (para marcar a própria foto como "Sua foto").
  String? get currentUserId => _auth.currentUserId;

  /// A ida (avaliação ou visita) é do usuário logado.
  bool isOwn(PlaceActivity r) {
    final uid = _auth.currentUserId;
    return uid != null && r.authorId == uid;
  }

  Place? _place;
  Place? get place => _place;

  /// `null` enquanto não se sabe (carregando sem dados prontos).
  List<Review>? _visibleReviews;

  /// Avaliações dos amigos e do próprio usuário (como "Você"), mais
  /// recentes primeiro. Vazia = ninguém avaliou.
  List<Review> get reviews => _visibleReviews ?? const [];

  bool get reviewsKnown => _visibleReviews != null;

  List<Visit> _visibleVisits = const [];

  /// Visitas ("Voltei aqui") dos amigos e do usuário, mais recentes primeiro.
  List<Visit> get visits => _visibleVisits;

  /// "5 idas de 3 amigos" (o selo acrescenta o 🔁) acima das médias,
  /// quando alguém voltou (2 idas ou mais); `null` caso contrário.
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

  /// O usuário já avaliou o local (o CTA vira "Avaliar de novo").
  bool get hasOwnReview {
    final uid = _auth.currentUserId;
    return uid != null && reviews.any((r) => r.authorId == uid);
  }

  DateTime? _lockLastAt;
  Timer? _unlockTimer;
  int _lockSeq = 0;

  /// Hora da última avaliação do usuário aqui, enquanto ainda dentro do
  /// período mínimo (F03); `null` = pode avaliar.
  DateTime? get reviewBlockedSince =>
      isReviewBlocked(_lockLastAt, now()) ? _lockLastAt : null;

  /// "Pode avaliar de novo a partir de 11/11 às 20h" no lugar do CTA (F03).
  String? get reviewAgainLabel {
    final since = reviewBlockedSince;
    return since == null ? null : reviewAgainFromLabel(since);
  }

  void _setLock(DateTime? lastAt) {
    _lockLastAt = lastAt;
    _unlockTimer?.cancel();
    _unlockTimer = null;
    if (lastAt == null || !isReviewBlocked(lastAt, now())) return;
    // Na hora da liberação, o CTA volta sem precisar recarregar.
    _unlockTimer = Timer(
      reviewAllowedAt(lastAt).difference(now()),
      notifyListeners,
    );
  }

  /// Trava do F03 em paralelo com o resto (os dados não esperam por ela).
  /// Erro ou mais de [reviewLockTimeout]: sem trava (não mostra uma trava
  /// velha; o formulário confere de novo e as Rules decidem).
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

  /// "2 avaliações de amigos"; com a do próprio usuário, só "3 avaliações".
  /// Visitas (F15) do mesmo jeito: "2 avaliações de amigos · 3 visitas de
  /// amigos", ou "3 visitas" quando há visita do próprio usuário. Nunca
  /// vazio: sem idas, "0 avaliações de amigos".
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

  /// Card com as avaliações e visitas (cabeçalho, médias, autores, lista).
  FeedItem? get item {
    final p = _place;
    final r = _visibleReviews;
    if (p == null || r == null) return null;
    if (r.isEmpty && _visibleVisits.isEmpty) return null;
    return FeedItem(place: p, activities: [...r, ..._visibleVisits]);
  }

  DateTime? _visitLockLastAt;
  Timer? _visitUnlockTimer;
  int _visitLockSeq = 0;

  /// Visita registrada neste aparelho ([markVisited]): vale até a trava
  /// lida do servidor confirmar (uma leitura que falha não a apaga).
  DateTime? _localVisitAt;

  /// "Você registrou uma visita em 12/10 às 20h. De novo a partir de 13/10
  /// às 8h." quando a última visita do usuário aqui tem menos de 12 h (o
  /// "Voltei aqui" fica desabilitado); `null` = pode registrar.
  String? get visitBlockedLabel {
    final lastAt = _visitLockLastAt;
    return isVisitBlocked(lastAt, now()) ? visitBlockedMessage(lastAt!) : null;
  }

  /// A visita acabou de ser registrada (sheet ou tela de bloqueio do F03):
  /// o "Voltei aqui" trava já, sem esperar a releitura da trava.
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

  /// Trava de visita em paralelo, como a de avaliação: erro ou timeout =
  /// sem trava (o sheet confere de novo e as Rules decidem).
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

  /// Visitas do local; a falha não derruba o detalhe (`ok: false`: fica
  /// com as que já havia).
  Future<VisitsRead> _fetchVisits(List<String> authors) => loadVisitsOrEmpty(
    'detalhe',
    () async =>
        ActivityBatch(await _visits.fetchVisitsForPlace(placeId, authors)),
  );

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _notFound = false;

  /// O id não existe no catálogo (e não veio local pronto da navegação).
  bool get notFound => _notFound;

  String? _errorMessage;

  /// Falha sem algo para mostrar no lugar (o local ou as avaliações). Com o
  /// FeedItem pronto a falha é silenciosa (continua o que veio do feed).
  String? get errorMessage => _errorMessage;

  int _seq = 0;

  Future<void> load() async {
    final seq = ++_seq;
    _follow.clear();
    _errorMessage = null;
    _notFound = false;
    final uid = _auth.currentUserId;
    if (uid == null) {
      // Sem sessão: nenhuma trava (de outra conta) fica na tela.
      _lockSeq++;
      _setLock(null);
      _visitLockSeq++;
      _localVisitAt = null;
      _setVisitLock(null);
      // Sem sessão não há como ler: erro em vez de spinner eterno.
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
      // Cópia: o Set pode ser o do repositório.
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
        // Sem local no catálogo nem dado pronto: nada para mostrar.
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
    // O Future de load() inclui a trava; a tela não espera por ela.
    await lock;
    await visitLock;
  }

  static Review _asYou(Review r) => Review(
    id: r.id,
    authorId: r.authorId,
    authorName: youLabel,
    placeId: r.placeId,
    placeName: r.placeName,
    scores: r.scores,
    companion: r.companion,
    comment: r.comment,
    createdAt: r.createdAt,
    hasPhoto: r.hasPhoto,
  );

  static Visit _visitAsYou(Visit v) => Visit(
    id: v.id,
    authorId: v.authorId,
    authorName: youLabel,
    placeId: v.placeId,
    placeName: v.placeName,
    companion: v.companion,
    createdAt: v.createdAt,
  );

  @override
  void dispose() {
    _visitUnlockTimer?.cancel();
    _visitLockSeq++;
    _unlockTimer?.cancel();
    _lockSeq++;
    _follow.dispose();
    super.dispose();
  }
}
