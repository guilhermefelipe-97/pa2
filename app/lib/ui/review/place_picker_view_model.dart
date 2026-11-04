import 'dart:async';

import '../../data/photon/photon_client.dart';
import '../../data/repositories/place_repository.dart';
import '../../data/services/location_service.dart';
import '../../domain/geo.dart';
import '../../domain/models/place.dart';
import '../../domain/search_tokens.dart';
import '../core/safe_change_notifier.dart';

class PlacePickerViewModel extends SafeChangeNotifier {
  PlacePickerViewModel({
    required PlaceRepository placeRepository,
    LocationService? locationService,
    this.debounce = const Duration(milliseconds: 300),
  }) : _places = placeRepository,
       _location = locationService;

  final PlaceRepository _places;
  final LocationService? _location;

  static const loadErrorMessage =
      'Não foi possível carregar os locais. Verifique sua conexão.';
  static const searchErrorMessage =
      'Não foi possível buscar os locais. Verifique sua conexão.';

  LatLng? _near;
  LatLng? get near => _near;

  Future<LatLng?> _bias() async {
    final known = _near;
    if (known != null) return known;
    final location = _location;
    if (location == null) return null;
    try {
      _near = await location.lastKnownPositionIfGranted();
      notifyListeners();
      return _near;
    } on Object {
      return null;
    }
  }

  final Duration debounce;

  Timer? _timer;

  int _seq = 0;

  String _query = '';
  String get query => _query;

  List<Place> _suggestions = const [];
  bool _suggestionsLoaded = false;
  List<Place> _results = const [];

  bool _isLoading = false;

  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  String? _category;
  static const filterOptions = ['Cafés & Padarias', 'Restaurantes', 'Bares'];

  String? get selectedCategory => _category;

  bool get isShowingSuggestions => serverTerm(normalizeQuery(_query)) == null;

  List<Place> get _base => isShowingSuggestions ? _suggestions : _results;

  List<String> get categories {
    final set = {
      for (final p in _base)
        if (p.category.trim().isNotEmpty) p.category,
    };
    return set.toList()..sort((a, b) => nameLower(a).compareTo(nameLower(b)));
  }

  List<Place> get places {
    final c = _category;
    final base = _base;
    if (c == null) return base;
    return base.where((p) {
      final category = nameLower(p.category);
      final cuisine = nameLower(p.cuisine ?? '');
      return switch (c) {
        'Cafés & Padarias' =>
          category.contains('caf') ||
              category.contains('padar') ||
              category.contains('confeitar'),
        'Restaurantes' =>
          category.contains('restaurante') ||
              category.contains('cozinha') ||
              category.contains('bistro') ||
              category.contains('bistrô'),
        'Bares' =>
          category.contains('bar') ||
              category.contains('pub') ||
              category.contains('boteco'),
        _ => p.category == c || cuisine == c,
      };
    }).toList();
  }

  bool get isResultCapped =>
      !isShowingSuggestions && _results.length >= placeSearchLimit;

  bool get showNoResults =>
      !_isLoading &&
      _errorMessage == null &&
      !isShowingSuggestions &&
      _results.isEmpty;

  Future<void> load() {
    unawaited(_bias());
    return _loadSuggestions();
  }

  void setQuery(String value) {
    if (value == _query) return;
    _query = value;
    _timer?.cancel();
    _category = null;
    if (isShowingSuggestions) {
      _seq++;
      _results = const [];
      _errorMessage = null;
      _isLoading = false;
      notifyListeners();
      if (!_suggestionsLoaded) _loadSuggestions();
      return;
    }
    _seq++;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    _timer = Timer(debounce, _search);
  }

  void selectCategory(String? category) {
    _category = category == _category ? null : category;
    notifyListeners();
  }

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
      _errorMessage = loadErrorMessage;
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
      final near = await _bias();
      if (seq != _seq) return;
      final list = await _places.search(_query, near: near);
      if (seq != _seq) return;
      _results = list;
    } on Object catch (e) {
      if (seq != _seq) return;
      _results = const [];
      _errorMessage = e is PhotonRateLimitedException
          ? PhotonRateLimitedException.userMessage
          : searchErrorMessage;
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
