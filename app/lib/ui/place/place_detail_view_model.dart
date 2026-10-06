import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/place_repository.dart';
import '../../data/repositories/review_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../domain/feed.dart';
import '../../domain/models/place.dart';
import '../../domain/models/review.dart';
import '../core/follow_events.dart';
import '../core/safe_change_notifier.dart';

/// Detalhe do local, autônomo por `placeId` (F11): carrega o local e as
/// avaliações de quem o usuário segue ali (e as dele, como "Você"). Quando a
/// navegação traz dados prontos (`FeedItem` do feed ou `Place` da aba
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
    DateTime Function()? clock,
  }) : _auth = authRepository,
       _users = userRepository,
       _places = placeRepository,
       _reviews = reviewRepository,
       _follow = FollowStaleness(followEvents),
       _clock = clock ?? DateTime.now {
    switch (initial) {
      case final FeedItem item when item.placeId == placeId:
        _place = item.place;
        _visibleReviews = item.reviews;
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

  /// A avaliação é do usuário logado.
  bool isOwn(Review r) {
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

  /// O usuário já avaliou o local (o CTA vira "Avaliar de novo").
  bool get hasOwnReview {
    final uid = _auth.currentUserId;
    return uid != null && reviews.any((r) => r.authorId == uid);
  }

  /// "2 avaliações de amigos"; com a do próprio usuário, só "3 avaliações".
  String get reviewCountLabel {
    final n = reviews.length;
    if (hasOwnReview) return n == 1 ? '1 avaliação' : '$n avaliações';
    return n == 1 ? '1 avaliação de amigo' : '$n avaliações de amigos';
  }

  /// Card com as avaliações (para cabeçalho, médias e autores).
  FeedItem? get item {
    final p = _place;
    final r = _visibleReviews;
    if (p == null || r == null || r.isEmpty) return null;
    return FeedItem(place: p, reviews: r);
  }

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
      // Sem sessão não há como ler: erro em vez de spinner eterno.
      _isLoading = false;
      if (_place == null || _visibleReviews == null) _errorMessage = errorText;
      notifyListeners();
      return;
    }
    _isLoading = true;
    notifyListeners();
    try {
      final results = await Future.wait([
        _places.getPlaces([placeId]),
        _users.getFollowing(uid),
      ]);
      if (seq != _seq) return;
      final found = (results[0] as Map<String, Place>)[placeId];
      // Cópia: o Set pode ser o do repositório.
      final authors = {...results[1] as Set<String>, uid};
      final fetched = await _reviews.fetchReviewsForPlace(
        placeId,
        authors.toList(),
      );
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
    } on Object {
      if (seq != _seq) return;
      if (_place == null || _visibleReviews == null) _errorMessage = errorText;
    } finally {
      if (seq == _seq) {
        _isLoading = false;
        notifyListeners();
      }
    }
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

  @override
  void dispose() {
    _follow.dispose();
    super.dispose();
  }
}
