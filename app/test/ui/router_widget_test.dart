import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/feed.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/routing/routes.dart';
import 'package:naarea/ui/feed/widgets/review_tile.dart';
import 'package:naarea/ui/feed/feed_view.dart';
import 'package:naarea/ui/lists/add_to_list_sheet.dart';
import 'package:naarea/ui/people/people_view.dart';
import 'package:naarea/ui/place/place_detail_view.dart';
import 'package:naarea/ui/profile/profile_view.dart';
import 'package:naarea/ui/review/place_picker_view.dart';
import 'package:naarea/ui/review/review_view.dart';
import 'package:naarea/ui/saved/saved_view.dart';

import '../support/app_harness.dart';
import '../support/builders.dart';
import '../support/fakes.dart';

const _mangai = Place(
  id: 'mangai',
  name: 'Mangai',
  category: 'Restaurante',
  neighborhood: 'Tirol',
  city: 'Natal',
);

/// Segue "a" (Ana), que avaliou o Mangai.
({FakeUserRepository users, FakeReviewRepository reviews}) _anaFoiNoMangai() {
  final users = FakeUserRepository()
    ..addUser('me', 'Eu')
    ..addUser('a', 'Ana')
    ..followingByUser['me'] = {'a'};
  final reviews = FakeReviewRepository()
    ..stored.add(
      review(
        authorId: 'a',
        authorName: 'Ana',
        placeId: 'mangai',
        placeName: 'Mangai',
      ),
    );
  return (users: users, reviews: reviews);
}

/// Na aba Pessoas: busca [name] e toca em Seguir.
Future<void> _followInPeople(WidgetTester tester, String name) async {
  await tester.enterText(find.byKey(const Key('people-search')), name);
  await tester.pump(const Duration(milliseconds: 350)); // debounce
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Seguir'));
  await tester.pumpAndSettle();
}

/// Nome do autor num tile de avaliação do detalhe (abre o perfil).
Finder _authorInTile(String name) =>
    find.descendant(of: find.byType(ReviewTile), matching: find.text(name));

Finder _tab(String label) => find.descendant(
  of: find.byKey(const Key('app-nav')),
  matching: find.text(label),
);

