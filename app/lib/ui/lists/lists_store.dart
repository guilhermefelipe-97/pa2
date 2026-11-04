import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/lists_repository.dart';
import '../../domain/models/place_list.dart';
import '../../domain/models/user_profile.dart';
import '../saved/saved_places_store.dart';

enum ListsStatus { idle, loading, ready, error }

enum RestoreResult { ok, savedFailed, someListsFailed }

typedef ListCreation = ({String id, Future<bool> done});

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

  final Duration _waitTimeout;

  String? _uid;
  int _generation = 0;

  ListsStatus _status = ListsStatus.idle;
  ListsStatus get status => _status;
  bool get isIdle => _status == ListsStatus.idle;
  bool get isReady => _status == ListsStatus.ready;
  bool get isLoading => _status == ListsStatus.loading;
  bool get hasError => _status == ListsStatus.error;

  final Map<String, PlaceList> _server = {};

  final Map<String, PlaceList> _creating = {};

  final Map<String, ({String name, String? emoji, int token})> _meta = {};

  final Map<String, ({bool visible, int token})> _visibility = {};

  String? _focusRequest;

  final Set<String> _deleting = {};

  final Map<String, Map<String, ({bool member, int token})>> _members = {};

  final Map<String, Future<bool>> _chains = {};

  final Map<String, int> _autoSaved = {};

  int _seq = 0;
  Future<void>? _loading;
  bool _reconcileScheduled = false;
  bool _disposed = false;

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
    final visibility = _visibility[base.id];
    if (meta == null &&
        visibility == null &&
        (members == null || members.isEmpty)) {
      return base;
    }
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
      visible: visibility?.visible,
    );
  }

  void focusList(String listId) {
    _focusRequest = listId;
    _notify();
  }

  String? takeFocusRequest() {
    final id = _focusRequest;
    _focusRequest = null;
    return id;
  }

  Set<String> savedPlaceIdsOf(PlaceList list) => {
    for (final id in list.placeIds)
      if (_saved.isSaved(id)) id,
  };

  int countOf(PlaceList list) => savedPlaceIdsOf(list).length;

  List<PlaceList> listsContaining(String placeId) => [
    for (final l in lists)
      if (l.contains(placeId)) l,
  ];

  bool get canCreate => isReady && lists.length < PlaceList.maxLists;

  bool isNameTaken(String rawName, {String? exceptId}) {
    final key = PlaceList.nameKey(rawName);
    return lists.any(
      (l) => l.id != exceptId && PlaceList.nameKey(l.name) == key,
    );
  }

  void _onSavedChanged() {
    _members.removeWhere((_, m) {
      m.removeWhere((placeId, o) => o.member && !_saved.isSaved(placeId));
      return m.isEmpty;
    });
    _autoSaved.removeWhere((placeId, _) => !_saved.isSaved(placeId));

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
    _visibility.clear();
    _focusRequest = null;
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

  Future<void> _fetch(String uid, int generation) async {
    final loaded = await _repo.listLists(uid).timeout(_waitTimeout);
    if (generation != _generation) return;
    _server
      ..clear()
      ..addAll({for (final l in loaded) l.id: l});
    _status = ListsStatus.ready;

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

  void _dropGhost(String listId, String placeId) {
    if (_members[listId]?.containsKey(placeId) ?? false) return;
    if (listById(listId) == null) return;
    unawaited(_setMembership(listId, placeId, false));
  }

  Future<bool> _enqueue(String listId, Future<bool> Function() op) {
    final prev = _chains[listId];
    final next = prev == null ? op() : prev.then((_) => op());
    _chains[listId] = next;
    next.whenComplete(() {
      if (identical(_chains[listId], next)) _chains.remove(listId);
    });
    return next;
  }

  ({Future<bool> done, int? token}) _saveFor(String placeId) {
    int? token;
    if (!_saved.isSaved(placeId)) {
      token = ++_seq;
      _autoSaved[placeId] = token;
    } else {
      token = _autoSaved[placeId];
    }
    return (done: _saved.setSaved(placeId, true), token: token);
  }

  void _undoAutoSave(String placeId, int? token) {
    if (token == null || _autoSaved[placeId] != token) return;
    if (!_saved.isSaved(placeId) || listsContaining(placeId).isNotEmpty) {
      return;
    }
    _autoSaved.remove(placeId);
    unawaited(_saved.setSaved(placeId, false));
  }

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
        _visibility.remove(list.id);
        if (withPlace != null) _undoAutoSave(withPlace, save?.token);
        _notify();
        return false;
      }
    });
    return (id: list.id, done: done);
  }

  ListCreation? copyFrom(PlaceList source, UserProfile author) {
    final uid = _uid;
    final authorUid = author.uid;

    final authorName = author.displayName;
    if (uid == null || uid == authorUid || !canCreate) return null;
    final generation = _generation;
    final name = PlaceList.copyName(
      source.name,
      authorName,
      isTaken: (n) => isNameTaken(n),
    );
    final emoji = PlaceList.isValidEmoji(source.emoji) ? source.emoji : null;
    final placeIds = [
      ...{...source.placeIds},
    ].take(PlaceList.maxPlaces).toList();
    final credit = ListCredit(
      uid: authorUid,
      name: authorName,
      listId: source.id,
    );

    final saves = {for (final id in placeIds) id: _saveFor(id)};
    final list = PlaceList(
      id: _repo.newListId(uid),
      name: name,
      emoji: emoji,
      placeIds: placeIds,
      createdAt: _clock(),
      copiedFrom: credit,
    );
    _creating[list.id] = list;
    _notify();
    final done = _enqueue(list.id, () async {
      try {
        final results = await Future.wait([
          for (final id in placeIds) saves[id]!.done,
        ]);
        if (generation != _generation) return false;
        final confirmed = [
          for (var i = 0; i < placeIds.length; i++)
            if (results[i] && _saved.isSaved(placeIds[i])) placeIds[i],
        ];
        if (placeIds.isNotEmpty && confirmed.isEmpty) {
          throw StateError('nenhum local salvo');
        }
        await _repo.createList(
          uid: uid,
          listId: list.id,
          name: list.name,
          emoji: list.emoji,
          placeIds: confirmed,
          copiedFrom: credit,
        );
        if (generation != _generation) return false;
        _server[list.id] = list.copyWith(placeIds: confirmed);
        _creating.remove(list.id);
        for (final id in placeIds) {
          if (_autoSaved[id] == saves[id]!.token) _autoSaved.remove(id);
        }
        _notify();
        unawaited(_recordCopy(source.id, authorUid, uid, list.id));
        return true;
      } on Object {
        if (generation != _generation) return false;
        _creating.remove(list.id);
        _members.remove(list.id);
        _meta.remove(list.id);
        _visibility.remove(list.id);
        for (final id in placeIds) {
          _undoAutoSave(id, saves[id]!.token);
        }
        _notify();
        return false;
      }
    });
    return (id: list.id, done: done);
  }

  Future<void> _recordCopy(
    String listId,
    String ownerUid,
    String uid,
    String copiedListId,
  ) async {
    try {
      await _repo.recordCopy(
        ownerUid: ownerUid,
        listId: listId,
        copierUid: uid,
        copiedListId: copiedListId,
      );
    } on Object catch (e) {
      debugPrint('Registro de cópia indisponível: $e');
    }
  }

  Future<int> copyCount(String listId) {
    final uid = _uid;
    if (uid == null) return Future.value(0);
    return _repo.copyCount(ownerUid: uid, listId: listId);
  }

  Future<bool> setVisible(String listId, bool visible) {
    final uid = _uid;
    final current = listById(listId);
    if (uid == null || !isReady || current == null) {
      return Future.value(false);
    }
    if (current.visible == visible) return Future.value(true);
    final generation = _generation;
    final token = ++_seq;
    _visibility[listId] = (visible: visible, token: token);
    _notify();
    return _enqueue(listId, () async {
      var ok = false;
      try {
        await _repo.setVisible(uid: uid, listId: listId, visible: visible);
        ok = true;
      } on Object {
        ok = false;
      }
      if (generation != _generation) return false;
      if (ok) {
        final base = _server[listId];
        if (base != null) _server[listId] = base.copyWith(visible: visible);
      }
      if (_visibility[listId]?.token == token) _visibility.remove(listId);
      _notify();
      return ok;
    });
  }

  Future<bool> setMembership(String listId, String placeId, bool member) =>
      _setMembership(listId, placeId, member);

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
        _visibility.remove(listId);
      } else {
        for (final placeId in [...?_server[listId]?.placeIds]) {
          if (!_saved.isSaved(placeId)) _dropGhost(listId, placeId);
        }
      }
      _notify();
      return ok;
    });
  }

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

  Future<void> _removeEverywhere(String uid, String placeId) async {
    final generation = _generation;
    if (!isReady) {
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
