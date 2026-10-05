import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/domain/models/place_list.dart';
import 'package:naarea/routing/routes.dart';
import 'package:naarea/ui/core/messages.dart';
import 'package:naarea/ui/lists/add_to_list_sheet.dart';
import 'package:naarea/ui/lists/list_name_form.dart';
import 'package:naarea/ui/lists/lists_store.dart';
import 'package:naarea/ui/saved/saved_places_store.dart';
import 'package:naarea/ui/saved/saved_view.dart';
import 'package:provider/provider.dart';

import '../support/app_harness.dart';
import '../support/builders.dart';
import '../support/fakes.dart';

final _catalog = <Place>[
  place(id: 'a', name: 'Mangai', neighborhood: 'Tirol'),
  place(id: 'b', name: 'Beco da Lama', neighborhood: 'Cidade Alta'),
  place(id: 'c', name: 'Camarões', neighborhood: 'Ponta Negra'),
];

FakeSavedRepository _saved() => FakeSavedRepository()
  ..seed('me', 'a', DateTime.utc(2026, 9, 28, 13))
  ..seed('me', 'b', DateTime.utc(2026, 9, 27, 15))
  ..seed('me', 'c', DateTime.utc(2026, 9, 1, 15));

Future<TestApp> _pumpSaved(
  WidgetTester tester, {
  FakeSavedRepository? saved,
  void Function(FakeListsRepository lists)? seed,
  FakePlaceRepository? placeRepository,
}) async {
  final s = saved ?? _saved();
  final lists = FakeListsRepository(saved: s);
  seed?.call(lists);
  final app = await pumpApp(
    tester,
    places: _catalog,
    placeRepository: placeRepository,
    saved: s,
    lists: lists,
    clock: () => DateTime.utc(2026, 9, 28, 15),
  );
  app.router.go(Routes.saved);
  await tester.pumpAndSettle();
  return app;
}

List<String> _cardNames(WidgetTester tester) => [
  for (final e in find.byType(SavedCard).evaluate())
    (e.widget as SavedCard).item.place.name,
];

Finder _chip(String id) => find.byKey(Key('list-chip-$id'));

Future<void> _openMenu(WidgetTester tester, String placeId) async {
  await tester.tap(find.byKey(Key('saved-menu-$placeId')));
  await tester.pumpAndSettle();
}

Future<void> _closeSheet(WidgetTester tester) async {
  await tester.tapAt(const Offset(10, 10));
  await tester.pumpAndSettle();
}

