import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/routing/routes.dart';
import '../support/app_harness.dart';
import '../support/builders.dart';
import '../support/fakes.dart';

void main() {
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
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'vegano'))
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'integral'))
            .selected,
        isTrue,
      );
      await tester.tap(find.text('Limpar filtro'));
      await tester.tap(find.text('Salvar preferências'));
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
      await tester.tap(
        find.text('Este estabelecimento é seu? Solicitar titularidade'),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Pedido pendente.'), findsOneWidget);
      await tester.tap(
        find.text('Este estabelecimento é seu? Solicitar titularidade'),
      );
      await tester.pumpAndSettle();
      expect(owners.requests['me'], hasLength(1));
      await tester.tap(find.text('Fechar'));
      app.router.go('/meus-estabelecimentos');
      await tester.pumpAndSettle();
      expect(find.text('Cozinha da Paola'), findsOneWidget);
      expect(find.textContaining('Pedido pendente'), findsOneWidget);
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
      expect(find.text('Meus estabelecimentos'), findsOneWidget);
      expect(find.text('Perfil alimentar'), findsOneWidget);
    },
  );
}
