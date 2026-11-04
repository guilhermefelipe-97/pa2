import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/routing/routes.dart';
import 'package:naarea/ui/core/naarea_footer.dart';
import '../support/app_harness.dart';

void main() {
  testWidgets('rodapé em duas linhas somente em Configurações', (tester) async {
    final app = await pumpApp(tester);
    expect(find.byType(NaAreaFooter), findsNothing);
    app.router.go(Routes.settings);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byType(NaAreaFooter), 200);
    final footer = find.byType(NaAreaFooter);
    final brand = find.descendant(of: footer, matching: find.text('NaÁrea'));
    final rights = find.text('© 2026. Todos os direitos reservados.');
    expect(brand, findsOneWidget);
    expect(rights, findsOneWidget);
    expect(tester.getTopLeft(brand).dy, lessThan(tester.getTopLeft(rights).dy));
    app.router.go(Routes.nearby);
    await tester.pumpAndSettle();
    expect(find.byType(NaAreaFooter), findsNothing);
  });
}
