import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/data/repositories/auth_repository.dart';
import 'package:naarea/ui/auth/auth_view_model.dart';

import '../support/fakes.dart';

void main() {
  late FakeUserRepository users;
  late FakeAuthRepository auth;
  late AuthViewModel vm;

  setUp(() {
    users = FakeUserRepository();
    auth = FakeAuthRepository(users: users);
    vm = AuthViewModel(authRepository: auth);
  });

  group('cadastro', () {
    for (final name in ['', '   ']) {
      test('nome "${name.replaceAll(' ', '·')}" bloqueia sem chamar o repositório', () async {
        final ok = await vm.signUp(displayName: name, email: 'a@b.com', password: '123456');
        expect(ok, isFalse);
        expect(vm.errorMessage, 'Informe seu nome.');
        expect(auth.signUpCalls, isEmpty);
      });
    }

    test('válido: cria conta com nome sem espaços nas pontas e perfil existe', () async {
      final ok = await vm.signUp(displayName: '  Bianca ', email: ' bia@x.com ', password: '123456');
      expect(ok, isTrue);
      expect(auth.signUpCalls.single['displayName'], 'Bianca');
      expect(auth.signUpCalls.single['email'], 'bia@x.com');
      expect(auth.isSignedIn, isTrue);
      expect(users.profiles[auth.currentUserId]!.displayName, 'Bianca');
      expect(vm.errorMessage, isNull);
      expect(vm.isLoading, isFalse);
    });

    test('nome acima de 60 caracteres bloqueia com mensagem específica', () async {
      final ok = await vm.signUp(displayName: 'a' * 61, email: 'a@b.com', password: '123456');
      expect(ok, isFalse);
      expect(vm.errorMessage, 'Nome muito longo (máx. 60 caracteres).');
      expect(auth.signUpCalls, isEmpty);
    });

    test('nome com exatamente 60 caracteres (após trim) é aceito', () async {
      final ok = await vm.signUp(displayName: '  ${'a' * 60}  ', email: 'a@b.com', password: '123456');
      expect(ok, isTrue);
      expect(auth.signUpCalls.single['displayName'], 'a' * 60);
    });

    test('senha curta bloqueia', () async {
      final ok = await vm.signUp(displayName: 'Bia', email: 'a@b.com', password: '123');
      expect(ok, isFalse);
      expect(vm.errorMessage, contains('6'));
      expect(auth.signUpCalls, isEmpty);
    });

    test('erro do provedor aparece na tela', () async {
      auth.nextError = const AuthException('Este e-mail já está cadastrado.');
      final ok = await vm.signUp(displayName: 'Bia', email: 'a@b.com', password: '123456');
      expect(ok, isFalse);
      expect(vm.errorMessage, 'Este e-mail já está cadastrado.');
      expect(vm.isLoading, isFalse);
    });
  });

  group('login', () {
    test('e-mail vazio bloqueia', () async {
      expect(await vm.signIn(email: ' ', password: '123456'), isFalse);
      expect(auth.signInCalls, isEmpty);
    });

    test('válido entra', () async {
      expect(await vm.signIn(email: 'a@b.com', password: '123456'), isTrue);
      expect(auth.isSignedIn, isTrue);
    });

    test('clearError limpa a mensagem', () async {
      await vm.signIn(email: '', password: '');
      expect(vm.errorMessage, isNotNull);
      vm.clearError();
      expect(vm.errorMessage, isNull);
    });
  });
}
