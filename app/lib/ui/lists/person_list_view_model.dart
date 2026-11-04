import 'package:flutter/foundation.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/lists_repository.dart';
import '../../data/repositories/place_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../domain/models/place.dart';
import '../../domain/models/place_list.dart';
import '../../domain/models/user_profile.dart';
import '../core/safe_change_notifier.dart';
import 'lists_store.dart';

enum PersonListState { loading, ready, notFound, error, signedOut }

sealed class CopyNotice {
  const CopyNotice();
}

class CopyDone extends CopyNotice {
  const CopyDone(this.listId, {required this.copied, required this.total});

  final String listId;
  final int copied;
  final int total;

  String get message => copied < total
      ? '${PersonListViewModel.copiedText} ($copied de $total locais)'
      : PersonListViewModel.copiedText;
}

class CopyFailed extends CopyNotice {
  const CopyFailed();
}

class PersonListViewModel extends SafeChangeNotifier {
  PersonListViewModel({
    required this.ownerUid,
    required this.listId,
    required AuthRepository authRepository,
    required UserRepository userRepository,
    required ListsRepository listsRepository,
    required PlaceRepository placeRepository,
    ListsStore? listsStore,
    Object? initial,
  }) : _auth = authRepository,
       _users = userRepository,
       _listsRepo = listsRepository,
       _places = placeRepository,
       _store = listsStore,
       _list = initial is PlaceList && initial.id == listId ? initial : null {
    _store?.addListener(notifyListeners);
  }

  static const loadErrorText =
      'Não foi possível carregar a lista. Verifique sua conexão.';
  static const notFoundText = 'Esta lista não está disponível';
  static const limitText =
      'Você já tem ${PlaceList.maxLists} listas. Exclua uma para copiar.';
  static const copyFailedText = 'Não foi possível copiar a lista';
  static const copiedText = 'Lista copiada';
  static const listsLoadingText = 'Carregando suas listas…';
  static const listsFailedText = 'Não foi possível carregar suas listas';

  final String ownerUid;
  final String listId;
  final AuthRepository _auth;
  final UserRepository _users;
  final ListsRepository _listsRepo;
  final PlaceRepository _places;
  final ListsStore? _store;

  PersonListState _state = PersonListState.loading;
  PersonListState get state => _state;

  PlaceList? _list;

  PlaceList? get list => _list;

  UserProfile? _author;

  String get authorName => _author?.displayName ?? '';

  List<Place> _placesList = const [];

  List<Place> get places => _placesList;

  bool _copying = false;
  bool get isCopying => _copying;

  CopyNotice? _notice;

  CopyNotice? takeNotice() {
    final n = _notice;
    _notice = null;
    return n;
  }

  bool get limitReached {
    final store = _store;
    return store != null &&
        store.isReady &&
        store.lists.length >= PlaceList.maxLists;
  }

  bool get listsLoading {
    final store = _store;
    return store != null && (store.isIdle || store.isLoading);
  }

  bool get listsFailed => _store?.hasError ?? false;

  Future<void> retryLists() => _store?.reload() ?? Future.value();

  bool get canCopy {
    final store = _store;
    return store != null &&
        _state == PersonListState.ready &&
        _author != null &&
        _list != null &&
        !_copying &&
        _auth.currentUserId != ownerUid &&
        store.canCreate;
  }

  int _seq = 0;

  Future<void> load() async {
    final seq = ++_seq;
    if (_auth.currentUserId == null) {
      _state = PersonListState.signedOut;
      notifyListeners();
      return;
    }
    _state = PersonListState.loading;
    notifyListeners();
    try {
      final results = await Future.wait<Object?>([
        _users.getProfile(ownerUid),
        _listsRepo.listVisibleLists(ownerUid),
      ]);
      if (seq != _seq) return;
      final author = results[0] as UserProfile?;
      final visible = results[1]! as List<PlaceList>;
      final list = visible.where((l) => l.id == listId).firstOrNull;
      if (author == null || list == null) {
        _state = PersonListState.notFound;
        notifyListeners();
        return;
      }
      final found = await _places.getPlaces(list.placeIds);
      if (seq != _seq) return;
      _author = author;
      _list = list;
      _placesList = [
        for (final id in list.placeIds)
          if (found[id] case final Place p) p,
      ];
      _state = PersonListState.ready;
    } on ListAccessDeniedException {
      if (seq != _seq) return;
      _state = PersonListState.notFound;
    } on Object catch (e) {
      if (seq != _seq) return;
      debugPrint('Lista indisponível: $e');
      _state = PersonListState.error;
    }
    notifyListeners();
  }

  Future<void> copy() async {
    final store = _store;
    final list = _list;
    final me = _auth.currentUserId;
    if (!canCopy ||
        store == null ||
        list == null ||
        _author == null ||
        me == null) {
      return;
    }
    _copying = true;
    notifyListeners();
    try {
      final author = await _users
          .getProfile(ownerUid)
          .timeout(const Duration(seconds: 10));
      if (isDisposed || _auth.currentUserId != me) return;
      if (author == null) throw StateError('Perfil indisponível');
      _author = author;
      final total = {...list.placeIds}.length;
      final shown = list.copyWith(
        placeIds: [for (final p in _placesList) p.id],
      );
      final creation = store.copyFrom(shown, author);
      if (creation == null) {
        _notice = const CopyFailed();
        return;
      }
      final ok = await creation.done;
      if (isDisposed || _auth.currentUserId != me) return;
      _notice = ok
          ? CopyDone(
              creation.id,
              copied: store.listById(creation.id)?.placeIds.length ?? 0,
              total: total,
            )
          : const CopyFailed();
    } on Object {
      if (!isDisposed && _auth.currentUserId == me) {
        _notice = const CopyFailed();
      }
    } finally {
      _copying = false;
      notifyListeners();
    }
  }

  void focusCopied(String newListId) => _store?.focusList(newListId);

  @override
  void dispose() {
    _store?.removeListener(notifyListeners);
    super.dispose();
  }
}
