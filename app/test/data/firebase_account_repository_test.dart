import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/data/firebase/firebase_account_repository.dart';
import 'package:naarea/data/repositories/auth_repository.dart' as app;

// ignore: must_be_immutable
class TrackedUser extends MockUser {
  TrackedUser()
    : super(uid: 'me', email: 'atual@exemplo.com', isAnonymous: false);
  final calls = <String>[];
  bool deny = false;
  @override
  Future<UserCredential> reauthenticateWithCredential(
    AuthCredential? credential,
  ) async {
    calls.add('reauth');
    if (deny) throw FirebaseAuthException(code: 'wrong-password');
    return super.reauthenticateWithCredential(credential);
  }

  @override
  Future<void> verifyBeforeUpdateEmail(
    String email, [
    ActionCodeSettings? settings,
  ]) async {
    calls.add('verify:$email');
  }

  @override
  Future<void> updatePassword(String value) async {
    calls.add('password');
  }
}

void main() {
  test(
    'email confirma identidade antes de solicitar verificação, sem alterar endereço prematuramente',
    () async {
      final user = TrackedUser();
      final repo = FirebaseAccountRepository(
        MockFirebaseAuth(mockUser: user, signedIn: true),
      );
      await repo.requestEmailChange(
        email: 'novo@exemplo.com',
        currentPassword: 'senha',
      );
      expect(user.calls, ['reauth', 'verify:novo@exemplo.com']);
      expect(repo.email, 'atual@exemplo.com');
    },
  );
  test('senha incorreta impede alterar senha e erro é legível', () async {
    final user = TrackedUser()..deny = true;
    final repo = FirebaseAccountRepository(
      MockFirebaseAuth(mockUser: user, signedIn: true),
    );
    await expectLater(
      repo.changePassword(currentPassword: 'errada', newPassword: 'nova-senha'),
      throwsA(isA<app.AuthException>()),
    );
    expect(user.calls, ['reauth']);
    user.deny = false;
    user.calls.clear();
    await repo.changePassword(
      currentPassword: 'correta',
      newPassword: 'nova-senha',
    );
    expect(user.calls, ['reauth', 'password']);
  });
}
