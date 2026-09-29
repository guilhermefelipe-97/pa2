import '../../data/repositories/place_repository.dart';
import '../../domain/models/place.dart';
import '../core/safe_change_notifier.dart';

/// Escolha do local a avaliar.
class PlacePickerViewModel extends SafeChangeNotifier {
  PlacePickerViewModel({required PlaceRepository placeRepository})
      : _places = placeRepository;

  final PlaceRepository _places;

  List<Place> _all = const [];

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  String _query = '';
  String get query => _query;

  List<Place> get places {
    final q = _normalize(_query);
    if (q.isEmpty) return _all;
    return _all
        .where((p) =>
            _normalize(p.name).contains(q) || _normalize(p.neighborhood).contains(q))
        .toList();
  }

  Future<void> load() async {
    if (_isLoading) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _all = await _places.listPlaces();
    } on Object {
      _errorMessage = 'Não foi possível carregar os locais.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setQuery(String value) {
    _query = value;
    notifyListeners();
  }

  static const _accents = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
    'é': 'e', 'ê': 'e', 'è': 'e',
    'í': 'i', 'î': 'i',
    'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
    'ú': 'u', 'ü': 'u',
    'ç': 'c',
  };

  static String _normalize(String s) {
    final lower = s.trim().toLowerCase();
    final buf = StringBuffer();
    for (final ch in lower.split('')) {
      buf.write(_accents[ch] ?? ch);
    }
    return buf.toString();
  }
}
