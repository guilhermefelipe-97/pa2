import '../../data/repositories/place_repository.dart';
import '../../domain/models/place.dart';
import '../../domain/models/place_list.dart';
import '../core/safe_change_notifier.dart';
import '../lists/lists_store.dart';
import 'saved_places_store.dart';

/// Um item da aba "Quero ir".
typedef SavedItem = ({Place place, DateTime savedAt});

/// Aba "Quero ir" (F11): os salvos do [SavedPlacesStore], do mais recente
/// para o mais antigo, com os dados do local. Salvo que aponta para um local
/// que sumiu do catálogo é omitido (e revalidado no "Tentar de novo" e ao
/// puxar para atualizar). Com o [ListsStore] (F12), chips filtram por lista.
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
    _lists?.addListener(notifyListeners);
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

  /// Listas para os chips (vazio sem listas ou antes de carregar).
  List<PlaceList> get lists =>
      _lists != null && _lists.isReady ? _lists.lists : const [];

  /// Lista do chip ativo; `null` = "Todos". Lista que sumiu (excluída,
  /// troca de usuário) volta para "Todos".
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

  /// Cards visíveis da lista (salvos e resolvidos no catálogo): o número do
  /// chip bate com o que aparece ao filtrar.
  int countOf(PlaceList list) =>
      _allItems.where((i) => list.contains(i.place.id)).length;

  /// Cards visíveis em "Todos".
  int get savedCount => _allItems.length;

  /// Listas não carregaram (banner discreto acima dos cards).
  bool get listsFailed => _lists?.hasError ?? false;

  /// "Tentar de novo" do banner das listas.
  Future<void> retryLists() => _lists?.reload() ?? Future.value();

  /// "Agora" para o "salvo há…" (injetável nos testes).
  DateTime now() => _clock();

  /// Locais já resolvidos; `null` = ausente do catálogo.
  final Map<String, Place?> _resolved = {};

  /// Ids cuja leitura falhou por último (um id novo tenta de novo).
  final Set<String> _failedIds = {};

  /// Ausentes a reler ignorando o cache da sessão (no próximo resolve).
  final Set<String> _revalidate = {};

  bool _fetching = false;
  bool get _placesFailed => _failedIds.isNotEmpty;

  /// Salvos do filtro ativo, do mais recente para o mais antigo.
  List<SavedItem> get items {
    final list = selectedList;
    return [
      for (final e in _store.entries)
        if (list == null || list.contains(e.placeId))
          if (_resolved[e.placeId] case final Place p)
            (place: p, savedAt: e.savedAt),
    ];
  }

  /// Todos os salvos resolvidos, sem filtro.
  List<SavedItem> get _allItems => [
    for (final e in _store.entries)
      if (_resolved[e.placeId] case final Place p)
        (place: p, savedAt: e.savedAt),
  ];

  /// Lista ativa com locais salvos ainda sem dados do catálogo (mostra
  /// carregando, não "Nada nesta lista ainda").
  bool get isListLoading {
    final list = selectedList;
    if (list == null || !_store.isReady || _placesFailed) return false;
    return list.placeIds.any(
      (id) => _store.isSaved(id) && !_resolved.containsKey(id),
    );
  }

  /// Lista ativa sem nenhum local (salvo e resolvido).
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

  /// "Tentar de novo" e puxar para atualizar: relê os salvos e revalida os
  /// locais dados como ausentes.
  Future<void> refresh() async {
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
    // Id salvo depois de uma falha: tenta resolver de novo.
    if (_placesFailed && !_failedIds.containsAll(_unresolved)) {
      _failedIds.clear();
    }
    notifyListeners();
    _resolveMissing();
  }

  /// Resolve os ids sem local e os marcados em [_revalidate]. Se já houver
  /// uma leitura em voo, a dela pega o que sobrar ao terminar.
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
    // Salvos novos (ou revalidações pedidas) chegaram durante a leitura.
    if (ok) await _resolveMissing();
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    _lists?.removeListener(notifyListeners);
    super.dispose();
  }
}
