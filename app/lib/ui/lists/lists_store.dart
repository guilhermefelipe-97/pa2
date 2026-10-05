import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/lists_repository.dart';
import '../../domain/models/place_list.dart';
import '../saved/saved_places_store.dart';

enum ListsStatus { idle, loading, ready, error }

/// Resultado do "Desfazer" de uma remoção do "Quero ir".
enum RestoreResult {
  ok,

  /// Não voltou ao "Quero ir" (nem às listas).
  savedFailed,

  /// Voltou ao "Quero ir", mas não a todas as listas.
  someListsFailed,
}

/// Lista recém-criada (otimista) e o Future da escrita (`false` = falhou e
/// a lista sumiu).
typedef ListCreation = ({String id, Future<bool> done});

/// Fonte única das listas nomeadas (F12) do usuário logado, coerente com o
/// [SavedPlacesStore].
///
/// A invariante "lista ⊂ Quero ir" é garantida em três camadas:
/// - pôr um local numa lista salva o local antes (a escrita da lista só sai
///   depois do salvamento confirmado);
/// - remover do "Quero ir" tira o local de todas as listas no mesmo batch
///   (este store assume o `remover` do [SavedPlacesStore]);
/// - **reconciliação**: com salvos e listas prontos (e a cada recarga), todo
///   membro de lista que não está salvo, nem com escrita pendente, sai com
///   `arrayRemove` em segundo plano. Isso cobre as corridas (escritas que
///   terminam depois de uma remoção, remoção sem listas carregadas, outro
///   aparelho).
///
/// Contagens e filtros só consideram locais salvos.
///
/// Tudo é otimista: o estado confirmado ([_server]) recebe sobreposições
/// (criação, renomeação, exclusão, membros) que somem quando a escrita
/// termina — com sucesso viram estado confirmado, com falha são descartadas
/// (reversão). Escritas da mesma lista são serializadas, na ordem dos toques.
class ListsStore extends ChangeNotifier {
  ListsStore({
    required AuthRepository authRepository,
    required ListsRepository listsRepository,
    required SavedPlacesStore savedStore,
    DateTime Function()? clock,
    Duration waitTimeout = const Duration(seconds: 10),
  }) : _auth = authRepository,
       _repo = listsRepository,
       _saved = savedStore,
       _clock = clock ?? DateTime.now,
       _waitTimeout = waitTimeout {
    _saved.remover = _removeEverywhere;
    _saved.addListener(_onSavedChanged);
    _auth.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  final AuthRepository _auth;
  final ListsRepository _repo;
  final SavedPlacesStore _saved;
  final DateTime Function() _clock;

  /// Quanto recarga e remoção esperam escritas em voo / a leitura das
  /// listas (offline elas não terminam e nada pode travar).
  final Duration _waitTimeout;

  String? _uid;
  int _generation = 0;

  ListsStatus _status = ListsStatus.idle;
  ListsStatus get status => _status;
  bool get isIdle => _status == ListsStatus.idle;
  bool get isReady => _status == ListsStatus.ready;
  bool get isLoading => _status == ListsStatus.loading;
  bool get hasError => _status == ListsStatus.error;

  /// Último estado confirmado pelo servidor.
  final Map<String, PlaceList> _server = {};

  /// Criadas no app, ainda sem confirmação.
  final Map<String, PlaceList> _creating = {};

  /// Renomeação pendente por lista.
  final Map<String, ({String name, String? emoji, int token})> _meta = {};

  /// Exclusão pendente.
  final Set<String> _deleting = {};

  /// Membro desejado (pendente) por lista → local.
  final Map<String, Map<String, ({bool member, int token})>> _members = {};

  /// Última escrita enfileirada por lista (serialização).
  final Map<String, Future<bool>> _chains = {};

  /// Local salvo por uma marcação/criação de lista ainda não confirmada →
  /// token. Se todas as que dependem dele falharem (e ele não estiver em
  /// lista nenhuma), o salvamento é desfeito.
  final Map<String, int> _autoSaved = {};

  int _seq = 0;
  Future<void>? _loading;
  bool _reconcileScheduled = false;
  bool _disposed = false;

  // ---------------------------------------------------------------- leitura

  /// Listas exibidas (com as mudanças otimistas), da mais antiga para a mais
  /// nova.
  List<PlaceList> get lists {
    final out = <PlaceList>[
      for (final l in _server.values)
        if (!_deleting.contains(l.id)) _display(l),
      for (final l in _creating.values)
        if (!_server.containsKey(l.id) && !_deleting.contains(l.id))
          _display(l),
    ];
    out.sort((a, b) {
      final byDate = a.createdAt.compareTo(b.createdAt);
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });
    return out;
  }

  PlaceList? listById(String listId) {
    if (_deleting.contains(listId)) return null;
    final base = _server[listId] ?? _creating[listId];
    return base == null ? null : _display(base);
  }

  PlaceList _display(PlaceList base) {
    final meta = _meta[base.id];
    final members = _members[base.id];
    if (meta == null && (members == null || members.isEmpty)) return base;
    var ids = base.placeIds;
    if (members != null && members.isNotEmpty) {
      ids = [...base.placeIds];
      members.forEach((placeId, o) {
        if (o.member) {
          if (!ids.contains(placeId)) ids.add(placeId);
        } else {
          ids.remove(placeId);
        }
      });
    }
    return base.copyWith(
      name: meta?.name,
      emoji: meta == null ? null : () => meta.emoji,
      placeIds: ids,
    );
  }

  /// Locais da lista que estão no "Quero ir".
  Set<String> savedPlaceIdsOf(PlaceList list) => {
    for (final id in list.placeIds)
      if (_saved.isSaved(id)) id,
  };

  /// Quantos locais salvos a lista tem.
  int countOf(PlaceList list) => savedPlaceIdsOf(list).length;

  /// Listas (exibidas) que contêm [placeId].
  List<PlaceList> listsContaining(String placeId) => [
    for (final l in lists)
      if (l.contains(placeId)) l,
  ];

  bool get canCreate => isReady && lists.length < PlaceList.maxLists;

  /// Já existe lista com esse nome (sem diferenciar caixa nem acento)?
  bool isNameTaken(String rawName, {String? exceptId}) {
    final key = PlaceList.nameKey(rawName);
    return lists.any(
      (l) => l.id != exceptId && PlaceList.nameKey(l.name) == key,
    );
  }

  // ---------------------------------------------------------------- carga

  void _onSavedChanged() {
    // Local que saiu do "Quero ir": marcações pendentes dele são canceladas
    // (não salvam de novo o que a pessoa acabou de remover) e ele deixa de
    // contar como "salvo por uma lista".
    _members.removeWhere((_, m) {
      m.removeWhere((placeId, o) => o.member && !_saved.isSaved(placeId));
      return m.isEmpty;
    });
    _autoSaved.removeWhere((placeId, _) => !_saved.isSaved(placeId));
    // Depois do toque em curso (o worker da escrita ainda vai se registrar).
    _scheduleReconcile();
    _notify();
  }

  void _onAuthChanged() {
    final uid = _auth.currentUserId;
    if (uid == _uid) return;
    _uid = uid;
    _generation++;
    _server.clear();
    _creating.clear();
    _meta.clear();
    _deleting.clear();
    _members.clear();
    _chains.clear();
    _autoSaved.clear();
    _loading = null;
    _status = ListsStatus.idle;
    if (uid != null) {
      reload();
    } else {
      _notify();
    }
  }

  /// Carrega as listas (também é o "Tentar de novo"). Chamadas simultâneas
  /// compartilham a mesma leitura.
  Future<void> reload() {
    final uid = _uid;
    if (uid == null) return Future.value();
    return _loading ??= _load(uid, _generation);
  }

  Future<void> _load(String uid, int generation) async {
    if (!isReady) {
      _status = ListsStatus.loading;
      _notify();
    }
    try {
      // Escritas em voo primeiro (a leitura já reflete o que elas fizeram),
      // com limite: offline elas não terminam.
      if (_chains.isNotEmpty) {
        await Future.wait(
          _chains.values.toList(),
        ).timeout(_waitTimeout, onTimeout: () => const []);
      }
      if (generation != _generation) return;
      await _fetch(uid, generation);
    } on Object {
      if (generation != _generation) return;
      if (!isReady) _status = ListsStatus.error;
    } finally {
      if (generation == _generation) {
        _loading = null;
        _notify();
      }
    }
  }

  /// Lê as listas do servidor (com limite de tempo) e reconcilia.
  Future<void> _fetch(String uid, int generation) async {
    final loaded = await _repo.listLists(uid).timeout(_waitTimeout);
    if (generation != _generation) return;
    _server
      ..clear()
      ..addAll({for (final l in loaded) l.id: l});
    _status = ListsStatus.ready;
    // Já no carregamento: antes de a pessoa conseguir salvar de novo um
    // local que saiu do "Quero ir", ele já não aparece na lista.
    _reconcile();
  }

  void _scheduleReconcile() {
    if (_reconcileScheduled) return;
    _reconcileScheduled = true;
    scheduleMicrotask(() {
      _reconcileScheduled = false;
      if (!_disposed) _reconcile();
    });
  }

  /// Tira das listas (em segundo plano) quem não está no "Quero ir" nem tem
  /// escrita de salvo pendente.
  void _reconcile() {
    if (!isReady || !_saved.isReady) return;
    for (final list in [..._server.values]) {
      if (_deleting.contains(list.id)) continue;
      for (final placeId in list.placeIds) {
        if (_saved.isSaved(placeId) || _saved.hasPendingWrite(placeId)) {
          continue;
        }
        _dropGhost(list.id, placeId);
      }
    }
  }

  /// `arrayRemove` de um membro que não está no "Quero ir" (se ainda não há
  /// escrita pendente desse membro).
  void _dropGhost(String listId, String placeId) {
    if (_members[listId]?.containsKey(placeId) ?? false) return;
    if (listById(listId) == null) return;
    unawaited(_setMembership(listId, placeId, false));
  }

  // ---------------------------------------------------------------- escrita

  /// Enfileira [op] depois das escritas anteriores da mesma lista.
  Future<bool> _enqueue(String listId, Future<bool> Function() op) {
    final prev = _chains[listId];
    final next = prev == null ? op() : prev.then((_) => op());
    _chains[listId] = next;
    next.whenComplete(() {
      if (identical(_chains[listId], next)) _chains.remove(listId);
    });
    return next;
  }

  /// Salva [placeId] já (otimista) por conta de uma lista; devolve o Future
  /// do salvamento e o token de "salvo por lista" (null se já estava salvo).
  ({Future<bool> done, int? token}) _saveFor(String placeId) {
    int? token;
    if (!_saved.isSaved(placeId)) {
      token = ++_seq;
      _autoSaved[placeId] = token;
    } else {
      // Já salvo por outra lista pendente: participa da mesma decisão.
      token = _autoSaved[placeId];
    }
    return (done: _saved.setSaved(placeId, true), token: token);
  }

  /// Uma marcação/criação que salvou [placeId] falhou: se o salvamento ainda
  /// é "dela" e o local não está (nem vai estar) em lista nenhuma, desfaz.
  void _undoAutoSave(String placeId, int? token) {
    if (token == null || _autoSaved[placeId] != token) return;
    if (!_saved.isSaved(placeId) || listsContaining(placeId).isNotEmpty) {
      return;
    }
    _autoSaved.remove(placeId);
    unawaited(_saved.setSaved(placeId, false));
  }

  /// Cria a lista já (otimista). Com [withPlace], ela nasce com o local, que
  /// é salvo no "Quero ir" antes. `null` se não pode criar (limite, nome
  /// inválido ou repetido, listas não carregadas).
  ListCreation? create(String rawName, {String? emoji, String? withPlace}) {
    final uid = _uid;
    if (uid == null ||
        !canCreate ||
        !PlaceList.isValidName(rawName) ||
        !PlaceList.isValidEmoji(emoji) ||
        isNameTaken(rawName)) {
      return null;
    }
    final generation = _generation;
    // Salva já (otimista); a lista só é gravada depois da confirmação.
    final save = withPlace == null ? null : _saveFor(withPlace);
    final list = PlaceList(
      id: _repo.newListId(uid),
      name: PlaceList.normalizeName(rawName),
      emoji: emoji,
      placeIds: [?withPlace],
      createdAt: _clock(),
    );
    _creating[list.id] = list;
    _notify();
    final done = _enqueue(list.id, () async {
      try {
        var placeIds = const <String>[];
        if (withPlace != null && save != null) {
          if (!await save.done) throw StateError('não salvo: $withPlace');
          // Removido do "Quero ir" enquanto isso: a lista nasce vazia.
          if (_saved.isSaved(withPlace)) placeIds = [withPlace];
        }
        if (generation != _generation) return false;
        await _repo.createList(
          uid: uid,
          listId: list.id,
          name: list.name,
          emoji: list.emoji,
          placeIds: placeIds,
        );
        if (generation != _generation) return false;
        _server[list.id] = list.copyWith(placeIds: placeIds);
        _creating.remove(list.id);
        if (withPlace != null) _autoSaved.remove(withPlace);
        // Saiu do "Quero ir" com a criação em voo: tira da lista.
        if (withPlace != null &&
            placeIds.isNotEmpty &&
            !_saved.isSaved(withPlace)) {
          _dropGhost(list.id, withPlace);
        }
        _notify();
        return true;
      } on Object {
        if (generation != _generation) return false;
        _creating.remove(list.id);
        _members.remove(list.id);
        _meta.remove(list.id);
        if (withPlace != null) _undoAutoSave(withPlace, save?.token);
        _notify();
        return false;
      }
    });
    return (id: list.id, done: done);
  }

  /// Põe/tira [placeId] da lista (otimista). Pôr salva o local antes.
  /// Completa com `false` se falhou (estado revertido) ou não é possível
  /// (lista cheia, inexistente, listas não carregadas).
  Future<bool> setMembership(String listId, String placeId, bool member) =>
      _setMembership(listId, placeId, member);

  /// [force]: não checa a lista cheia (repor no "Desfazer" um membro que já
  /// estava lá; as Rules ainda limitam a 200).
  Future<bool> _setMembership(
    String listId,
    String placeId,
    bool member, {
    bool force = false,
  }) {
    final uid = _uid;
    final list = listById(listId);
    if (uid == null || !isReady || list == null) return Future.value(false);
    if (member && !force && !list.contains(placeId) && list.isFull) {
      return Future.value(false);
    }
    final generation = _generation;
    // Salva já (otimista); o membro só é gravado depois da confirmação.
    final save = member ? _saveFor(placeId) : null;
    final token = ++_seq;
    _members.putIfAbsent(listId, () => {})[placeId] = (
      member: member,
      token: token,
    );
    _notify();
    bool current() => _members[listId]?[placeId]?.token == token;
    return _enqueue(listId, () async {
      try {
        // Superada por outro toque ou cancelada (saiu do "Quero ir").
        if (generation != _generation) return false;
        if (!current()) return true;
        if (save != null) {
          if (!await save.done) throw StateError('não salvo: $placeId');
          if (generation != _generation) return false;
          if (!current()) return true;
        }
        await _repo.setMembership(
          uid: uid,
          listId: listId,
          placeId: placeId,
          member: member,
        );
        if (generation != _generation) return false;
        final base = _server[listId];
        if (base != null) {
          final ids = [...base.placeIds]..remove(placeId);
          if (member) ids.add(placeId);
          _server[listId] = base.copyWith(placeIds: ids);
        }
        _clearMember(listId, placeId, token);
        if (member) {
          _autoSaved.remove(placeId);
          // Saiu do "Quero ir" com a escrita em voo: tira da lista.
          if (!_saved.isSaved(placeId)) _dropGhost(listId, placeId);
        }
        _notify();
        return true;
      } on Object {
        if (generation != _generation) return false;
        _clearMember(listId, placeId, token);
        if (member) _undoAutoSave(placeId, save?.token);
        _notify();
        return false;
      }
    });
  }

  void _clearMember(String listId, String placeId, int token) {
    final m = _members[listId];
    if (m == null) return;
    if (m[placeId]?.token == token) m.remove(placeId);
    if (m.isEmpty) _members.remove(listId);
  }

  /// Renomeia / troca o emoji (mesmas validações da criação). Sem mudança,
  /// não escreve.
  Future<bool> rename(String listId, String rawName, {String? emoji}) {
    final uid = _uid;
    final current = listById(listId);
    if (uid == null ||
        !isReady ||
        current == null ||
        !PlaceList.isValidName(rawName) ||
        !PlaceList.isValidEmoji(emoji) ||
        isNameTaken(rawName, exceptId: listId)) {
      return Future.value(false);
    }
    final name = PlaceList.normalizeName(rawName);
    if (name == current.name && emoji == current.emoji) {
      return Future.value(true);
    }
    final generation = _generation;
    final token = ++_seq;
    _meta[listId] = (name: name, emoji: emoji, token: token);
    _notify();
    return _enqueue(listId, () async {
      var ok = false;
      try {
        await _repo.updateList(
          uid: uid,
          listId: listId,
          name: name,
          emoji: emoji,
        );
        ok = true;
      } on Object {
        ok = false;
      }
      if (generation != _generation) return false;
      if (ok) {
        final base = _server[listId];
        if (base != null) {
          _server[listId] = base.copyWith(name: name, emoji: () => emoji);
        }
      }
      if (_meta[listId]?.token == token) _meta.remove(listId);
      _notify();
      return ok;
    });
  }

  /// Exclui a lista (otimista). Os locais continuam no "Quero ir".
  Future<bool> delete(String listId) {
    final uid = _uid;
    if (uid == null || !isReady || listById(listId) == null) {
      return Future.value(false);
    }
    final generation = _generation;
    _deleting.add(listId);
    _notify();
    return _enqueue(listId, () async {
      var ok = false;
      try {
        await _repo.deleteList(uid: uid, listId: listId);
        ok = true;
      } on Object {
        ok = false;
      }
      if (generation != _generation) return false;
      _deleting.remove(listId);
      if (ok) {
        _server.remove(listId);
        _creating.remove(listId);
        _members.remove(listId);
        _meta.remove(listId);
      } else {
        // A lista volta: sem quem saiu do "Quero ir" enquanto isso (o batch
        // de remoção a pulou por estar sendo excluída).
        for (final placeId in [...?_server[listId]?.placeIds]) {
          if (!_saved.isSaved(placeId)) _dropGhost(listId, placeId);
        }
      }
      _notify();
      return ok;
    });
  }

  /// "Desfazer" de uma remoção do "Quero ir": salva de novo e repõe nas
  /// listas em que o local estava (sem checar se a lista ficou cheia).
  Future<RestoreResult> restore(
    String placeId,
    Iterable<String> listIds,
  ) async {
    final ids = listIds.toList();
    final saved = _saved.setSaved(placeId, true);
    final back = [
      for (final id in ids)
        if (listById(id) != null)
          _setMembership(id, placeId, true, force: true),
    ];
    if (!await saved) return RestoreResult.savedFailed;
    final results = await Future.wait(back);
    return back.length == ids.length && results.every((ok) => ok)
        ? RestoreResult.ok
        : RestoreResult.someListsFailed;
  }

  /// `remover` do [SavedPlacesStore]: apaga o salvo e tira o local de todas
  /// as listas num único batch.
  Future<void> _removeEverywhere(String uid, String placeId) async {
    final generation = _generation;
    if (!isReady) {
      // Sem saber em que listas o local está: remove só o salvo. A
      // reconciliação tira das listas quando elas carregarem.
      await _saved.removeOnly(uid, placeId);
      unawaited(reload());
      return;
    }
    var listIds = _listsWith(placeId);
    try {
      await _repo.removeEverywhere(
        uid: uid,
        placeId: placeId,
        listIds: listIds,
      );
    } on Object {
      // Lista apagada em outro aparelho (update de doc ausente falha o
      // batch): relê as listas e tenta uma vez sem as que sumiram.
      if (listIds.isEmpty || generation != _generation) rethrow;
      try {
        await _fetch(uid, generation);
      } on Object {
        rethrow;
      }
      final remaining = [
        for (final id in listIds)
          if (_server.containsKey(id)) id,
      ];
      if (remaining.length == listIds.length) rethrow;
      listIds = remaining;
      await _repo.removeEverywhere(
        uid: uid,
        placeId: placeId,
        listIds: listIds,
      );
    }
    if (generation != _generation) return;
    for (final id in listIds) {
      final base = _server[id];
      if (base == null) continue;
      _server[id] = base.copyWith(
        placeIds: [...base.placeIds]..remove(placeId),
      );
    }
    _notify();
  }

  /// Listas confirmadas que têm (ou vão ter) [placeId]. Exclusão pendente
  /// fica de fora: a lista vai sumir (e o update falharia o batch).
  List<String> _listsWith(String placeId) => [
    for (final l in _server.values)
      if (!_deleting.contains(l.id) &&
          (l.contains(placeId) || _display(l).contains(placeId)))
        l.id,
  ];

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_saved.remover == _removeEverywhere) _saved.remover = null;
    _saved.removeListener(_onSavedChanged);
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }
}
