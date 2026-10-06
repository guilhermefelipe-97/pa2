import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../domain/models/user_profile.dart';
import '../core/follow_events.dart';
import '../core/safe_change_notifier.dart';

enum PeopleInitState { loading, ready, error }

/// Tela Pessoas: busca por nome e seguir/deixar de seguir.
class PeopleViewModel extends SafeChangeNotifier {
  PeopleViewModel({
    required AuthRepository authRepository,
    required UserRepository userRepository,
    required FollowEvents followEvents,
  }) : _auth = authRepository,
       _users = userRepository,
       _follow = FollowStaleness(followEvents);

  final AuthRepository _auth;
  final UserRepository _users;
  final FollowStaleness _follow;

  /// Alguém foi seguido/deixado de seguir em outra tela (ex.: perfil).
  bool get isStale => _follow.isStale;

  /// Ao voltar a ficar visível: relê quem é seguido se mudou fora daqui.
  Future<void> reloadIfStale() => _follow.isStale ? init() : Future.value();

  static const String initErrorMessage =
      'Não foi possível carregar quem você segue.';

  List<UserProfile> _results = const [];
  List<UserProfile> get results => _results;

  final Set<String> _following = {};
  bool isFollowing(String uid) => _following.contains(uid);

  /// Mudanças locais (seguir = true / deixar = false) feitas depois que a
  /// carga de `following` começou; aplicadas por cima do que veio do servidor.
  final Map<String, bool> _localChanges = {};

  final Set<String> _busy = {};
  bool isBusy(String uid) => _busy.contains(uid);

  PeopleInitState _initState = PeopleInitState.loading;
  PeopleInitState get initState => _initState;
  bool get isReady => _initState == PeopleInitState.ready;

  /// Botão Seguir só habilita depois que sabemos quem já é seguido.
  bool canToggle(String uid) => isReady && !_busy.contains(uid);

  bool _isSearching = false;
  bool get isSearching => _isSearching;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  String _lastQuery = '';
  String get lastQuery => _lastQuery;

  int _searchSeq = 0;
  int _initSeq = 0;

  /// Carrega quem o usuário segue. Também serve de "Tentar de novo".
  Future<void> init() async {
    final uid = _auth.currentUserId;
    if (uid == null) return;
    final seq = ++_initSeq;
    _follow.clear();
    _initState = PeopleInitState.loading;
    _localChanges.clear();
    notifyListeners();
    try {
      final fetched = await _users.getFollowing(uid);
      if (seq != _initSeq) return;
      _reconcile(fetched);
      _initState = PeopleInitState.ready;
    } on Object {
      if (seq != _initSeq) return;
      _initState = PeopleInitState.error;
    }
    notifyListeners();
  }

  void _reconcile(Set<String> fetched) {
    _following
      ..clear()
      ..addAll(fetched);
    _localChanges.forEach((target, followed) {
      if (followed) {
        _following.add(target);
      } else {
        _following.remove(target);
      }
    });
    _localChanges.clear();
  }

  Future<void> search(String query) async {
    final uid = _auth.currentUserId;
    _lastQuery = query.trim();
    final seq = ++_searchSeq;
    if (_lastQuery.isEmpty) {
      _results = const [];
      _isSearching = false;
      notifyListeners();
      return;
    }
    _isSearching = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final found = await _users.searchByName(_lastQuery);
      if (seq != _searchSeq) return; // resposta de uma busca antiga
      _results = found.where((p) => p.uid != uid).toList();
    } on Object {
      if (seq != _searchSeq) return;
      _errorMessage = 'Não foi possível buscar. Tente de novo.';
    } finally {
      if (seq == _searchSeq) {
        _isSearching = false;
        notifyListeners();
      }
    }
  }

  Future<void> toggleFollow(String targetUid) async {
    final uid = _auth.currentUserId;
    if (uid == null || uid == targetUid || !canToggle(targetUid)) return;
    final wasFollowing = _following.contains(targetUid);
    _busy.add(targetUid);
    _errorMessage = null;
    notifyListeners();
    try {
      if (wasFollowing) {
        await _users.unfollow(uid: uid, targetUid: targetUid);
        _following.remove(targetUid);
      } else {
        await _users.follow(uid: uid, targetUid: targetUid);
        _following.add(targetUid);
      }
      if (!isReady) _localChanges[targetUid] = !wasFollowing;
      // Feed, detalhe e perfis abertos ficam desatualizados.
      _follow.announce();
    } on Object {
      _errorMessage = wasFollowing
          ? 'Não foi possível deixar de seguir.'
          : 'Não foi possível seguir.';
      // O estado real pode ter mudado (ex.: escrita aplicada e resposta
      // perdida): busca de novo e reconcilia.
      try {
        _reconcile(await _users.getFollowing(uid));
      } on Object {
        // mantém o estado local; o erro já está na tela
      }
    } finally {
      _busy.remove(targetUid);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _follow.dispose();
    super.dispose();
  }
}
