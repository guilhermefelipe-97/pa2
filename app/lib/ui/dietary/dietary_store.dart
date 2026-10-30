import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/dietary_repository.dart';
import '../core/safe_change_notifier.dart';

class DietaryStore extends SafeChangeNotifier {
  DietaryStore(this.auth, this.repository) {
    auth.addListener(_session);
    _session();
  }
  final AuthRepository auth;
  final DietaryRepository repository;
  String? _uid;
  int _epoch = 0;
  int _operation = 0;
  bool _saving = false;
  int get sessionEpoch => _epoch;
  Set<String> tags = const {};
  bool loading = true;
  bool ready = false;
  String? error;
  int revision = 0;
  void _session() {
    if (_uid == auth.currentUserId && _epoch > 0) return;
    _uid = auth.currentUserId;
    _epoch++;
    _saving = false;
    tags = const {};
    ready = false;
    error = null;
    revision++;
    load();
  }

  Future<void> load() async {
    if (_saving) return;
    final operation = ++_operation;
    final epoch = _epoch;
    final uid = _uid;
    loading = true;
    ready = false;
    error = null;
    notifyListeners();
    if (uid == null) {
      loading = false;
      notifyListeners();
      return;
    }
    try {
      final read = await repository.load(uid);
      if (epoch != _epoch || operation != _operation || isDisposed) return;
      tags = Set.unmodifiable(read);
      ready = true;
      revision++;
    } on Object {
      if (epoch != _epoch || operation != _operation || isDisposed) return;
      error = 'Não foi possível carregar suas preferências. Tente novamente.';
    } finally {
      if (epoch == _epoch && operation == _operation && !isDisposed) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> save(Set<String> value) async {
    final uid = _uid;
    final epoch = _epoch;
    if (uid == null || _saving) return false;
    final operation = ++_operation;
    final saved = Set<String>.of(value);
    _saving = true;
    loading = true;
    error = null;
    notifyListeners();
    try {
      await repository.save(uid, saved);
      if (epoch != _epoch || operation != _operation || isDisposed) {
        return false;
      }
      tags = Set.unmodifiable(saved);
      ready = true;
      revision++;
      return true;
    } on Object {
      if (epoch == _epoch && operation == _operation) {
        error = 'Não foi possível salvar. Tente novamente.';
      }
      return false;
    } finally {
      if (epoch == _epoch && operation == _operation && !isDisposed) {
        _saving = false;
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _epoch++;
    auth.removeListener(_session);
    super.dispose();
  }
}
