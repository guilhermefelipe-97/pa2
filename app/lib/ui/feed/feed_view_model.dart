import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/place_repository.dart';
import '../../data/repositories/review_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../domain/feed.dart';
import '../../domain/models/place.dart';
import '../core/follow_events.dart';
import '../core/safe_change_notifier.dart';

/// Feed "Amigos foram aqui" (F05).
class FeedViewModel extends SafeChangeNotifier {
  FeedViewModel({
    required AuthRepository authRepository,
    required UserRepository userRepository,
    required ReviewRepository reviewRepository,
    required PlaceRepository placeRepository,
    required FollowEvents followEvents,
    DateTime Function()? clock,
  }) : _auth = authRepository,
       _users = userRepository,
       _reviews = reviewRepository,
       _places = placeRepository,
       _follow = FollowStaleness(followEvents),
       _clock = clock ?? DateTime.now;

  final AuthRepository _auth;
  final UserRepository _users;
  final ReviewRepository _reviews;
  final PlaceRepository _places;
  final FollowStaleness _follow;
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

  Set<String> _following = const {};

  /// O usuário segue [uid] (segundo a última carga): selo "você segue" no
  /// card, sem leituras extras.
  bool isFollowing(String uid) => _following.contains(uid);

  /// Usuário da última carga bem-sucedida (troca de conta limpa o estado).
  String? _loadedUid;

  /// Alguém foi seguido/deixado de seguir em outra tela desde o início da
  /// última carga.
  bool get isStale => _follow.isStale;

  /// Recarrega só se ficou desatualizado. Chamado quando o feed volta a ficar
  /// visível (retorno de rota ou ativação da aba). Uma carga que começou
  /// depois da mudança já basta: não agenda outra.
  Future<void> reloadIfStale() => _follow.isStale ? load() : Future.value();

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
    if (uid != _loadedUid) {
      // Outra conta (ou saiu): nada do usuário anterior fica visível.
      _following = const {};
      _items = const [];
      _followsNobody = false;
      _loadedOnce = false;
      _loadedUid = null;
    }
    if (uid == null) return;
    // Esta carga lê o estado atual: mudanças anteriores já entram nela.
    _follow.clear();
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      // Cópia: o Set pode ser o do repositório.
      final following = {...await _users.getFollowing(uid)}..remove(uid);
      var items = const <FeedItem>[];
      if (following.isNotEmpty) {
        final reviews = await _reviews.fetchReviewsByAuthors(
          following.toList(),
        );
        // Só os locais que aparecem no feed; _loadPlaces nunca lança.
        final places = await _loadPlaces({for (final r in reviews) r.placeId});
        items = groupReviewsIntoFeed(reviews, places: places);
      }
      // Só depois de tudo dar certo: uma falha no meio mantém o estado
      // anterior inteiro (relação, cards e CTA coerentes entre si).
      _following = following;
      _followsNobody = following.isEmpty;
      _items = items;
      _loadedOnce = true;
      _loadedUid = uid;
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
  /// carga. O repositório guarda em cache o que já leu (1 leitura por local).
  Future<Map<String, Place>> _loadPlaces(Set<String> ids) async {
    if (ids.isEmpty) return const {};
    try {
      return await _places.getPlaces(ids);
    } on Object {
      return const {};
    }
  }

  Future<void> signOut() => _auth.signOut();

  @override
  void dispose() {
    _follow.dispose();
    super.dispose();
  }
}