void main() {
  testWidgets(
    'sub-rota de avaliação sem o Place (extra) volta para a escolha de local',
    (tester) async {
      final app = await pumpApp(tester, places: [_mangai]);
      app.router.go(Routes.reviewFor('mangai'));
      await tester.pumpAndSettle();

      expect(find.byType(PlacePickerView), findsOneWidget);
      expect(find.byType(ReviewView), findsNothing);
      expect(
        app.router.routerDelegate.currentConfiguration.uri.path,
        Routes.pickPlace,
      );
    },
  );

  testWidgets('sub-rota de avaliação com o Place abre a tela de avaliação', (
    tester,
  ) async {
    final app = await pumpApp(tester, places: [_mangai]);
    app.router.go(Routes.reviewFor('mangai'), extra: _mangai);
    await tester.pumpAndSettle();

    expect(find.byType(ReviewView), findsOneWidget);
    expect(find.text('Mangai'), findsOneWidget);
  });

  testWidgets('deslogado cai no login', (tester) async {
    final app = await pumpApp(tester, uid: null);
    expect(
      app.router.routerDelegate.currentConfiguration.uri.path,
      Routes.login,
    );
    expect(find.text('Entrar'), findsOneWidget);
  });

  group('shell com barra inferior', () {
    testWidgets(
      'abas Amigos · Perto · Quero ir · Pessoas; FAB "Avaliar" só em Amigos',
      (tester) async {
        final app = await pumpApp(tester, places: [_mangai]);
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(_tab('Amigos'), findsOneWidget);
        expect(_tab('Perto'), findsOneWidget);
        expect(_tab('Quero ir'), findsOneWidget);
        expect(_tab('Pessoas'), findsOneWidget);
        expect(find.byType(FeedView), findsOneWidget);
        expect(find.byKey(const Key('feed-review')), findsOneWidget);

        await tester.tap(_tab('Quero ir'));
        await tester.pumpAndSettle();
        expect(find.byType(SavedView), findsOneWidget);
        expect(find.byKey(const Key('feed-review')), findsNothing);
        expect(
          app.router.routerDelegate.currentConfiguration.uri.path,
          Routes.saved,
        );

        await tester.tap(_tab('Pessoas'));
        await tester.pumpAndSettle();
        expect(find.byType(PeopleView), findsOneWidget);
      },
    );

    testWidgets('"Sair" fica no menu do feed', (tester) async {
      final app = await pumpApp(tester);
      await tester.tap(find.byKey(const Key('feed-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sair'));
      await tester.pumpAndSettle();
      expect(app.auth.currentUserId, isNull);
      expect(find.text('Entrar'), findsOneWidget);
    });

    testWidgets('seguir alguém em Pessoas e voltar a Amigos recarrega o feed', (
      tester,
    ) async {
      final data = _anaFoiNoMangai();
      data.users.followingByUser['me'] = {};
      await pumpApp(
        tester,
        users: data.users,
        reviews: data.reviews,
        places: [_mangai],
      );
      expect(find.text('Encontrar pessoas'), findsOneWidget);

      await tester.tap(find.text('Encontrar pessoas'));
      await tester.pumpAndSettle();
      expect(find.byType(PeopleView), findsOneWidget);
      await _followInPeople(tester, 'Ana');

      await tester.tap(_tab('Amigos'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('trust-source-a')), findsOneWidget);
    });

    testWidgets('aba vazia: "Ver onde os amigos foram" leva ao feed', (
      tester,
    ) async {
      final app = await pumpApp(tester);
      app.router.go(Routes.saved);
      await tester.pumpAndSettle();
      expect(
        find.text('Toque no marcador de um lugar para guardar aqui'),
        findsOneWidget,
      );

      await tester.tap(find.text('Ver onde os amigos foram'));
      await tester.pumpAndSettle();
      expect(find.byType(FeedView), findsOneWidget);
    });
  });

  group('detalhe do local', () {
    testWidgets(
      'aberto por URL sem extra carrega o local e as avaliações dos amigos',
      (tester) async {
        final data = _anaFoiNoMangai();
        final app = await pumpApp(
          tester,
          users: data.users,
          reviews: data.reviews,
          places: [_mangai],
        );
        app.router.go(Routes.placeDetail('mangai'));
        await tester.pumpAndSettle();

        expect(find.byType(PlaceDetailView), findsOneWidget);
        expect(find.text('Mangai'), findsWidgets);
        expect(find.text('Ana'), findsOneWidget);
        expect(find.text('1 avaliação de amigo'), findsOneWidget);
      },
    );

    testWidgets('sem avaliações de amigos: mensagem e botão Avaliar', (
      tester,
    ) async {
      final app = await pumpApp(tester, places: [_mangai]);
      app.router.go(Routes.placeDetail('mangai'));
      await tester.pumpAndSettle();

      expect(find.text('Nenhum amigo avaliou ainda'), findsOneWidget);
      await tester.tap(find.byKey(const Key('place-review')));
      await tester.pumpAndSettle();
      expect(find.byType(ReviewView), findsOneWidget);
    });

    testWidgets('id inexistente: "Local não encontrado" e Voltar', (
      tester,
    ) async {
      final app = await pumpApp(tester, places: [_mangai]);
      app.router.go(Routes.placeDetail('fantasma'));
      await tester.pumpAndSettle();

      expect(find.text('Local não encontrado'), findsOneWidget);
      await tester.tap(find.text('Voltar'));
      await tester.pumpAndSettle();
      expect(find.byType(FeedView), findsOneWidget);
    });

    testWidgets('com o FeedItem abre a tela de detalhe', (tester) async {
      final data = _anaFoiNoMangai();
      final app = await pumpApp(
        tester,
        users: data.users,
        reviews: data.reviews,
        places: [_mangai],
      );
      final item = groupReviewsIntoFeed(
        data.reviews.stored,
        places: {'mangai': _mangai},
      ).single;
      app.router.go(Routes.placeDetail('mangai'), extra: item);
      await tester.pumpAndSettle();

      expect(find.byType(PlaceDetailView), findsOneWidget);
      expect(find.text('Ana'), findsOneWidget);
    });

    testWidgets('tocar no card do feed abre o detalhe do local', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(412, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final data = _anaFoiNoMangai();
      await pumpApp(
        tester,
        users: data.users,
        reviews: data.reviews,
        places: [_mangai],
      );

      await tester.tap(find.text('Mangai'));
      await tester.pumpAndSettle();
      // push não reflete na URI do go_router (optionURLReflectsImperativeAPIs).
      expect(find.byType(PlaceDetailView), findsOneWidget);
      expect(find.text('Ana'), findsOneWidget);
    });
  });

  group('revisão F11', () {
    testWidgets('card de local fora do catálogo não tem marcador', (
      tester,
    ) async {
      final users = FakeUserRepository()
        ..addUser('me', 'Eu')
        ..followingByUser['me'] = {'a'};
      final reviews = FakeReviewRepository()
        ..stored.add(
          review(authorId: 'a', placeId: 'sumiu', placeName: 'Sumiu'),
        );
      await pumpApp(tester, users: users, reviews: reviews, places: [_mangai]);
      expect(find.text('Sumiu'), findsOneWidget);
      expect(find.byKey(const Key('save-sumiu')), findsNothing);
    });

    testWidgets('detalhe com erro tem "Tentar de novo" e "Voltar"', (
      tester,
    ) async {
      final reviews = FakeReviewRepository()
        ..placeFetchError = Exception('offline');
      final app = await pumpApp(tester, reviews: reviews, places: [_mangai]);
      app.router.go(Routes.placeDetail('mangai'));
      await tester.pumpAndSettle();
      expect(find.text('Tentar de novo'), findsOneWidget);
      await tester.tap(find.text('Voltar'));
      await tester.pumpAndSettle();
      expect(find.byType(FeedView), findsOneWidget);
    });

    testWidgets(
      'avaliar pelo detalhe recarrega e mostra "Você" com "Avaliar de novo"',
      (tester) async {
        tester.view.physicalSize = const Size(412, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final app = await pumpApp(tester, places: [_mangai]);
        app.router.go(Routes.placeDetail('mangai'));
        await tester.pumpAndSettle();
        expect(find.text('Avaliar'), findsOneWidget);

        await tester.tap(find.byKey(const Key('place-review')));
        await tester.pumpAndSettle();
        expect(find.byType(ReviewView), findsOneWidget);
        // Simula o envio: a avaliação existe e a tela volta com `true`.
        app.reviews.stored.add(
          review(
            authorId: 'me',
            authorName: 'Eu',
            placeId: 'mangai',
            placeName: 'Mangai',
          ),
        );
        app.router.pop(true);
        await tester.pumpAndSettle();

        expect(find.byType(PlaceDetailView), findsOneWidget);
        expect(find.text('Você'), findsOneWidget);
        expect(find.text('Avaliar de novo'), findsOneWidget);
      },
    );
  });

  group('AC "Quero ir"', () {
    testWidgets(
      'marcador do card do feed põe o local no topo da aba, sem recarregar o app',
      (tester) async {
        final data = _anaFoiNoMangai();
        final saved = FakeSavedRepository()
          ..seed('me', 'antigo', DateTime.utc(2026, 9, 1));
        final app = await pumpApp(
          tester,
          users: data.users,
          reviews: data.reviews,
          places: [
            _mangai,
            const Place(
              id: 'antigo',
              name: 'Beco da Lama',
              category: 'Bar',
              neighborhood: 'Cidade Alta',
              city: 'Natal',
            ),
          ],
          saved: saved,
          clock: () => DateTime.utc(2026, 9, 28, 15),
        );
        final listCallsBefore = saved.listCalls;

        await tester.tap(find.byKey(const Key('save-mangai')));
        await tester.pump();
        expect(find.text('Salvo em Quero ir'), findsOneWidget);
        expect(find.text('Desfazer'), findsOneWidget);
        await tester.pumpAndSettle();
        expect(saved.byUser['me']!.containsKey('mangai'), isTrue);

        await tester.tap(_tab('Quero ir'));
        await tester.pumpAndSettle();
        final cards = find.byType(SavedCard);
        expect(cards, findsNWidgets(2));
        expect(
          find.descendant(of: cards.first, matching: find.text('Mangai')),
          findsOneWidget,
          reason: 'mais recente primeiro',
        );
        expect(
          saved.listCalls,
          listCallsBefore,
          reason: 'carregado uma vez por sessão',
        );
        expect(app.store(tester).isSaved('mangai'), isTrue);
      },
    );

    testWidgets(
      'detalhe aberto pela aba mostra o marcador cheio e as avaliações dos amigos',
      (tester) async {
        final data = _anaFoiNoMangai();
        final saved = FakeSavedRepository()
          ..seed('me', 'mangai', DateTime.utc(2026, 9, 28, 13));
        await pumpApp(
          tester,
          users: data.users,
          reviews: data.reviews,
          places: [_mangai],
          saved: saved,
        );

        await tester.tap(_tab('Quero ir'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Mangai'));
        await tester.pumpAndSettle();

        expect(find.byType(PlaceDetailView), findsOneWidget);
        expect(find.text('Ana'), findsOneWidget);
        final marker = find.descendant(
          of: find.byType(PlaceDetailView),
          matching: find.byKey(const Key('save-mangai')),
        );
        expect(marker, findsOneWidget);
        expect(
          find.descendant(of: marker, matching: find.byIcon(Icons.bookmark)),
          findsOneWidget,
        );
      },
    );

    testWidgets('app reaberto: os salvos continuam na aba', (tester) async {
      final saved = FakeSavedRepository();
      // Sessão 1: salva pelo detalhe.
      final app1 = await pumpApp(tester, places: [_mangai], saved: saved);
      app1.router.go(Routes.placeDetail('mangai'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-mangai')));
      await tester.pumpAndSettle();

      // Sessão 2: app novo, mesmo "servidor".
      await tester.pumpWidget(const SizedBox());
      final app2 = await pumpApp(tester, places: [_mangai], saved: saved);
      app2.router.go(Routes.saved);
      await tester.pumpAndSettle();
      expect(find.byType(SavedCard), findsOneWidget);
      expect(find.text('Mangai'), findsOneWidget);
    });
  });

  group('AC listas nomeadas', () {
    testWidgets(
      'salvar no feed, "Adicionar a lista" na SnackBar, criar "Sábado com as '
      'meninas": o chip aparece e filtra o local',
      (tester) async {
        final data = _anaFoiNoMangai();
        final saved = FakeSavedRepository()
          ..seed('me', 'antigo', DateTime.utc(2026, 9, 1));
        final app = await pumpApp(
          tester,
          users: data.users,
          reviews: data.reviews,
          places: [
            _mangai,
            const Place(
              id: 'antigo',
              name: 'Beco da Lama',
              category: 'Bar',
              neighborhood: 'Cidade Alta',
              city: 'Natal',
            ),
          ],
          saved: saved,
          clock: () => DateTime.utc(2026, 9, 28, 15),
        );

        await tester.tap(find.byKey(const Key('save-mangai')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 750));
        expect(find.text('Salvo em Quero ir'), findsOneWidget);
        expect(find.text('Desfazer'), findsOneWidget);
        await tester.tap(find.text('Adicionar a lista'));
        await tester.pumpAndSettle();

        expect(find.byType(AddToListSheet), findsOneWidget);
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
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();

        await tester.tap(_tab('Quero ir'));
        await tester.pumpAndSettle();
        final list = app.lists.byUser['me']!.values.single;
        final chip = find.byKey(Key('list-chip-${list.id}'));
        expect(
          find.descendant(
            of: chip,
            matching: find.text('🎉 Sábado com as meninas · 1'),
          ),
          findsOneWidget,
        );
        expect(find.byType(SavedCard), findsNWidgets(2));

        await tester.tap(chip);
        await tester.pumpAndSettle();
        expect(find.byType(SavedCard), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(SavedCard),
            matching: find.text('Mangai'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('app reaberto: as listas e seus locais continuam lá', (
      tester,
    ) async {
      final saved = FakeSavedRepository();
      final lists = FakeListsRepository(saved: saved);
      final places = [
        _mangai,
        const Place(
          id: 'antigo',
          name: 'Beco da Lama',
          category: 'Bar',
          neighborhood: 'Cidade Alta',
          city: 'Natal',
        ),
      ];
      // Sessão 1: salva os dois e põe o Mangai numa lista nova.
      final app1 = await pumpApp(
        tester,
        places: places,
        saved: saved,
        lists: lists,
      );
      final store = app1.listsStore(tester);
      app1.store(tester).setSaved('antigo', true);
      await store.create('Sábado', withPlace: 'mangai')!.done;
      await tester.pumpAndSettle();

      // Sessão 2: app novo, mesmo "servidor".
      await tester.pumpWidget(const SizedBox());
      final app2 = await pumpApp(
        tester,
        places: places,
        saved: saved,
        lists: lists,
      );
      app2.router.go(Routes.saved);
      await tester.pumpAndSettle();
      expect(find.byType(SavedCard), findsNWidgets(2));
      final id = lists.byUser['me']!.keys.single;
      expect(find.text('Sábado · 1'), findsOneWidget);
      await tester.tap(find.byKey(Key('list-chip-$id')));
      await tester.pumpAndSettle();
      expect(find.byType(SavedCard), findsOneWidget);
      expect(find.text('Mangai'), findsOneWidget);
    });
  });

  group('F06: fonte de confiança e perfil', () {
    // Celular alto: o card inteiro (e o bloco "Quem foi") fica na tela.
    setUp(() {
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.physicalSize = const Size(412, 2000);
      view.devicePixelRatio = 1;
    });
    tearDown(() {
      TestWidgetsFlutterBinding.instance.platformDispatcher.views.first.reset();
    });

    Future<TestApp> pumpAna(WidgetTester tester, {bool following = true}) {
      final data = _anaFoiNoMangai();
      if (!following) data.users.followingByUser['me'] = {};
      return pumpApp(
        tester,
        users: data.users,
        reviews: data.reviews,
        places: [_mangai],
      );
    }

    Finder anaCard() => find.byKey(const ValueKey('trust-source-a'));

    testWidgets(
      'AC: no card, tocar em "Ana" abre o perfil dela com as avaliações',
      (tester) async {
        await pumpAna(tester);
        expect(
          find.descendant(of: anaCard(), matching: find.text('você segue')),
          findsOneWidget,
        );

        await tester.tap(
          find.descendant(of: anaCard(), matching: find.text('Ana')),
        );
        await tester.pumpAndSettle();

        expect(find.byType(ProfileView), findsOneWidget);
        expect(
          tester.widget<ProfileView>(find.byType(ProfileView)).viewModel.uid,
          'a',
        );
        expect(find.text('Ana'), findsWidgets);
        expect(find.text('Seguindo'), findsOneWidget);
        expect(find.text('Mangai'), findsOneWidget);
      },
    );

    testWidgets(
      'deixar de seguir no perfil: ao voltar o feed recarrega sem Ana',
      (tester) async {
        await pumpAna(tester);
        await tester.tap(anaCard());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Seguindo'));
        await tester.pumpAndSettle();
        expect(find.text('Seguir'), findsOneWidget);

        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(FeedView), findsOneWidget);
        expect(anaCard(), findsNothing);
        expect(find.text('Encontrar pessoas'), findsOneWidget);
      },
    );

    testWidgets('seguir Ana no perfil: ao voltar o feed mostra o card dela', (
      tester,
    ) async {
      final app = await pumpAna(tester, following: false);
      expect(find.text('Encontrar pessoas'), findsOneWidget);

      app.router.push(Routes.person('a'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Seguir'));
      await tester.pumpAndSettle();
      expect(find.text('Seguindo'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(anaCard(), findsOneWidget);
    });

    testWidgets(
      'perfil aberto pela aba Quero ir: deixar de seguir e trocar para Amigos recarrega',
      (tester) async {
        final app = await pumpAna(tester);
        expect(anaCard(), findsOneWidget);

        await tester.tap(_tab('Quero ir'));
        await tester.pumpAndSettle();
        app.router.push(Routes.person('a'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Seguindo'));
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(SavedView), findsOneWidget);

        await tester.tap(_tab('Amigos'));
        await tester.pumpAndSettle();
        expect(anaCard(), findsNothing);
        expect(find.text('Encontrar pessoas'), findsOneWidget);
      },
    );

    testWidgets('aba Pessoas reflete o deixar de seguir feito no perfil', (
      tester,
    ) async {
      await pumpAna(tester);
      await tester.tap(_tab('Pessoas'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('people-search')), 'Ana');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(OutlinedButton, 'Seguindo'), findsOneWidget);

      await tester.tap(_tab('Amigos'));
      await tester.pumpAndSettle();
      await tester.tap(anaCard());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Seguindo'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(_tab('Pessoas'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Seguir'), findsOneWidget);
    });

    testWidgets(
      'perfil empilhado (Ana, local, Ana, deixar de seguir, voltar) mostra "Seguir"',
      (tester) async {
        final app = await pumpAna(tester);
        app.router.push(Routes.person('a'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Mangai')); // avaliação dela: detalhe
        await tester.pumpAndSettle();
        expect(find.byType(PlaceDetailView), findsOneWidget);
        await tester.tap(_authorInTile('Ana'));
        await tester.pumpAndSettle();
        expect(find.byType(ProfileView), findsOneWidget);
        await tester.tap(find.text('Seguindo'));
        await tester.pumpAndSettle();

        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('Nenhum amigo avaliou ainda'), findsOneWidget);

        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(ProfileView), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Seguir'), findsOneWidget);
        expect(find.text('Seguindo'), findsNothing);
      },
    );

    testWidgets('voltar do perfil sem mudar nada não recarrega o feed', (
      tester,
    ) async {
      final app = await pumpAna(tester);
      final before = app.reviews.fetchCalls.length;
      await tester.tap(anaCard());
      await tester.pumpAndSettle();
      // o perfil lê as avaliações dela (1 leitura)
      expect(app.reviews.fetchCalls.length, before + 1);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(app.reviews.fetchCalls.length, before + 1);
    });

    testWidgets(
      'detalhe, perfil e voltar sem mudança não recarrega o detalhe',
      (tester) async {
        final app = await pumpAna(tester);
        await tester.tap(find.text('Mangai'));
        await tester.pumpAndSettle();
        expect(find.byType(PlaceDetailView), findsOneWidget);
        final placeReads = app.reviews.placeFetchCalls.length;
        final authorReads = app.reviews.fetchCalls.length;

        await tester.tap(_authorInTile('Ana'));
        await tester.pumpAndSettle();
        expect(find.byType(ProfileView), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();

        expect(find.byType(PlaceDetailView), findsOneWidget);
        expect(app.reviews.placeFetchCalls.length, placeReads);
        expect(
          app.reviews.fetchCalls.length,
          authorReads + 1,
          reason: 'só a leitura do perfil',
        );
      },
    );

    testWidgets(
      'no detalhe, deixar de seguir no perfil recarrega o detalhe e o feed',
      (tester) async {
        await pumpAna(tester);
        await tester.tap(find.text('Mangai'));
        await tester.pumpAndSettle();

        await tester.tap(_authorInTile('Ana'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Seguindo'));
        await tester.pumpAndSettle();

        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(PlaceDetailView), findsOneWidget);
        expect(find.text('Nenhum amigo avaliou ainda'), findsOneWidget);

        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(FeedView), findsOneWidget);
        expect(find.text('Encontrar pessoas'), findsOneWidget);
      },
    );

    testWidgets(
      'perfil próprio a partir do detalhe ("Você"): sem botão Seguir',
      (tester) async {
        final data = _anaFoiNoMangai();
        data.reviews.stored.add(
          review(
            authorId: 'me',
            authorName: 'Eu',
            placeId: 'mangai',
            placeName: 'Mangai',
          ),
        );
        final app = await pumpApp(
          tester,
          users: data.users,
          reviews: data.reviews,
          places: [_mangai],
        );
        app.router.push(Routes.placeDetail('mangai'));
        await tester.pumpAndSettle();

        await tester.tap(_authorInTile('Você'));
        await tester.pumpAndSettle();
        expect(find.byType(ProfileView), findsOneWidget);
        expect(find.text('Você'), findsWidgets);
        expect(find.byKey(const Key('profile-follow')), findsNothing);
        expect(find.text('Mangai'), findsOneWidget);
      },
    );

    testWidgets('link direto para uid inexistente: "Pessoa não encontrada"', (
      tester,
    ) async {
      final app = await pumpApp(tester);
      app.router.go(Routes.person('fantasma'));
      await tester.pumpAndSettle();
      expect(find.text('Pessoa não encontrada'), findsOneWidget);

      await tester.tap(find.text('Voltar'));
      await tester.pumpAndSettle();
      expect(find.byType(FeedView), findsOneWidget);
    });
  });
}
