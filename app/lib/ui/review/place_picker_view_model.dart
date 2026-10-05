import 'dart:async';

import '../../data/repositories/place_repository.dart';
import '../../domain/models/place.dart';
import '../../domain/search_tokens.dart';
import '../core/safe_change_notifier.dart';

/// Escolha do local a avaliar: busca por nome no catálogo (~600 locais) sem
/// ler a coleção inteira. Busca curta (0–1 letra) mostra sugestões (curados
/// com foto).
class PlacePickerViewModel extends SafeChangeNotifier {
  PlacePickerViewModel({
    required PlaceRepository placeRepository,
    this.debounce = const Duration(milliseconds: 300),
  }) : _places = placeRepository;

  final PlaceRepository _places;

  /// Espera depois da última tecla antes de consultar.
  final Duration debounce;

  Timer? _timer;

  /// Só a resposta da consulta mais recente é aplicada.
  int _seq = 0;

  String _query = '';
  String get query => _query;

  List<Place> _suggestions = const [];
  bool _suggestionsLoaded = false;
  List<Place> _results = const [];

  bool _isLoading = false;

  /// Carregando (a View mostra skeleton).
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  String? _category;

  /// Chip de categoria selecionado (null = todas).
  String? get selectedCategory => _category;

  /// Busca curta: mostra sugestões em vez de resultados.
  bool get isShowingSuggestions => serverTerm(normalizeQuery(_query)) == null;

  List<Place> get _base => isShowingSuggestions ? _suggestions : _results;

  /// Categorias presentes na lista atual (para os chips), em ordem alfabética.
  List<String> get categories {
    final set = {
      for (final p in _base)
        if (p.category.trim().isNotEmpty) p.category,
    };
    return set.toList()..sort((a, b) => nameLower(a).compareTo(nameLower(b)));
  }

  /// Locais a exibir (resultados ou sugestões, filtrados pelo chip).
  List<Place> get places {
    final c = _category;
    final base = _base;
    if (c == null) return base;
    return base.where((p) => p.category == c).toList();
  }

  /// A busca devolveu o máximo de resultados: pode haver mais (refinar).
  bool get isResultCapped =>
      !isShowingSuggestions && _results.length >= placeSearchLimit;

  /// Busca concluída sem resultados: "Nenhum local com esse nome".
  bool get showNoResults =>
      !_isLoading && _errorMessage == null && !isShowingSuggestions && _results.isEmpty;

  /// Carga inicial: sugestões.
  Future<void> load() => _loadSuggestions();

  void setQuery(String value) {
    if (value == _query) return;
    _query = value;
    _timer?.cancel();
    _category = null;
    if (isShowingSuggestions) {
      _seq++; // descarta consulta em voo
      _results = const [];
      _errorMessage = null;
      _isLoading = false;
      notifyListeners();
      if (!_suggestionsLoaded) _loadSuggestions();
      return;
    }
    _seq++; // resposta antiga não pode tirar o skeleton durante o debounce
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    _timer = Timer(debounce, _search);
  }

  void selectCategory(String? category) {
    _category = category == _category ? null : category;
    notifyListeners();
  }

  /// "Tentar de novo": repete a operação atual sem esperar o debounce.
  Future<void> retry() {
    _timer?.cancel();
    return isShowingSuggestions ? _loadSuggestions() : _search();
  }

  Future<void> _loadSuggestions() async {
    final seq = ++_seq;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final list = await _places.suggestions();
      if (seq != _seq) return;
      _suggestions = list;
      _suggestionsLoaded = true;
    } on Object {
      if (seq != _seq) return;
      _errorMessage = 'Não foi possível carregar os locais.';
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _search() async {
    final seq = ++_seq;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final list = await _places.search(_query);
      if (seq != _seq) return;
      _results = list;
    } on Object {
      if (seq != _seq) return;
      _results = const [];
      _errorMessage = 'Não foi possível buscar os locais.';
    }
    _isLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
