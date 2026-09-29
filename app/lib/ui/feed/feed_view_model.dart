import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/review_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../domain/feed.dart';
import '../core/safe_change_notifier.dart';

/// Feed "Amigos foram aqui" (F05).
class FeedViewModel extends SafeChangeNotifier {
  FeedViewModel({
    required AuthRepository authRepository,
    required UserRepository userRepository,
    required ReviewRepository reviewRepository,
  })  : _auth = authRepository,
        _users = userRepository,
        _reviews = reviewRepository;

  final AuthRepository _auth;
  final UserRepository _users;
  final ReviewRepository _reviews;

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
        final reviews = await _reviews.fetchReviewsByAuthors(following.toList());
        _items = groupReviewsIntoFeed(reviews);
      }
      _loadedOnce = true;
    } on Object {
      _errorMessage = 'Não foi possível carregar o feed. Verifique sua conexão.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() => _auth.signOut();
}
