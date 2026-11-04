import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/data/repositories/owner_repository.dart';
import 'package:naarea/routing/routes.dart';
import 'package:naarea/ui/core/theme.dart';
import 'package:naarea/ui/profile/profile_view.dart';
import '../support/app_harness.dart';
import '../support/builders.dart';
import '../support/fakes.dart';

void main() {
  testWidgets('Quero ir cria uma lista vazia pelo cabeçalho', (tester) async {
    final app = await pumpApp(tester);
    app.router.go(Routes.saved);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saved-new-list')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('list-name-field')),
      'Cafés para conhecer',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('list-name-submit')));
    await tester.pumpAndSettle();
    expect(app.lists.byUser['me']!.values.single.name, 'Cafés para conhecer');
    expect(app.lists.byUser['me']!.values.single.placeIds, isEmpty);
    expect(find.textContaining('Cafés para conhecer'), findsWidgets);
  });

  testWidgets(
    'Seguindo abre perfil real e reflete deixar de seguir ao voltar',
    (tester) async {
      final users = FakeUserRepository()
        ..addUser('me', 'Bianca')
        ..addUser('ana', 'Ana Silva')
        ..followingByUser['me'] = {'ana'};
      final app = await pumpApp(tester, users: users);
      app.router.go(Routes.people);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Seguindo 1'));
      await tester.pumpAndSettle();
      expect(find.text('Ana Silva'), findsOneWidget);
      await tester.tap(find.text('Ver perfil'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileView), findsOneWidget);
      await tester.tap(find.byKey(const Key('profile-follow')));
      await tester.pumpAndSettle();
      app.router.pop();
      await tester.pumpAndSettle();
      expect(find.text('Seguindo 0'), findsOneWidget);
      expect(users.followingByUser['me'], isEmpty);
      expect(find.text('Você ainda não segue ninguém.'), findsOneWidget);
    },
  );

  testWidgets('telas restantes em 320dp e fonte 2x preservam layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final owners = FakeOwnerRepository()
      ..owners['p1'] = 'me'
      ..requests['me'] = [const OwnershipRequest('p1', 'approved')];
    final app = await pumpApp(
      tester,
      theme: AppTheme.light(),
      textScale: 2,
      owners: owners,
      places: [place()],
    );
    for (final route in [
      Routes.saved,
      Routes.people,
      '/meus-estabelecimentos',
      Routes.person('me'),
      Routes.settings,
    ]) {
      app.router.go(route);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: route);
    }
  });
}
