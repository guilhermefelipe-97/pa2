import 'package:flutter/foundation.dart';

/// Estado de autenticação. É um [ChangeNotifier] para servir de
/// `refreshListenable` do go_router.
abstract class AuthRepository extends ChangeNotifier {
  /// `false` até a primeira resposta do provedor (sessão restaurada ou não).
  bool get isInitialized;

  String? get currentUserId;

  bool get isSignedIn => currentUserId != null;

  /// Cria a conta e o perfil `users/{uid}` com o nome normalizado.
  Future<void> signUp({
    required String displayName,
    required String email,
    required String password,
  });

  Future<void> signIn({required String email, required String password});

  Future<void> signOut();
}

/// Erro de autenticação com mensagem pronta para a UI.
class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => 'AuthException: $message';
}
