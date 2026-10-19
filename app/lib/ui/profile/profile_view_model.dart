import 'package:flutter/foundation.dart';

import '../../data/activity_batch.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/lists_repository.dart';
import '../../data/repositories/review_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/repositories/visit_repository.dart';
import '../../domain/models/place_activity.dart';
import '../../domain/models/place_list.dart';
import '../../domain/models/user_profile.dart';
import '../core/follow_events.dart';
import '../core/load_visits.dart';
import '../core/safe_change_notifier.dart';

enum ProfileState { loading, ready, notFound, error, signedOut }

/// Aviso de uma ação de seguir, mostrado uma vez pela tela.
enum ProfileNotice {
  /// Falhou; o botão já voltou ao estado anterior.
  followFailed,

  /// Deixou de seguir com sucesso (SnackBar com "Desfazer").
  unfollowed,
}

/// Perfil simples de uma pessoa (F06): nome, Seguir/Deixar de seguir e as
/// avaliações e visitas ("Voltei aqui", F15) dela, mais recentes primeiro.
/// Sem foto, sem contagem de seguidores, sem edição. Para quem segue a
/// pessoa, as listas que ela deixou visíveis (F13).
class ProfileViewModel extends SafeChangeNotifier {
  ProfileViewModel({
    required this.uid,
    required AuthRepository authRepository,
    required UserRepository userRepository,
    required ReviewRepository reviewRepository,
    required FollowEvents followEvents,
    required VisitRepository visitRepository,
    ListsRepository? listsRepository,
    DateTime Function()? clock,
  }) : _auth = authRepository,
       _users = userRepository,
       _reviews = reviewRepository,
       _visits = visitRepository,
       _lists = listsRepository,
       _follow = FollowStaleness(followEvents),
       _clock = clock ?? DateTime.now;

  static const loadErrorText =
      'Não foi possível carregar o perfil. Verifique sua conexão.';
  static const followErrorText = 'Não foi possível atualizar';
  static const youLabel = 'Você';
  static const unnamedLabel = 'Usuário';

  /// O perfil mostra só as avaliações mais recentes...
  static const int maxReviews = 50;

  /// ...e só as visitas ("Voltei aqui", F15) mais recentes, com limite
  /// próprio (visitas frequentes não empurram as avaliações para fora).
  static const int maxVisits = 50;

  final String uid;
  final AuthRepository _auth;
  final UserRepository _users;
  final ReviewRepository _reviews;
  final VisitRepository _visits;
  final ListsRepository? _lists;
  final FollowStaleness _follow;
  final DateTime Function() _clock;

  DateTime now() => _clock();

  /// O perfil é do próprio usuário: título "Você" e sem botão Seguir.
  bool get isSelf => _auth.currentUserId == uid;

  ProfileState _state = ProfileState.loading;
  ProfileState get state => _state;

  UserProfile? _profile;

  /// Nome no título ("Você" no próprio perfil; "Usuário" sem nome).
  String get title {
    if (isSelf) return youLabel;
    final name = _profile?.displayName.trim() ?? '';
    return name.isEmpty ? unnamedLabel : name;
  }

  List<Review> _reviewList = const [];

  /// Até [maxReviews] avaliações da pessoa, mais recentes primeiro.
  List<Review> get reviews => _reviewList;

  List<PlaceActivity> _activities = const [];

  /// Até [maxReviews] avaliações e até [maxVisits] visitas da pessoa,
  /// juntas, mais recentes primeiro.
  List<PlaceActivity> get activities => _activities;

  /// Sem avaliações nem visitas: "Ana ainda não avaliou nem registrou
  /// visita em nenhum lugar".
  String get emptyText => isSelf
      ? 'Você ainda não avaliou nem registrou visita em nenhum lugar'
      : '$title ainda não avaliou nem registrou visita em nenhum lugar';

  bool _following = false;
  bool get isFollowing => _following;

  List<PlaceList> _visibleLists = const [];

  /// Listas visíveis da pessoa (F13): só para quem a segue; vazio (seção
  /// oculta) sem seguir, no próprio perfil ou se a leitura falhou.
  List<PlaceList> get lists => _visibleLists;

  int _listsSeq = 0;

  /// Lê as listas visíveis (sem bloquear o perfil). Falha = seção oculta.
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

  /// Devolve o aviso pendente (uma vez só).
  ProfileNotice? takeNotice() {
    final n = _notice;
    _notice = null;
    return n;
  }

  /// Alguém foi seguido/deixado de seguir em outra tela (ex.: este mesmo
  /// perfil aberto de novo mais acima na pilha).
  bool get isStale => _follow.isStale;

  /// Ao voltar a ficar visível.
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
        // Falha só das visitas: perfil com as avaliações.
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
        // As listas chegam depois, sem atrasar o perfil.
        _loadLists();
      }
    } on Object {
      if (seq != _seq) return;
      _state = ProfileState.error;
    }
    notifyListeners();
  }

  /// Seguir/Deixar de seguir, otimista: o botão muda já; a falha reverte e
  /// avisa ([ProfileNotice.followFailed]); deixar de seguir com sucesso
  /// avisa [ProfileNotice.unfollowed] (para o "Desfazer").
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
      // Passou a seguir: as listas visíveis aparecem; deixou: somem.
      _loadLists();
    } on Object {
      _following = wasFollowing;
      _notice = ProfileNotice.followFailed;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// "Desfazer" do deixar de seguir.
  Future<void> undoUnfollow() async {
    if (!_following) await toggleFollow();
  }

  @override
  void dispose() {
    _follow.dispose();
    super.dispose();
  }
}
