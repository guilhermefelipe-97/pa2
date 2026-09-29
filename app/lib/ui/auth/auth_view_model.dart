import '../../data/repositories/auth_repository.dart';
import '../../domain/models/user_profile.dart';
import '../core/safe_change_notifier.dart';

class AuthViewModel extends SafeChangeNotifier {
  AuthViewModel({required AuthRepository authRepository}) : _auth = authRepository;

  final AuthRepository _auth;

  static const int minPasswordLength = 6;
  static const String nameTooLongMessage = 'Nome muito longo (máx. 60 caracteres).';

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// Retorna `true` quando o cadastro deu certo (o redirect leva ao feed).
  Future<bool> signUp({
    required String displayName,
    required String email,
    required String password,
  }) async {
    if (!UserProfile.isNonEmptyName(displayName)) {
      return _fail('Informe seu nome.');
    }
    if (!UserProfile.isNameWithinLimit(displayName)) {
      return _fail(nameTooLongMessage);
    }
    final credentialsError = _validateCredentials(email, password);
    if (credentialsError != null) return _fail(credentialsError);

    return _run(() => _auth.signUp(
          displayName: UserProfile.normalizeName(displayName),
          email: email.trim(),
          password: password,
        ));
  }

  Future<bool> signIn({required String email, required String password}) async {
    final credentialsError = _validateCredentials(email, password);
    if (credentialsError != null) return _fail(credentialsError);
    return _run(() => _auth.signIn(email: email.trim(), password: password));
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  String? _validateCredentials(String email, String password) {
    if (email.trim().isEmpty) return 'Informe seu e-mail.';
    if (password.length < minPasswordLength) {
      return 'A senha precisa ter pelo menos $minPasswordLength caracteres.';
    }
    return null;
  }

  bool _fail(String message) {
    _errorMessage = message;
    notifyListeners();
    return false;
  }

  Future<bool> _run(Future<void> Function() action) async {
    if (_isLoading) return false;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await action();
      return true;
    } on AuthException catch (e) {
      _errorMessage = e.message;
      return false;
    } on Object {
      _errorMessage = 'Algo deu errado. Tente de novo.';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
