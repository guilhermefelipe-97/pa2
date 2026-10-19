import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/domain/models/place_list.dart';
import 'package:naarea/routing/routes.dart';
import 'package:naarea/ui/core/follow_events.dart';
import 'package:naarea/ui/core/messages.dart';
import 'package:naarea/ui/lists/person_list_view.dart';
import 'package:naarea/ui/lists/person_list_view_model.dart';
import 'package:naarea/ui/profile/profile_view.dart';
import 'package:naarea/ui/profile/profile_view_model.dart';
import 'package:naarea/ui/saved/saved_view.dart';

import '../support/app_harness.dart';
import '../support/builders.dart';
import '../support/fakes.dart';

final _catalog = <Place>[
  place(id: 'a', name: 'Mangai', neighborhood: 'Tirol'),
  place(id: 'b', name: 'Beco da Lama', neighborhood: 'Cidade Alta'),
  place(id: 'c', name: 'Camarões', neighborhood: 'Ponta Negra'),
];

/// Bianca ("me") segue Ana; a lista "Sábado" de Ana está visível.
({
  FakeUserRepository users,
  FakeSavedRepository saved,
  FakeListsRepository lists,
})
_world({bool follows = true, bool visible = true}) {
  final users = FakeUserRepository()
    ..addUser('me', 'Bianca')
    ..addUser('ana', 'Ana');
  if (follows) users.followingByUser['me'] = {'ana'};
  final saved = FakeSavedRepository()
    // Bianca já tinha o Mangai.
    ..seed('me', 'a', DateTime.utc(2026, 9, 20, 15));
  final lists = FakeListsRepository(saved: saved)
    ..users = users
    ..seed(
      'ana',
      'sab',
      'Sábado',
      emoji: '🎉',
      placeIds: ['a', 'b', 'c'],
      visible: visible,
    )
    ..seed('ana', 'privada', 'Só minha', placeIds: ['a']);
  return (users: users, saved: saved, lists: lists);
}

Future<TestApp> _pump(
  WidgetTester tester, {
  bool follows = true,
  bool visible = true,
  void Function(FakeListsRepository lists)? seed,
}) async {
  final w = _world(follows: follows, visible: visible);
  seed?.call(w.lists);
  return pumpApp(
    tester,
    users: w.users,
    saved: w.saved,
    lists: w.lists,
    places: _catalog,
    clock: () => DateTime.utc(2026, 9, 28, 15),
  );
}

Finder _chip(String id) => find.byKey(Key('list-chip-$id'));

Future<void> _openChipMenu(WidgetTester tester, String listId) async {
  await tester.tap(_chip(listId));
  await tester.pumpAndSettle();
  await tester.tap(_chip(listId));
  await tester.pumpAndSettle();
}

