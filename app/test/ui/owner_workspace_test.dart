import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/data/repositories/owner_repository.dart';
import 'package:naarea/data/repositories/owner_workspace_repository.dart';
import 'package:naarea/routing/routes.dart';
import 'package:naarea/ui/core/theme.dart';
import '../support/app_harness.dart';
import '../support/builders.dart';
import '../support/fakes.dart';
import '../support/owner_workspace_fake.dart';

Future<void> showSave(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byKey(const Key('save-place-presentation')),
    180,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(find.byKey(const Key('save-place-presentation')));
}

void main() {
  FakeOwnerRepository owner() => FakeOwnerRepository()
    ..owners['p1'] = 'me'
    ..requests['me'] = [const OwnershipRequest('p1', 'approved')];
  testWidgets(
    'titular edita apresentação e horários; falha mantém rascunho; ficha lê o salvo',
    (tester) async {
      final workspace = FakeOwnerWorkspace();
      final app = await pumpApp(
        tester,
        places: [place()],
        owners: owner(),
        ownerWorkspace: workspace,
      );
      app.router.go('/meus-estabelecimentos');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('place-description')),
        'Café artesanal e acolhedor.',
      );
      await tester.enterText(
        find.byKey(const Key('place-public-hours')),
        'Terça a domingo, 12h–22h.',
      );
      workspace.failSave = true;
      await showSave(tester);
      await tester.tap(find.byKey(const Key('save-place-presentation')));
      await tester.pumpAndSettle();
      expect(workspace.saves, 0);
      expect(find.textContaining('Seus textos foram mantidos'), findsOneWidget);
      workspace.failSave = false;
      await showSave(tester);
      await tester.tap(find.byKey(const Key('save-place-presentation')));
      await tester.pumpAndSettle();
      expect(
        workspace.values['p1']!.description,
        'Café artesanal e acolhedor.',
      );
      Navigator.of(
        tester.element(find.byKey(const Key('save-place-presentation'))),
      ).pop();
      await tester.pumpAndSettle();
      app.router.go(Routes.placeDetail('p1'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Sobre o local'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Café artesanal e acolhedor.'), findsOneWidget);
      expect(find.text('Terça a domingo, 12h–22h.'), findsOneWidget);
    },
  );
  testWidgets('revogação durante edição impede salvar', (tester) async {
    final owners = owner();
    final workspace = FakeOwnerWorkspace();
    final app = await pumpApp(
      tester,
      places: [place()],
      owners: owners,
      ownerWorkspace: workspace,
    );
    app.router.go('/meus-estabelecimentos');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('place-description')),
      'Rascunho',
    );
    owners.owners.clear();
    await showSave(tester);
    await tester.tap(find.byKey(const Key('save-place-presentation')));
    await tester.pumpAndSettle();
    expect(workspace.saves, 0);
    expect(find.textContaining('A titularidade mudou'), findsOneWidget);
  });
  testWidgets(
    'pedido pendente só acompanha; nunca recebe controles de titular',
    (tester) async {
      final owners = FakeOwnerRepository()
        ..requests['me'] = [const OwnershipRequest('p1', 'pending')];
      final app = await pumpApp(tester, places: [place()], owners: owners);
      app.router.go('/meus-estabelecimentos');
      await tester.pumpAndSettle();
      expect(find.text('Editar'), findsNothing);
      expect(find.text('Responder'), findsNothing);
      await tester.tap(find.byTooltip('Acompanhar pedido'));
      await tester.pumpAndSettle();
      expect(find.text('Acompanhar solicitação'), findsOneWidget);
      expect(find.textContaining('Etapa'), findsNothing);
    },
  );
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'painel em 320dp e fonte $scale; contagem indisponível não vira zero',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final workspace = FakeOwnerWorkspace()..failSummary = true;
        final app = await pumpApp(
          tester,
          places: [place()],
          owners: owner(),
          ownerWorkspace: workspace,
          theme: AppTheme.light(),
          textScale: scale,
        );
        app.router.go('/meus-estabelecimentos');
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Responder'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Responder'), findsOneWidget);
        expect(find.text('Responder (0)'), findsNothing);
        expect(find.text('Respostas em dia'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'painel mostra pendências e média reais fornecidas pelo repositório',
    (tester) async {
      final workspace = FakeOwnerWorkspace()
        ..summaries['p1'] = const OwnerPlaceSummary(
          reviews: 27,
          unanswered: 23,
          rating: 4.6,
        );
      final app = await pumpApp(
        tester,
        places: [place()],
        owners: owner(),
        ownerWorkspace: workspace,
      );
      app.router.go('/meus-estabelecimentos');
      await tester.pumpAndSettle();
      expect(find.text('23 avaliações pendentes'), findsOneWidget);
      expect(find.text('Responder (23)'), findsOneWidget);
      expect(find.text('★ 4.6'), findsOneWidget);
    },
  );
}
