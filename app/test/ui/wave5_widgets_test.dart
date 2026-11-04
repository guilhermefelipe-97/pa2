import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/routing/routes.dart';
import 'package:naarea/ui/core/theme.dart';
import '../support/app_harness.dart';
import '../support/builders.dart';
import '../support/fakes.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'titularidade em 320dp com fonte ${scale}x envia sem overflow',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final owners = FakeOwnerRepository();
        final app = await pumpApp(
          tester,
          owners: owners,
          places: [place()],
          theme: AppTheme.light(),
          textScale: scale,
        );
        app.router.go(Routes.placeDetail('p1'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Solicitar titularidade'));
        await tester.pumpAndSettle();
        expect(find.text('Este estabelecimento é seu?'), findsOneWidget);
        final submit = find.byKey(const Key('ownership-request-submit'));
        await tester.ensureVisible(submit);
        await tester.pumpAndSettle();
        expect(submit.hitTestable(), findsOneWidget);
        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(owners.requests['me'], hasLength(1));
        expect(find.textContaining('Pedido pendente.'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Fechar'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
      },
    );
  }
  testWidgets(
    'filtro vazio explica motivo; editor persiste seleção e limpar recupera cards',
    (tester) async {
      final users = FakeUserRepository()
        ..addUser('me', 'Eu')
        ..addUser('a', 'Ana');
      users.followingByUser['me'] = {'a'};
      final reviews = FakeReviewRepository()
        ..stored.add(review(placeId: 'p1', authorId: 'a', authorName: 'Ana'));
      final preferences = FakeDietaryRepository()
        ..stored['me'] = {'vegano', 'integral'};
      await pumpApp(
        tester,
        users: users,
        reviews: reviews,
        places: [place()],
        dietary: preferences,
      );
      expect(find.textContaining('Nenhum local dos amigos'), findsOneWidget);
      await tester.tap(find.text('Editar ou limpar filtro'));
      await tester.pumpAndSettle();
      expect(find.text('2 tags selecionadas'), findsOneWidget);
      expect(find.byKey(const Key('food-filter-vegano')), findsOneWidget);
      await tester.tap(find.byKey(const Key('food-filter-clear')));
      await tester.tap(find.byKey(const Key('food-filter-apply')));
      await tester.pumpAndSettle();
      expect(preferences.stored['me'], isEmpty);
      expect(find.text('Local p1'), findsOneWidget);
      expect(find.text('Ana'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'pedido na ficha é privado, repetido mostra existente e área separada usa nome; aprovação bloqueia avaliação',
    (tester) async {
      final owners = FakeOwnerRepository();
      final app = await pumpApp(
        tester,
        owners: owners,
        places: [place(name: 'Cozinha da Paola')],
      );
      app.router.go(Routes.placeDetail('p1'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Solicitar titularidade'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ownership-request-submit')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Pedido pendente.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('ownership-request-submit')));
      await tester.pumpAndSettle();
      expect(owners.requests['me'], hasLength(1));
      await tester.tap(find.text('Fechar'));
      app.router.go('/meus-estabelecimentos');
      await tester.pumpAndSettle();
      expect(find.text('Cozinha da Paola'), findsOneWidget);
      expect(find.text('Em análise'), findsOneWidget);
      owners.owners['p1'] = 'me';
      app.router.go(Routes.reviewFor('p1'), extra: place());
      await tester.pumpAndSettle();
      expect(find.textContaining('Como titular verificado'), findsOneWidget);
      expect(find.byKey(const Key('review-submit')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Você oferece entradas separadas para consumidor e estabelecimentos',
    (tester) async {
      final app = await pumpApp(tester);
      app.router.go(Routes.person('me'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Configurações'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Meus estabelecimentos'), 200);
      expect(find.text('Meus estabelecimentos'), findsOneWidget);
      expect(find.text('Perfil alimentar'), findsNothing);
    },
  );
}