void main() {
  group('ProfileViewModel: listas visíveis (F13)', () {
    ProfileViewModel vm(
      ({
        FakeUserRepository users,
        FakeSavedRepository saved,
        FakeListsRepository lists,
      })
      w, {
      String uid = 'ana',
      String me = 'me',
    }) => ProfileViewModel(
      uid: uid,
      authRepository: FakeAuthRepository(uid: me),
      userRepository: w.users,
      reviewRepository: FakeReviewRepository(),
      followEvents: FollowEvents(),
      visitRepository: FakeVisitRepository(),
      listsRepository: w.lists,
    );

    test('quem segue vê só as visíveis', () async {
      final w = _world();
      final v = vm(w);
      await v.load();
      await pumpEventQueue();
      expect(v.lists.map((l) => l.id), ['sab']);
    });

    test('quem não segue: seção oculta, sem consultar', () async {
      final w = _world(follows: false);
      final v = vm(w);
      await v.load();
      await pumpEventQueue();
      expect(v.lists, isEmpty);
      expect(w.lists.visibleListsCalls, isEmpty);
    });

    test('falha na leitura: seção oculta, perfil carrega', () async {
      final w = _world();
      w.lists.visibleListsError = Exception('permission-denied');
      final v = vm(w);
      await v.load();
      await pumpEventQueue();
      expect(v.state, ProfileState.ready);
      expect(v.lists, isEmpty);
    });

    test('perfil próprio: sem a seção', () async {
      final w = _world();
      final v = vm(w, uid: 'ana', me: 'ana');
      await v.load();
      await pumpEventQueue();
      expect(v.lists, isEmpty);
    });

    test(
      'passar a seguir mostra as listas; deixar de seguir esconde',
      () async {
        final w = _world(follows: false);
        final v = vm(w);
        await v.load();
        await v.toggleFollow();
        await pumpEventQueue();
        expect(v.lists.map((l) => l.id), ['sab']);
        await v.toggleFollow();
        await pumpEventQueue();
        expect(v.lists, isEmpty);
      },
    );
  });

  group('perfil → lista → copiar (F13)', () {
    testWidgets(
      'Bianca copia "Sábado" de Ana: chip "Copiada de Ana", todos os locais '
      'salvos e Ana vê "Copiada 1 vez"',
      (tester) async {
        final app = await _pump(tester);
        app.router.push(Routes.person('ana'));
        await tester.pumpAndSettle();

        // Seção "Listas": só a visível, com emoji, nome e quantos locais.
        expect(find.byKey(const Key('profile-lists')), findsOneWidget);
        expect(find.text('Sábado'), findsOneWidget);
        expect(find.text('3 locais'), findsOneWidget);
        expect(find.text('Só minha'), findsNothing);

        await tester.tap(find.byKey(const ValueKey('profile-list-sab')));
        await tester.pumpAndSettle();
        expect(find.byType(PersonListView), findsOneWidget);
        expect(find.text('Lista de Ana'), findsOneWidget);
        for (final id in ['a', 'b', 'c']) {
          expect(find.byKey(ValueKey('person-list-place-$id')), findsOneWidget);
        }

        await tester.tap(find.byKey(const Key('person-list-copy')));
        await tester.pumpAndSettle();
        expect(find.text(PersonListViewModel.copiedText), findsOneWidget);
        final newId = app.lists.byUser['me']!.keys.single;
        final copy = app.lists.get('me', newId)!;
        expect(copy.name, 'Sábado');
        expect(copy.emoji, '🎉');
        expect(copy.placeIds, ['a', 'b', 'c']);
        expect(copy.copiedFrom!.name, 'Ana');
        expect(app.saved.byUser['me']!.keys, containsAll(['a', 'b', 'c']));

        // "Ver": abre o Quero ir com o chip da lista copiada.
        await tester.tap(find.text('Ver'));
        await tester.pumpAndSettle();
        expect(find.byType(SavedView), findsOneWidget);
        expect(find.text('🎉 Sábado · 3'), findsOneWidget);
        await tester.tap(_chip(newId));
        await tester.pumpAndSettle();
        expect(find.text('Copiada de Ana'), findsOneWidget);
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();

        // Ana entra e vê o contador no menu da lista dela.
        expect(app.lists.copies['ana/sab'], {'me'});
        app.auth.restoreSession('ana');
        await tester.pumpAndSettle();
        app.router.go(Routes.saved);
        await tester.pumpAndSettle();
        await _openChipMenu(tester, 'sab');
        expect(find.text('Copiada 1 vez'), findsOneWidget);
      },
    );

    testWidgets('não segue a dona: seção "Listas" oculta', (tester) async {
      final app = await _pump(tester, follows: false);
      app.router.push(Routes.person('ana'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileView), findsOneWidget);
      expect(find.byKey(const Key('profile-lists')), findsNothing);
    });

    testWidgets('lista que não está visível: "não está disponível"', (
      tester,
    ) async {
      final app = await _pump(tester);
      app.router.push(Routes.personList('ana', 'privada'));
      await tester.pumpAndSettle();
      expect(find.text(PersonListViewModel.notFoundText), findsOneWidget);
      expect(find.byKey(const Key('person-list-copy')), findsNothing);
    });

    testWidgets(
      'link direto de quem não segue (ou deixou de seguir): "não está '
      'disponível", sem "Tentar de novo"',
      (tester) async {
        final app = await _pump(tester, follows: false);
        app.router.push(Routes.personList('ana', 'sab'));
        await tester.pumpAndSettle();
        expect(find.text(PersonListViewModel.notFoundText), findsOneWidget);
        expect(find.text(PersonListViewModel.loadErrorText), findsNothing);
        expect(find.text('Tentar de novo'), findsNothing);
        expect(find.byKey(const Key('person-list-copy')), findsNothing);
      },
    );

    testWidgets('erro de rede continua "Tentar de novo"', (tester) async {
      final app = await _pump(tester);
      app.lists.visibleListsError = Exception('unavailable');
      app.router.push(Routes.personList('ana', 'sab'));
      await tester.pumpAndSettle();
      expect(find.text(PersonListViewModel.loadErrorText), findsOneWidget);
      app.lists.visibleListsError = null;
      await tester.tap(find.text('Tentar de novo'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('person-list-copy')), findsOneWidget);
    });

    testWidgets(
      'suas listas carregando ou com falha: botão desabilitado com o motivo',
      (tester) async {
        final w = _world();
        w.lists.listGate = Completer<void>();
        final app = await pumpApp(
          tester,
          users: w.users,
          saved: w.saved,
          lists: w.lists,
          places: _catalog,
        );
        app.router.push(Routes.personList('ana', 'sab'));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        ButtonStyleButton copyButton() => tester.widget<ButtonStyleButton>(
          find.byKey(const Key('person-list-copy')),
        );
        expect(copyButton().onPressed, isNull);
        expect(find.text(PersonListViewModel.listsLoadingText), findsOneWidget);

        // A leitura falha: motivo e "Tentar de novo".
        w.lists.listError = Exception('unavailable');
        w.lists.listGate!.complete();
        w.lists.listGate = null;
        await tester.pumpAndSettle();
        expect(copyButton().onPressed, isNull);
        expect(find.text(PersonListViewModel.listsLoadingText), findsNothing);
        expect(find.text(PersonListViewModel.listsFailedText), findsOneWidget);

        w.lists.listError = null;
        await tester.tap(
          find.descendant(
            of: find.byKey(const Key('person-list-lists-failed')),
            matching: find.text('Tentar de novo'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(PersonListViewModel.listsFailedText), findsNothing);
        expect(copyButton().onPressed, isNotNull);
      },
    );

    testWidgets(
      'copia só os locais que a tela mostrou e avisa "N de M locais"',
      (tester) async {
        final app = await _pump(
          tester,
          seed: (l) => l.seed(
            'ana',
            'sab',
            'Sábado',
            emoji: '🎉',
            // "sumiu" não está no catálogo: a tela não mostra.
            placeIds: ['a', 'b', 'sumiu'],
            visible: true,
          ),
        );
        app.router.push(Routes.personList('ana', 'sab'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('person-list-place-sumiu')),
          findsNothing,
        );
        await tester.tap(find.byKey(const Key('person-list-copy')));
        await tester.pumpAndSettle();
        expect(find.text('Lista copiada (2 de 3 locais)'), findsOneWidget);
        final copy = app.lists.byUser['me']!.values.single;
        expect(copy.placeIds, ['a', 'b']);
        expect(app.saved.byUser['me']!.keys, isNot(contains('sumiu')));
      },
    );

    testWidgets('local que não salvou fica de fora e entra na contagem', (
      tester,
    ) async {
      final app = await _pump(tester);
      app.saved.failSaveIds.add('c');
      app.router.push(Routes.personList('ana', 'sab'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('person-list-copy')));
      await tester.pumpAndSettle();
      expect(find.text('Lista copiada (2 de 3 locais)'), findsOneWidget);
    });

    testWidgets(
      'Quero ir já aberto (em "Todos"): copiar e "Ver" ativa o chip da cópia',
      (tester) async {
        final app = await _pump(
          tester,
          seed: (l) => l.seed('me', 'minha', 'Minha', placeIds: ['a']),
        );
        // A aba fica viva antes, com outro chip ativo.
        app.router.go(Routes.saved);
        await tester.pumpAndSettle();
        await tester.tap(_chip('minha'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('list-chip-all')));
        await tester.pumpAndSettle();

        app.router.push(Routes.person('ana'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('profile-list-sab')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('person-list-copy')));
        await tester.pumpAndSettle();
        final newId = app.lists.byUser['me']!.keys.firstWhere(
          (id) => id != 'minha',
        );
        await tester.tap(find.text('Ver'));
        await tester.pumpAndSettle();

        expect(find.byType(SavedView), findsOneWidget);
        expect(tester.widget<ChoiceChip>(_chip(newId)).selected, isTrue);
        expect(
          tester
              .widget<ChoiceChip>(find.byKey(const Key('list-chip-all')))
              .selected,
          isFalse,
        );
        expect(tester.widget<ChoiceChip>(_chip('minha')).selected, isFalse);
      },
    );

    testWidgets('pedido de foco para lista que não existe é ignorado', (
      tester,
    ) async {
      final app = await _pump(
        tester,
        seed: (l) => l.seed('me', 'minha', 'Minha', placeIds: ['a']),
      );
      app.router.go(Routes.saved);
      await tester.pumpAndSettle();
      await tester.tap(_chip('minha'));
      await tester.pumpAndSettle();
      // Ex.: "Ver" de uma cópia que foi excluída nesse meio-tempo.
      app.listsStore(tester).focusList('fantasma');
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(_chip('minha')).selected, isTrue);
      expect(find.text('Mangai'), findsOneWidget);
    });

    testWidgets('30 listas: "Copiar lista" desabilitado com aviso', (
      tester,
    ) async {
      final app = await _pump(
        tester,
        seed: (l) {
          for (var i = 0; i < PlaceList.maxLists; i++) {
            l.seed('me', 'l$i', 'Lista $i');
          }
        },
      );
      app.router.push(Routes.personList('ana', 'sab'));
      await tester.pumpAndSettle();
      final button = tester.widget<ButtonStyleButton>(
        find.byKey(const Key('person-list-copy')),
      );
      expect(button.onPressed, isNull);
      expect(find.byKey(const Key('person-list-limit')), findsOneWidget);
    });

    testWidgets('falha ao gravar a lista: avisa e desfaz os salvamentos', (
      tester,
    ) async {
      final app = await _pump(tester);
      app.lists.failWhen = (op) => op.startsWith('create:');
      app.router.push(Routes.personList('ana', 'sab'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('person-list-copy')));
      await tester.pumpAndSettle();
      expect(find.text(PersonListViewModel.copyFailedText), findsOneWidget);
      expect(app.saved.byUser['me']!.keys, ['a']);
      expect(app.lists.byUser['me'], isNull);
      expect(app.lists.copies, isEmpty);
    });
  });

  group('menu do chip (F13)', () {
    testWidgets(
      '"Visível para quem me segue": legenda da AppBar muda; desmarcar volta',
      (tester) async {
        final app = await _pump(
          tester,
          seed: (l) => l.seed('me', 'minha', 'Minha', placeIds: ['a']),
        );
        app.router.go(Routes.saved);
        await tester.pumpAndSettle();
        expect(find.text(SavedView.privateCaption), findsOneWidget);

        await _openChipMenu(tester, 'minha');
        await tester.tap(find.text(visibleToFollowersLabel));
        await tester.pumpAndSettle();
        expect(find.text(SavedView.visibleCaption), findsOneWidget);
        expect(app.lists.get('me', 'minha')!.visible, isTrue);

        // "Todos" é sempre privado.
        await tester.tap(find.byKey(const Key('list-chip-all')));
        await tester.pumpAndSettle();
        expect(find.text(SavedView.privateCaption), findsOneWidget);

        await _openChipMenu(tester, 'minha');
        await tester.tap(find.text(visibleToFollowersLabel));
        await tester.pumpAndSettle();
        expect(find.text(SavedView.privateCaption), findsOneWidget);
        expect(app.lists.get('me', 'minha')!.visible, isFalse);
      },
    );

    testWidgets('falha ao tornar visível: reverte e avisa', (tester) async {
      final app = await _pump(
        tester,
        seed: (l) => l.seed('me', 'minha', 'Minha'),
      );
      app.router.go(Routes.saved);
      await tester.pumpAndSettle();
      app.lists.writeError = Exception('permission-denied');
      await _openChipMenu(tester, 'minha');
      await tester.tap(find.text(visibleToFollowersLabel));
      await tester.pumpAndSettle();
      expect(find.text(saveFailureMessage), findsOneWidget);
      expect(find.text(SavedView.privateCaption), findsOneWidget);
      expect(app.lists.get('me', 'minha')!.visible, isFalse);
    });

    testWidgets('"Copiada de Ana" abre o perfil dela', (tester) async {
      final app = await _pump(
        tester,
        seed: (l) => l.seed(
          'me',
          'copia',
          'Sábado',
          placeIds: ['a'],
          copiedFrom: const ListCredit(uid: 'ana', name: 'Ana', listId: 'sab'),
        ),
      );
      app.router.go(Routes.saved);
      await tester.pumpAndSettle();
      await _openChipMenu(tester, 'copia');
      await tester.tap(find.byKey(const Key('list-credit')));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileView), findsOneWidget);
      expect(find.text('Ana'), findsWidgets);
    });

    testWidgets('lista sem crédito não mostra "Copiada de"', (tester) async {
      final app = await _pump(
        tester,
        seed: (l) => l.seed('me', 'minha', 'Minha'),
      );
      app.router.go(Routes.saved);
      await tester.pumpAndSettle();
      await _openChipMenu(tester, 'minha');
      expect(find.byKey(const Key('list-credit')), findsNothing);
    });

    for (final (n, label) in [(3, 'Copiada 3 vezes'), (1, 'Copiada 1 vez')]) {
      testWidgets('contador: "$label"', (tester) async {
        final app = await _pump(
          tester,
          seed: (l) =>
              l.copies['me/minha'] = {for (var i = 0; i < n; i++) 'u$i'},
        );
        app.lists.seed('me', 'minha', 'Minha', visible: true);
        await app.listsStore(tester).reload();
        app.router.go(Routes.saved);
        await tester.pumpAndSettle();
        await _openChipMenu(tester, 'minha');
        expect(find.text(label), findsOneWidget);
      });
    }

    testWidgets(
      'trocar a lista do chip ativo não mostra o contador da anterior',
      (tester) async {
        final app = await _pump(
          tester,
          seed: (l) {
            l
              ..seed('me', 'velha', 'Velha', visible: true)
              ..seed('me', 'nova', 'Nova', visible: true)
              ..copies['me/velha'] = {'u1', 'u2', 'u3'};
          },
        );
        app.router.go(Routes.saved);
        await tester.pumpAndSettle();
        await _openChipMenu(tester, 'velha');
        expect(find.text('Copiada 3 vezes'), findsOneWidget);
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();

        // "Velha" sai e "Nova" vira a ativa na MESMA posição (o estado do
        // chip ativo é reaproveitado com outra lista).
        final store = app.listsStore(tester);
        app.lists.writeGate = Completer<void>();
        unawaited(store.delete('velha'));
        store.focusList('nova');
        await tester.pump();
        app.lists.copyCountGate = Completer<void>();
        await tester.tap(_chip('nova'));
        await tester.pump();
        await tester.pump();
        expect(find.text('Copiada 3 vezes'), findsNothing);
        expect(find.byKey(const Key('list-copies')), findsNothing);

        app.lists.copyCountGate!.complete();
        app.lists.writeGate!.complete();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('list-copies')), findsNothing);
      },
    );

    testWidgets('contador zero ou com falha: oculto', (tester) async {
      final app = await _pump(
        tester,
        seed: (l) => l.seed('me', 'minha', 'Minha'),
      );
      app.router.go(Routes.saved);
      await tester.pumpAndSettle();
      await _openChipMenu(tester, 'minha');
      expect(find.byKey(const Key('list-copies')), findsNothing);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      app.lists.copies['me/minha'] = {'u1'};
      app.lists.copyCountError = Exception('network');
      await tester.tap(_chip('minha'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('list-copies')), findsNothing);
    });
  });
}
