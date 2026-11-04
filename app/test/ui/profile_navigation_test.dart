import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/ui/settings/settings_view.dart';
import 'package:naarea/ui/review/place_picker_view.dart';
import '../support/app_harness.dart';

void main() {
  testWidgets('Avaliar lateral abre Onde Você Foi', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('feed-review')));
    await tester.pumpAndSettle();
    expect(find.byType(PlacePickerView), findsOneWidget);
    expect(find.text('Onde Você Foi?'), findsOneWidget);
  });
  testWidgets('Perfil na barra inferior abre as configurações da conta', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.byTooltip('Configurações'), findsNothing);
    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('app-nav')), findsOneWidget);
    await tester.tap(find.byTooltip('Configurações'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsView), findsOneWidget);
  });
}
