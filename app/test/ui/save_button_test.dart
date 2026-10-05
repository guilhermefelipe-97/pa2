import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/ui/core/save_button.dart';
import 'package:naarea/ui/saved/saved_places_store.dart';
import 'package:provider/provider.dart';

import '../support/fakes.dart';

Future<SavedPlacesStore> _pump(
  WidgetTester tester,
  FakeSavedRepository repo, {
  String? uid = 'me',
}) async {
  final store = SavedPlacesStore(
    authRepository: FakeAuthRepository(uid: uid),
    savedRepository: repo,
  );
  addTearDown(store.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: store,
      child: const MaterialApp(
        home: Scaffold(
          body: Center(child: SaveButton(placeId: 'mangai')),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

void main() {
  testWidgets('rótulo acessível e estado toggled', (tester) async {
    final handle = tester.ensureSemantics();
    final repo = FakeSavedRepository();
    await _pump(tester, repo);

    final empty = tester.getSemantics(
      find.bySemanticsLabel('Salvar em Quero ir'),
    );
    expect(
      empty,
      containsSemantics(
        isButton: true,
        hasToggledState: true,
        isToggled: false,
        hasTapAction: true,
      ),
    );

    await tester.tap(find.byType(SaveButton));
    await tester.pumpAndSettle();
    final full = tester.getSemantics(
      find.bySemanticsLabel('Remover de Quero ir'),
    );
    expect(full, containsSemantics(hasToggledState: true, isToggled: true));
    handle.dispose();
  });

  testWidgets(
    '1 toque: marcador cheio já, SnackBar "Salvo em Quero ir" com Desfazer',
    (tester) async {
      final repo = FakeSavedRepository()..writeGate = Completer();
      await _pump(tester, repo);

      await tester.tap(find.byType(SaveButton));
      await tester.pump();
      expect(
        find.byIcon(Icons.bookmark),
        findsOneWidget,
        reason: 'otimista, antes do servidor',
      );
      await tester.pump(const Duration(milliseconds: 750));
      expect(find.text('Salvo em Quero ir'), findsOneWidget);
      expect(find.text('Desfazer'), findsOneWidget);

      repo.writeGate!.complete();
      await tester.pumpAndSettle();
      expect(repo.byUser['me']!.containsKey('mangai'), isTrue);
    },
  );

  testWidgets('Desfazer volta ao estado anterior', (tester) async {
    final repo = FakeSavedRepository();
    final store = await _pump(tester, repo);

    await tester.tap(find.byType(SaveButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desfazer'));
    await tester.pumpAndSettle();
    expect(store.isSaved('mangai'), isFalse);
    expect(repo.byUser['me']!.containsKey('mangai'), isFalse);
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
  });

  testWidgets('remover mostra "Removido de Quero ir" com Desfazer', (
    tester,
  ) async {
    final repo = FakeSavedRepository()
      ..seed('me', 'mangai', DateTime.utc(2026, 9, 1));
    await _pump(tester, repo);
    expect(find.byIcon(Icons.bookmark), findsOneWidget);

    await tester.tap(find.byType(SaveButton));
    await tester.pumpAndSettle();
    expect(find.text('Removido de Quero ir'), findsOneWidget);
    expect(find.text('Desfazer'), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
  });

  testWidgets('falha: volta a vazio e avisa "Não foi possível salvar"', (
    tester,
  ) async {
    final repo = FakeSavedRepository()
      ..writeError = Exception('permission-denied');
    final store = await _pump(tester, repo);

    await tester.tap(find.byType(SaveButton));
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível salvar'), findsOneWidget);
    expect(store.isSaved('mangai'), isFalse);
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
  });

  testWidgets('carga inicial falhou: o toque tenta carregar de novo e salva', (
    tester,
  ) async {
    final repo = FakeSavedRepository()..listError = Exception('offline');
    final store = await _pump(tester, repo);
    expect(store.hasError, isTrue);

    repo.listError = null;
    await tester.tap(find.byType(SaveButton));
    await tester.pumpAndSettle();
    expect(store.isSaved('mangai'), isTrue);
    expect(find.text('Salvo em Quero ir'), findsOneWidget);
  });

  testWidgets('sem o store no contexto não desenha nada', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SaveButton(placeId: 'x')));
    expect(find.byType(IconButton), findsNothing);
  });

  testWidgets(
    'carga falhou e continua falhando: o toque avisa "Não foi possível salvar"',
    (tester) async {
      final repo = FakeSavedRepository()..listError = Exception('offline');
      final store = await _pump(tester, repo);

      await tester.tap(find.byType(SaveButton));
      await tester.pumpAndSettle();
      expect(find.text('Não foi possível salvar'), findsOneWidget);
      expect(store.isSaved('mangai'), isFalse);
      expect(repo.writes, isEmpty);
    },
  );

  testWidgets('sem usuário (store idle): desabilitado', (tester) async {
    await _pump(tester, FakeSavedRepository(), uid: null);
    final button = tester.widget<IconButton>(find.byType(IconButton));
    expect(button.onPressed, isNull);
  });

  testWidgets(
    'offline: "Salvo em Quero ir" aparece no toque, sem esperar o servidor',
    (tester) async {
      final repo = FakeSavedRepository()..writeGate = Completer();
      await _pump(tester, repo);
      await tester.tap(find.byType(SaveButton));
      await tester.pumpAndSettle();
      expect(find.text('Salvo em Quero ir'), findsOneWidget);
      expect(repo.inFlight['mangai'], 1, reason: 'escrita ainda pendente');
      repo.writeGate!.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('Desfazer reporta só o próprio resultado', (tester) async {
    // Salvar falharia, mas o Desfazer volta ao estado do servidor: sem erro.
    final repo = FakeSavedRepository()
      ..writeGate = Completer()
      ..writeError = Exception('permission-denied');
    final store = await _pump(tester, repo);

    await tester.tap(find.byType(SaveButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desfazer'));
    await tester.pump();
    repo.writeGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível salvar'), findsNothing);
    expect(store.isSaved('mangai'), isFalse);
  });
}
