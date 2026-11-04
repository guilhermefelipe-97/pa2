import '../../data/repositories/place_repository.dart';
import '../../domain/models/place.dart';
import '../../domain/models/place_list.dart';
import '../core/safe_change_notifier.dart';
import '../lists/lists_store.dart';
import 'saved_places_store.dart';

typedef SavedItem = ({Place place, DateTime savedAt});

class SavedViewModel extends SafeChangeNotifier {
  SavedViewModel({
    required SavedPlacesStore store,
    required PlaceRepository placeRepository,
    ListsStore? lists,
    DateTime Function()? clock,
  }) : _store = store,
       _places = placeRepository,
       _lists = lists,
       _clock = clock ?? DateTime.now {
    _store.addListener(_onStoreChanged);
    _lists?.addListener(_onListsChanged);
    _takeFocusRequest();
    _onStoreChanged();
  }

  static const errorText =
      'Não foi possível carregar seus salvos. Verifique sua conexão.';

  final SavedPlacesStore _store;
  final PlaceRepository _places;
  final ListsStore? _lists;
  final DateTime Function() _clock;

  ListsStore? get listsStore => _lists;

  String? _selectedListId;

  List<PlaceList> get lists =>
      _lists != null && _lists.isReady ? _lists.lists : const [];

  PlaceList? get selectedList {
    final id = _selectedListId;
    if (id == null) return null;
    return _lists?.listById(id);
  }

  void selectList(String? listId) {
    if (listId == _selectedListId) return;
    _selectedListId = listId;
    notifyListeners();
  }

  void _takeFocusRequest() {
    final lists = _lists;
    final id = lists?.takeFocusRequest();

    if (id != null && lists?.listById(id) != null) _selectedListId = id;
  }

  void _onListsChanged() {
    _takeFocusRequest();
    notifyListeners();
  }

  bool get isSelectedListVisible => selectedList?.visible ?? false;

  Future<bool> setSelectedListVisible(bool visible) {
    final list = selectedList;
    final lists = _lists;
    if (list == null || lists == null) return Future.value(false);
    return lists.setVisible(list.id, visible);
  }

  Future<int?> copyCountOf(PlaceList list) async {
    final lists = _lists;
    if (lists == null) return null;
    try {
      return await lists.copyCount(list.id);
    } on Object {
      return null;
    }
  }

  int countOf(PlaceList list) =>
      _allItems.where((i) => list.contains(i.place.id)).length;

  int get savedCount => _allItems.length;

  bool get listsFailed => _lists?.hasError ?? false;

  Future<void> retryLists() => _lists?.reload() ?? Future.value();

  DateTime now() => _clock();

  final Map<String, Place?> _resolved = {};

  final Set<String> _failedIds = {};

  final Set<String> _revalidate = {};

  bool _fetching = false;
  bool get _placesFailed => _failedIds.isNotEmpty;

  List<SavedItem> get items {
    final list = selectedList;
    return [
      for (final e in _store.entries)
        if (list == null || list.contains(e.placeId))
          if (_resolved[e.placeId] case final Place p)
            (place: p, savedAt: e.savedAt),
    ];
  }

  List<SavedItem> get _allItems => [
    for (final e in _store.entries)
      if (_resolved[e.placeId] case final Place p)
        (place: p, savedAt: e.savedAt),
  ];

  bool get isListLoading {
    final list = selectedList;
    if (list == null || !_store.isReady || _placesFailed) return false;
    return list.placeIds.any(
      (id) => _store.isSaved(id) && !_resolved.containsKey(id),
    );
  }

  bool get isListEmpty =>
      selectedList != null &&
      _store.isReady &&
      items.isEmpty &&
      !_placesFailed &&
      !isLoading &&
      !isListLoading;

  Set<String> get _unresolved => {
    for (final e in _store.entries)
      if (!_resolved.containsKey(e.placeId)) e.placeId,
  };

  bool get isLoading =>
      (!_store.isReady && !_store.hasError) ||
      (_store.isReady &&
          _allItems.isEmpty &&
          _unresolved.isNotEmpty &&
          !_placesFailed);

  String? get errorMessage =>
      _store.hasError || _placesFailed ? errorText : null;

  bool get isEmpty =>
      _store.isReady &&
      _unresolved.isEmpty &&
      _allItems.isEmpty &&
      !_placesFailed;

  int revision = 0;
  Future<void> refresh() async {
    revision++;
    _failedIds.clear();
    _revalidate.addAll([
      for (final e in _resolved.entries)
        if (e.value == null) e.key,
    ]);
    notifyListeners();
    await Future.wait([_store.reload(), ?_lists?.reload()]);
    if (isDisposed) return;
    await _resolveMissing();
  }

  void _onStoreChanged() {
    if (_placesFailed && !_failedIds.containsAll(_unresolved)) {
      _failedIds.clear();
    }
    notifyListeners();
    _resolveMissing();
  }

  Future<void> _resolveMissing() async {
    if (_fetching || isDisposed || !_store.isReady || _placesFailed) return;
    final saved = {for (final e in _store.entries) e.placeId};
    _revalidate.retainAll(saved);
    final recheck = {..._revalidate};
    final missing = {..._unresolved, ...recheck};
    if (missing.isEmpty) return;
    _fetching = true;
    var ok = false;
    try {
      final found = await _places.getPlaces(
        missing,
        refreshMissing: recheck.isNotEmpty,
      );
      for (final id in missing) {
        _resolved[id] = found[id];
      }
      _revalidate.removeAll(recheck);
      ok = true;
    } on Object {
      _failedIds.addAll(missing);
    } finally {
      _fetching = false;
      notifyListeners();
    }

    if (ok) await _resolveMissing();
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    _lists?.removeListener(_onListsChanged);
    super.dispose();
  }
}