void main() {
  group('chips e filtro', () {
    testWidgets('sem listas: sem chips', (tester) async {
      await _pumpSaved(tester);
      expect(find.byType(ListChips), findsNothing);
      expect(find.byType(SavedCard), findsNWidgets(3));
    });

    testWidgets(
      'chips com contagem; filtrar mostra só a lista, mais recente primeiro',
      (tester) async {
        await _pumpSaved(
          tester,
          seed: (l) => l
            ..seed(
              'me',
              'sab',
              'Sábado com as meninas',
              emoji: '🎉',
              placeIds: ['c', 'a'],
            )
            ..seed('me', 'vazia', 'Vazia'),
        );
        expect(find.text('Todos · 3'), findsOneWidget);
        expect(find.text('🎉 Sábado com as meninas · 2'), findsOneWidget);
        expect(find.text('Vazia · 0'), findsOneWidget);

        await tester.tap(_chip('sab'));
        await tester.pumpAndSettle();
        expect(_cardNames(tester), ['Mangai', 'Camarões']);

        await tester.tap(_chip('vazia'));
        await tester.pumpAndSettle();
        expect(find.byType(SavedCard), findsNothing);
        expect(find.text('Nada nesta lista ainda'), findsOneWidget);

        await tester.tap(find.byKey(const Key('list-chip-all')));
        await tester.pumpAndSettle();
        expect(find.byType(SavedCard), findsNWidgets(3));
      },
    );

    testWidgets('renomear pelo menu do chip ativo, com as mesmas validações', (
      tester,
    ) async {
      final app = await _pumpSaved(
        tester,
        seed: (l) => l
          ..seed('me', 'sab', 'Sábado', placeIds: ['a'])
          ..seed('me', 'bar', 'Bares'),
      );
      await tester.tap(_chip('sab'));
      await tester.pumpAndSettle();
      await tester.tap(_chip('sab'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Renomear lista'));
      await tester.pumpAndSettle();

      final field = find.byKey(const Key('list-name-field'));
      expect(tester.widget<TextField>(field).controller!.text, 'Sábado');
      await tester.enterText(field, 'BARES');
      await tester.pump();
      expect(find.text(ListNameForm.takenMessage), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('list-name-submit')))
            .onPressed,
        isNull,
      );

      await tester.enterText(field, '  Sábado com as meninas ');
      await tester.tap(find.byKey(const Key('list-emoji-🎉')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('list-name-submit')));
      await tester.pumpAndSettle();

      expect(find.text('🎉 Sábado com as meninas · 1'), findsOneWidget);
      expect(app.lists.get('me', 'sab')!.name, 'Sábado com as meninas');
      expect(app.lists.get('me', 'sab')!.emoji, '🎉');
    });

    testWidgets(
      'excluir confirma, volta para "Todos" e mantém os locais no Quero ir',
      (tester) async {
        final app = await _pumpSaved(
          tester,
          seed: (l) => l.seed('me', 'sab', 'Sábado', placeIds: ['a']),
        );
        await tester.tap(_chip('sab'));
        await tester.pumpAndSettle();
        await tester.tap(_chip('sab'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Excluir lista'));
        await tester.pumpAndSettle();

        expect(find.text('Excluir lista?'), findsOneWidget);
        expect(
          find.textContaining('Os locais continuam no Quero ir'),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('confirm-delete-list')));
        await tester.pumpAndSettle();

        expect(_chip('sab'), findsNothing);
        expect(find.byType(SavedCard), findsNWidgets(3));
        expect(app.lists.get('me', 'sab'), isNull);
        expect(app.saved.byUser['me']!.keys, containsAll(['a', 'b', 'c']));
      },
    );

    testWidgets('cancelar a exclusão mantém a lista', (tester) async {
      final app = await _pumpSaved(
        tester,
        seed: (l) => l.seed('me', 'sab', 'Sábado'),
      );
      await tester.tap(_chip('sab'));
      await tester.pumpAndSettle();
      await tester.tap(_chip('sab'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Excluir lista'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(app.lists.get('me', 'sab'), isNotNull);
      expect(find.text('Sábado · 0'), findsOneWidget);
    });
  });

  group('menu do card', () {
    testWidgets(
      '"Remover do Quero ir": some de tudo num batch; Desfazer restaura tudo',
      (tester) async {
        final app = await _pumpSaved(
          tester,
          seed: (l) => l
            ..seed('me', 'l1', 'Um', placeIds: ['a'])
            ..seed('me', 'l2', 'Dois', placeIds: ['a', 'b']),
        );
        await _openMenu(tester, 'a');
        await tester.tap(find.text('Remover do Quero ir'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 750));

        expect(find.text('Removido de Quero ir e de 2 listas'), findsOneWidget);
        expect(_cardNames(tester), ['Beco da Lama', 'Camarões']);
        expect(app.lists.writes, ['removeEverywhere:a:l1,l2']);
        expect(app.saved.writes, isEmpty);
        expect(app.saved.byUser['me']!.containsKey('a'), isFalse);
        expect(app.lists.get('me', 'l2')!.placeIds, ['b']);

        await tester.tap(find.text('Desfazer'));
        await tester.pumpAndSettle();
        expect(app.saved.byUser['me']!.containsKey('a'), isTrue);
        expect(app.lists.get('me', 'l1')!.placeIds, ['a']);
        expect(app.lists.get('me', 'l2')!.placeIds, containsAll(['a', 'b']));
        expect(find.text('Um · 1'), findsOneWidget);
        expect(find.text('Dois · 2'), findsOneWidget);
      },
    );

    testWidgets('marcador também tira das listas: "e de 1 lista"', (
      tester,
    ) async {
      final app = await _pumpSaved(
        tester,
        seed: (l) => l.seed('me', 'l1', 'Um', placeIds: ['a']),
      );
      await tester.tap(find.byKey(const Key('save-a')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));
      expect(find.text('Removido de Quero ir e de 1 lista'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(app.lists.writes, ['removeEverywhere:a:l1']);
      expect(app.lists.get('me', 'l1')!.placeIds, isEmpty);
    });

    testWidgets('remover local sem listas: "Removido de Quero ir"', (
      tester,
    ) async {
      await _pumpSaved(
        tester,
        seed: (l) => l.seed('me', 'l1', 'Um', placeIds: ['b']),
      );
      await _openMenu(tester, 'a');
      await tester.tap(find.text('Remover do Quero ir'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));
      expect(find.text('Removido de Quero ir'), findsOneWidget);
    });

    testWidgets('"Adicionar a lista" abre o sheet com as listas marcáveis', (
      tester,
    ) async {
      final app = await _pumpSaved(
        tester,
        seed: (l) => l
          ..seed('me', 'l1', 'Um', placeIds: ['a'])
          ..seed('me', 'l2', 'Dois'),
      );
      await _openMenu(tester, 'a');
      await tester.tap(find.text('Adicionar a lista'));
      await tester.pumpAndSettle();

      expect(find.byType(AddToListSheet), findsOneWidget);
      CheckboxListTile tile(String id) =>
          tester.widget(find.byKey(Key('list-check-$id')));
      expect(tile('l1').value, isTrue);
      expect(tile('l2').value, isFalse);

      // Desmarcar: sai só daquela lista, continua no Quero ir.
      await tester.tap(find.byKey(const Key('list-check-l1')));
      await tester.pumpAndSettle();
      expect(tile('l1').value, isFalse);
      expect(app.lists.get('me', 'l1')!.placeIds, isEmpty);
      expect(app.saved.byUser['me']!.containsKey('a'), isTrue);

      await tester.tap(find.byKey(const Key('list-check-l2')));
      await tester.pumpAndSettle();
      expect(app.lists.get('me', 'l2')!.placeIds, ['a']);

      await _closeSheet(tester);
      expect(find.text('Dois · 1'), findsOneWidget);
    });
  });

  group('sheet "Adicionar a lista"', () {
    Future<TestApp> openSheet(
      WidgetTester tester, {
      void Function(FakeListsRepository lists)? seed,
    }) async {
      final app = await _pumpSaved(tester, seed: seed);
      await _openMenu(tester, 'a');
      await tester.tap(find.text('Adicionar a lista'));
      await tester.pumpAndSettle();
      return app;
    }

    FilledButton submit(WidgetTester tester) =>
        tester.widget(find.byKey(const Key('list-name-submit')));

    testWidgets('"Nova lista": vazio/41+ desabilita, com contador', (
      tester,
    ) async {
      await openSheet(tester);
      await tester.tap(find.byKey(const Key('new-list')));
      await tester.pumpAndSettle();

      expect(submit(tester).onPressed, isNull);
      expect(find.text('0/40'), findsOneWidget);

      final field = find.byKey(const Key('list-name-field'));
      await tester.enterText(field, 'a' * 41);
      await tester.pump();
      expect(find.text('41/40'), findsOneWidget);
      expect(submit(tester).onPressed, isNull);

      await tester.enterText(field, '   ');
      await tester.pump();
      expect(submit(tester).onPressed, isNull);

      await tester.enterText(field, 'a' * 40);
      await tester.pump();
      expect(find.text('40/40'), findsOneWidget);
      expect(submit(tester).onPressed, isNotNull);
    });

    testWidgets('nome repetido sem caixa/acento é bloqueado', (tester) async {
      await openSheet(
        tester,
        seed: (l) => l.seed('me', 'sab', 'Sábado com as meninas'),
      );
      await tester.tap(find.byKey(const Key('new-list')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('list-name-field')),
        'sabado com as meninas',
      );
      await tester.pump();
      expect(find.text(ListNameForm.takenMessage), findsOneWidget);
      expect(submit(tester).onPressed, isNull);
    });

    testWidgets('criar: aparada, com emoji, já marcada', (tester) async {
      final app = await openSheet(tester);
      await tester.tap(find.byKey(const Key('new-list')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('list-name-field')),
        '  Sábado com as meninas ',
      );
      await tester.tap(find.byKey(const Key('list-emoji-🎉')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('list-name-submit')));
      await tester.pumpAndSettle();

      final stored = app.lists.byUser['me']!.values.single;
      expect(stored.name, 'Sábado com as meninas');
      expect(stored.emoji, '🎉');
      expect(stored.placeIds, ['a']);
      final tile = tester.widget<CheckboxListTile>(
        find.byKey(Key('list-check-${stored.id}')),
      );
      expect(tile.value, isTrue);
      expect(find.text('🎉 Sábado com as meninas'), findsOneWidget);
    });

    testWidgets('30 listas: "Nova lista" desabilitado com aviso', (
      tester,
    ) async {
      await openSheet(
        tester,
        seed: (l) {
          for (var i = 0; i < PlaceList.maxLists; i++) {
            l.seed('me', 'l$i', 'Lista $i');
          }
        },
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('new-list')),
        200,
        scrollable: find
            .descendant(
              of: find.byType(AddToListSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      final tile = tester.widget<ListTile>(find.byKey(const Key('new-list')));
      expect(tile.enabled, isFalse);
      expect(find.text(AddToListSheet.limitMessage), findsOneWidget);
    });

    testWidgets('lista com 200 locais: marcar desabilitado', (tester) async {
      await openSheet(
        tester,
        seed: (l) {
          // Salvos: membro não salvo seria limpo pela reconciliação.
          for (var i = 0; i < 200; i++) {
            l.saved!.seed('me', 'p$i', DateTime.utc(2026, 9, 1));
          }
          l.seed(
            'me',
            'cheia',
            'Cheia',
            placeIds: [for (var i = 0; i < 200; i++) 'p$i'],
          );
        },
      );
      final tile = tester.widget<CheckboxListTile>(
        find.byKey(const Key('list-check-cheia')),
      );
      expect(tile.onChanged, isNull);
      expect(find.text('Lista cheia (200 locais)'), findsOneWidget);
    });

    testWidgets('falha ao marcar: reverte e "Não foi possível salvar"', (
      tester,
    ) async {
      final app = await openSheet(
        tester,
        seed: (l) => l.seed('me', 'l1', 'Um'),
      );
      app.lists.failWhen = (op) => op.startsWith('add:');
      await tester.tap(find.byKey(const Key('list-check-l1')));
      await tester.pumpAndSettle();
      expect(find.text('Não foi possível salvar'), findsOneWidget);
      final tile = tester.widget<CheckboxListTile>(
        find.byKey(const Key('list-check-l1')),
      );
      expect(tile.value, isFalse);
      // O local já estava salvo: continua.
      expect(app.saved.byUser['me']!.containsKey('a'), isTrue);
    });
  });

  group('revisão', () {
    testWidgets('contagens só dos cards visíveis (locais resolvidos)', (
      tester,
    ) async {
      final saved = _saved()..seed('me', 'z', DateTime.utc(2026, 9, 28, 14));
      await _pumpSaved(
        tester,
        saved: saved,
        seed: (l) => l.seed('me', 'l', 'Lista', placeIds: ['a', 'z']),
      );
      expect(find.byType(SavedCard), findsNWidgets(3));
      expect(find.text('Todos · 3'), findsOneWidget);
      expect(find.text('Lista · 1'), findsOneWidget);
    });

    testWidgets(
      'lista com local ainda sem dados do catálogo: carregando, não "Nada '
      'nesta lista ainda"',
      (tester) async {
        final places = FakePlaceRepository([
          ..._catalog,
          place(id: 'd', name: 'Novo'),
        ]);
        final app = await _pumpSaved(
          tester,
          placeRepository: places,
          seed: (l) => l.seed('me', 'l', 'Lista'),
        );
        places.getGate = Completer();
        await app.listsStore(tester).setMembership('l', 'd', true);
        await tester.pump();
        await tester.tap(_chip('l'));
        await tester.pump();
        expect(find.text('Nada nesta lista ainda'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        places.getGate!.complete();
        await tester.pumpAndSettle();
        expect(_cardNames(tester), ['Novo']);
      },
    );

    testWidgets(
      'erro ao carregar listas: banner, sem chips; puxar para atualizar traz '
      'os chips',
      (tester) async {
        final app = await _pumpSaved(
          tester,
          seed: (l) => l
            ..seed('me', 'l', 'Lista', placeIds: ['a'])
            ..listError = Exception('network'),
        );
        expect(find.byType(ListChips), findsNothing);
        expect(
          find.text('Não foi possível carregar suas listas'),
          findsOneWidget,
        );
        expect(find.byType(SavedCard), findsNWidgets(3));

        app.lists.listError = null;
        await tester.fling(
          find.byType(SavedCard).first,
          const Offset(0, 400),
          1000,
        );
        await tester.pumpAndSettle();
        expect(find.byType(ListChips), findsOneWidget);
        expect(find.text('Lista · 1'), findsOneWidget);
        expect(
          find.text('Não foi possível carregar suas listas'),
          findsNothing,
        );
      },
    );

    testWidgets('banner "Tentar de novo" recarrega as listas', (tester) async {
      final app = await _pumpSaved(
        tester,
        seed: (l) => l
          ..seed('me', 'l', 'Lista')
          ..listError = Exception('network'),
      );
      app.lists.listError = null;
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('lists-error-banner')),
          matching: find.text('Tentar de novo'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Lista · 0'), findsOneWidget);
    });

    testWidgets('renomear falhou: aviso e o chip volta ao nome anterior', (
      tester,
    ) async {
      final app = await _pumpSaved(
        tester,
        seed: (l) => l.seed('me', 'l', 'Lista'),
      );
      app.lists.writeError = Exception('permission-denied');
      await tester.tap(_chip('l'));
      await tester.pumpAndSettle();
      await tester.tap(_chip('l'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Renomear lista'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('list-name-field')), 'Outra');
      await tester.pump();
      await tester.tap(find.byKey(const Key('list-name-submit')));
      await tester.pumpAndSettle();
      expect(find.text(saveFailureMessage), findsOneWidget);
      expect(find.text('Lista · 0'), findsOneWidget);
      expect(find.textContaining('Outra'), findsNothing);
    });

    testWidgets('excluir falhou: aviso, a lista volta e continua selecionada', (
      tester,
    ) async {
      final app = await _pumpSaved(
        tester,
        seed: (l) => l.seed('me', 'l', 'Lista', placeIds: ['a']),
      );
      app.lists.writeError = Exception('permission-denied');
      await tester.tap(_chip('l'));
      await tester.pumpAndSettle();
      await tester.tap(_chip('l'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Excluir lista'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-delete-list')));
      await tester.pumpAndSettle();
      expect(find.text(saveFailureMessage), findsOneWidget);
      expect(_chip('l'), findsOneWidget);
      expect(_cardNames(tester), ['Mangai'], reason: 'filtro de volta');
      final all = tester.widget<ChoiceChip>(
        find.byKey(const Key('list-chip-all')),
      );
      expect(all.selected, isFalse);
    });

    testWidgets('chip ativo é um botão de menu acessível', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpSaved(tester, seed: (l) => l.seed('me', 'l', 'Lista'));
      await tester.tap(_chip('l'));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.bySemanticsLabel('Opções da lista Lista')),
        containsSemantics(isButton: true, hasTapAction: true),
      );
      handle.dispose();
    });

    testWidgets(
      'SnackBar de salvar com listas: "Adicionar a lista" é a action e o '
      '"Desfazer" acessível desfaz sem aviso de falha',
      (tester) async {
        final handle = tester.ensureSemantics();
        final app = await _pumpSaved(
          tester,
          saved: FakeSavedRepository(),
          seed: (l) => l.seed('me', 'l', 'Lista'),
        );
        app.router.go(Routes.placeDetail('a'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('save-a')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 750));

        final bar = tester.widget<SnackBar>(find.byType(SnackBar));
        expect(bar.action!.label, 'Adicionar a lista');
        expect(
          tester.getSemantics(find.bySemanticsLabel('Desfazer')),
          containsSemantics(isButton: true, hasTapAction: true),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(app.saved.byUser['me']!.containsKey('a'), isTrue);

        await tester.tap(find.byKey(const Key('snackbar-undo')));
        await tester.pumpAndSettle();
        expect(app.store(tester).isSaved('a'), isFalse);
        expect(app.saved.byUser['me']!.containsKey('a'), isFalse);
        expect(find.text(saveFailureMessage), findsNothing);
        handle.dispose();
      },
    );

    testWidgets(
      '"Desfazer" com falha parcial: "Não foi possível restaurar todas as '
      'listas"',
      (tester) async {
        final app = await _pumpSaved(
          tester,
          seed: (l) => l
            ..seed('me', 'l1', 'Um', placeIds: ['a'])
            ..seed('me', 'l2', 'Dois', placeIds: ['a']),
        );
        await _openMenu(tester, 'a');
        await tester.tap(find.text('Remover do Quero ir'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 750));
        app.lists.failWhen = (op) => op == 'add:l2:a';
        await tester.tap(find.text('Desfazer'));
        await tester.pumpAndSettle();
        expect(find.text(restoreListsFailureMessage), findsOneWidget);
        expect(app.saved.byUser['me']!.containsKey('a'), isTrue);
        expect(app.lists.get('me', 'l1')!.placeIds, ['a']);
      },
    );

    testWidgets('sheet sem usuário: "Entre para usar listas"', (tester) async {
      final auth = FakeAuthRepository();
      final saved = SavedPlacesStore(
        authRepository: auth,
        savedRepository: FakeSavedRepository(),
      );
      final lists = ListsStore(
        authRepository: auth,
        listsRepository: FakeListsRepository(),
        savedStore: saved,
      );
      addTearDown(() {
        lists.dispose();
        saved.dispose();
      });
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: saved),
            ChangeNotifierProvider.value(value: lists),
          ],
          child: const MaterialApp(
            home: Scaffold(body: AddToListSheet(placeId: 'a')),
          ),
        ),
      );
      await tester.pump();
      expect(find.text(AddToListSheet.signedOutMessage), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
