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

/// Resultado de "Copiar lista", mostrado uma vez pela tela.
sealed class CopyNotice {
  const CopyNotice();
}

/// Copiou: a nova lista é [listId] ("Ver" abre o chip no Quero ir), com
/// [copied] dos [total] locais da lista original.
class CopyDone extends CopyNotice {
  const CopyDone(this.listId, {required this.copied, required this.total});

  final String listId;
  final int copied;
  final int total;

  /// "Lista copiada" ou, se faltaram locais, "Lista copiada (2 de 3
  /// locais)".
  String get message => copied < total
      ? '${PersonListViewModel.copiedText} ($copied de $total locais)'
      : PersonListViewModel.copiedText;
}

/// Falhou: os salvamentos feitos pela cópia foram desfeitos.
class CopyFailed extends CopyNotice {
  const CopyFailed();
}

/// Lista visível de uma pessoa que o usuário segue (F13):
/// `/pessoa/:uid/lista/:listId`, com os locais e "Copiar lista". Só abre
/// para quem segue a dona e com a lista visível (as Rules negam o resto).
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

  /// A lista (do `extra` do perfil até a leitura confirmar).
  PlaceList? get list => _list;

  UserProfile? _author;

  /// Nome da autora ("Ana").
  String get authorName => _author?.displayName ?? '';

  List<Place> _placesList = const [];

  /// Locais da lista que existem no catálogo, na ordem da lista.
  List<Place> get places => _placesList;

  bool _copying = false;
  bool get isCopying => _copying;

  CopyNotice? _notice;

  /// Aviso pendente da cópia (uma vez só).
  CopyNotice? takeNotice() {
    final n = _notice;
    _notice = null;
    return n;
  }

  /// O usuário já tem o máximo de listas: botão desabilitado com aviso.
  bool get limitReached {
    final store = _store;
    return store != null &&
        store.isReady &&
        store.lists.length >= PlaceList.maxLists;
  }

  /// Suas listas ainda carregando: "Copiar lista" espera por elas.
  bool get listsLoading {
    final store = _store;
    return store != null && (store.isIdle || store.isLoading);
  }

  /// Suas listas não carregaram: "Copiar lista" desabilitado com "Tentar de
  /// novo".
  bool get listsFailed => _store?.hasError ?? false;

  /// "Tentar de novo" das suas listas.
  Future<void> retryLists() => _store?.reload() ?? Future.value();

  /// "Copiar lista" habilitado.
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
      // Não segue (ou deixou de seguir) a dona: a lista não está disponível
      // — tentar de novo não adianta.
      if (seq != _seq) return;
      _state = PersonListState.notFound;
    } on Object catch (e) {
      if (seq != _seq) return;
      debugPrint('Lista indisponível: $e');
      _state = PersonListState.error;
    }
    notifyListeners();
  }

  /// "Copiar lista" (snapshot com crédito à autora): só os locais que a
  /// tela mostrou (os que existem no catálogo).
  Future<void> copy() async {
    final store = _store;
    final list = _list;
    final author = _author;
    if (!canCopy || store == null || list == null || author == null) return;
    final total = {...list.placeIds}.length;
    final shown = list.copyWith(placeIds: [for (final p in _placesList) p.id]);
    final creation = store.copyFrom(shown, author);
    if (creation == null) {
      _notice = const CopyFailed();
      notifyListeners();
      return;
    }
    _copying = true;
    notifyListeners();
    final ok = await creation.done;
    _copying = false;
    _notice = ok
        ? CopyDone(
            creation.id,
            copied: store.listById(creation.id)?.placeIds.length ?? 0,
            total: total,
          )
        : const CopyFailed();
    notifyListeners();
  }

  /// "Ver" da SnackBar: a aba "Quero ir" abre com a lista copiada.
  void focusCopied(String newListId) => _store?.focusList(newListId);

  @override
  void dispose() {
    _store?.removeListener(notifyListeners);
    super.dispose();
  }
}
