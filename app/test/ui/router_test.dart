import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/routing/router.dart';
import 'package:naarea/routing/routes.dart';

void main() {
  String? go(String location, {bool init = true, bool signedIn = false}) =>
      authRedirect(isInitialized: init, isSignedIn: signedIn, location: location);

  test('antes de restaurar a sessão fica no splash', () {
    expect(go(Routes.feed, init: false), Routes.splash);
    expect(go(Routes.splash, init: false), isNull);
  });

  test('sessão ativa ao reabrir: splash vai direto ao feed', () {
    expect(go(Routes.splash, signedIn: true), Routes.feed);
  });

  test('deslogado vai para login; login e cadastro são permitidos', () {
    expect(go(Routes.splash), Routes.login);
    expect(go(Routes.feed), Routes.login);
    expect(go(Routes.pickPlace), Routes.login);
    expect(go(Routes.login), isNull);
    expect(go(Routes.signUp), isNull);
  });

  test('logado em login/cadastro vai para o feed; demais rotas seguem', () {
    expect(go(Routes.login, signedIn: true), Routes.feed);
    expect(go(Routes.signUp, signedIn: true), Routes.feed);
    expect(go(Routes.people, signedIn: true), isNull);
    expect(go(Routes.feed, signedIn: true), isNull);
  });
}
