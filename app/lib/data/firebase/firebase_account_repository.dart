import 'package:firebase_auth/firebase_auth.dart';
import '../repositories/account_repository.dart';
import '../repositories/auth_repository.dart' show AuthException;

class FirebaseAccountRepository implements AccountRepository {
  FirebaseAccountRepository(this.auth);
  final FirebaseAuth auth;
  @override
  String? get email => auth.currentUser?.email;
  @override
  Future<void> refresh() => _run(() async {
    await auth.currentUser?.reload();
  });
  Future<User> _verify(String password) async {
    final user = auth.currentUser;
    if (user == null || user.email == null) {
      throw const AuthException('Entre novamente para alterar a conta.');
    }
    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: user.email!, password: password),
    );
    if (auth.currentUser?.uid != user.uid) {
      throw const AuthException('Conta alterada. Entre novamente.');
    }
    return user;
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on FirebaseAuthException catch (e) {
      throw AuthException(switch (e.code) {
        'wrong-password' || 'invalid-credential' => 'Senha atual incorreta.',
        'email-already-in-use' => 'Este e-mail já está em uso.',
        'invalid-email' => 'Informe um e-mail válido.',
        'weak-password' => 'Use uma senha com pelo menos 6 caracteres.',
        'network-request-failed' => 'Sem conexão. Tente novamente.',
        'too-many-requests' => 'Muitas tentativas. Aguarde e tente novamente.',
        _ =>
          'Não foi possível alterar a conta. Entre novamente e tente outra vez.',
      });
    }
  }

  @override
  Future<void> requestEmailChange({
    required String email,
    required String currentPassword,
  }) => _run(() async {
    final user = await _verify(currentPassword);
    await user.verifyBeforeUpdateEmail(email.trim());
  });
  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => _run(() async {
    if (newPassword.length < 6) {
      throw const AuthException('Use uma senha com pelo menos 6 caracteres.');
    }
    final user = await _verify(currentPassword);
    await user.updatePassword(newPassword);
  });
}
