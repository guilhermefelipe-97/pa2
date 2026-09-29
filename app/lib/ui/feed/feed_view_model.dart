import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/place_repository.dart';
import '../../data/repositories/review_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../domain/feed.dart';
import '../../domain/models/place.dart';
import '../core/safe_change_notifier.dart';

/// Feed "Amigos foram aqui" (F05).
class FeedViewModel extends SafeChangeNotifier {
  FeedViewModel({
    required AuthRepository authRepository,
    required UserRepository userRepository,
    required ReviewRepository reviewRepository,
    required PlaceRepository placeRepository,
    DateTime Function()? clock,
  }) : _auth = authRepository,
       _users = userRepository,
       _reviews = reviewRepository,
       _places = placeRepository,
       _clock = clock ?? DateTime.now;

  final AuthRepository _auth;
  final UserRepository _users;
  final ReviewRepository _reviews;
  final PlaceRepository _places;
  final DateTime Function() _clock;

  /// "Agora" para o tempo relativo dos cards (injetável nos testes).
  DateTime now() => _clock();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  List<FeedItem> _items = const [];
  List<FeedItem> get items => _items;

  bool _followsNobody = false;

  /// Não segue ninguém: mostrar o CTA "Encontrar pessoas".
  bool get followsNobody => _followsNobody;

  bool _loadedOnce = false;
  bool get loadedOnce => _loadedOnce;

  /// Locais por id (≈20, somente leitura): lidos uma vez e reaproveitados.
  Map<String, Place>? _placesById;

  bool _reloadPending = false;
  Future<void>? _inFlight;

  /// Recarrega o feed. Se já houver uma carga em andamento, agenda mais uma
  /// para logo depois (ex.: voltou da tela de avaliação durante a carga) e
  /// devolve um Future que só completa quando essa recarga terminar.
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
    if (uid == null) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final following = await _users.getFollowing(uid);
      following.remove(uid);
      if (following.isEmpty) {
        _followsNobody = true;
        _items = const [];
      } else {
        _followsNobody = false;
        // Em paralelo; _loadPlaces nunca lança.
        final placesFuture = _loadPlaces();
        final reviews = await _reviews.fetchReviewsByAuthors(
          following.toList(),
        );
        final places = await placesFuture;
        _items = groupReviewsIntoFeed(reviews, places: places);
      }
      _loadedOnce = true;
    } on Object {
      _errorMessage =
          'Não foi possível carregar o feed. Verifique sua conexão.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Falha ao ler os locais não derruba o feed: os cards usam o fallback
  /// (nome da avaliação, sem foto) e a leitura é tentada de novo na próxima
  /// carga.
  Future<Map<String, Place>> _loadPlaces() async {
    final cached = _placesById;
    if (cached != null) return cached;
    try {
      final list = await _places.listPlaces();
      return _placesById = {for (final p in list) p.id: p};
    } on Object {
      return const {};
    }
  }

  Future<void> signOut() => _auth.signOut();
}
