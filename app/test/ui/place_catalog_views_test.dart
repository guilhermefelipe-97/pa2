import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/data/repositories/auth_repository.dart';
import 'package:naarea/data/repositories/place_repository.dart';
import 'package:naarea/data/repositories/review_repository.dart';
import 'package:naarea/data/services/photo_picker.dart';
import 'package:naarea/data/repositories/user_repository.dart';
import 'package:naarea/domain/feed.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/routing/router.dart';
import 'package:naarea/routing/routes.dart';
import 'package:naarea/ui/place/place_detail_view.dart';
import 'package:naarea/ui/review/place_picker_view.dart';
import 'package:naarea/ui/review/place_picker_view_model.dart';
import 'package:naarea/ui/review/review_view.dart';
import 'package:naarea/ui/core/follow_events.dart';
import 'package:provider/provider.dart';

import '../support/builders.dart';
import '../support/app_harness.dart';
import '../support/fakes.dart';

final _catalog = [
  place(
    id: 'c1',
    name: 'Camarões Potiguar',
    category: 'Frutos do mar',
    neighborhood: 'Ponta Negra',
    photoUrl: 'https://f/c1.jpg',
  ),
  place(
    id: 'c2',
    name: 'Camarões',
    category: 'Restaurante',
    neighborhood: 'Petrópolis',
    photoUrl: 'https://f/c2.jpg',
  ),
  place(
    id: 'osm-n9',
    name: 'Camarada Bar',
    category: 'Bar',
    neighborhood: 'Rocas',
    source: PlaceSource.osm,
    osmId: 'node/9',
  ),
];

const _debounce = Duration(milliseconds: 300);

Future<PlacePickerViewModel> _pumpPicker(
  WidgetTester tester,
  FakePlaceRepository repo,
) async {
  final vm = PlacePickerViewModel(placeRepository: repo);
  await tester.pumpWidget(MaterialApp(home: PlacePickerView(viewModel: vm)));
  await tester.pumpAndSettle();
  return vm;
}

void main() {
  testWidgets('seletor: sugestões iniciais e crédito © OpenStreetMap', (
    tester,
  ) async {
    await _pumpPicker(tester, FakePlaceRepository(_catalog));
    expect(find.text('Sugestões'), findsOneWidget);
    expect(find.text('Camarões Potiguar'), findsOneWidget);
    expect(
      find.text('Camarada Bar'),
      findsNothing,
      reason: 'sugestões = curados com foto',
    );
    expect(find.text('© colaboradores do OpenStreetMap'), findsOneWidget);
  });

  testWidgets('seletor: sem sugestões pede para digitar', (tester) async {
    await _pumpPicker(tester, FakePlaceRepository(const []));
    expect(find.text('Digite o nome do local para buscar'), findsOneWidget);
    expect(find.text('Sugestões'), findsNothing);
  });

  testWidgets('seletor: com 20 resultados avisa no fim para refinar', (
    tester,
  ) async {
    await _pumpPicker(
      tester,
      FakePlaceRepository([
        for (var i = 0; i < 25; i++)
          place(id: 'b$i', name: 'Bar ${i.toString().padLeft(2, '0')}'),
      ]),
    );
    await tester.enterText(find.byKey(const Key('place-search')), 'bar');
    await tester.pump(_debounce);
    await tester.pumpAndSettle();
    const hint = 'Mostrando os 20 primeiros — digite mais do nome para refinar';
    await tester.scrollUntilVisible(
      find.text(hint),
      200,
      scrollable: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ),
    );
    expect(find.text(hint), findsOneWidget);
    expect(find.text('Bar 19'), findsOneWidget);
    expect(find.text('Bar 20'), findsNothing);
  });

  testWidgets(
    'seletor: skeleton durante a busca, depois resultados com bairro',
    (tester) async {
      final repo = FakePlaceRepository(_catalog);
      final gate = Completer<List<Place>>();
      repo.searchOverride = (_) => gate.future;
      await _pumpPicker(tester, repo);

      await tester.enterText(find.byKey(const Key('place-search')), 'camar');
      await tester.pump();
      expect(find.byKey(const Key('place-skeleton')), findsOneWidget);
      await tester.pump(_debounce);
      expect(repo.searchCalls, ['camar']);

      gate.complete(_catalog);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('place-skeleton')), findsNothing);
      expect(find.text('Ponta Negra · Frutos do mar'), findsOneWidget);
      expect(find.text('Rocas · Bar'), findsOneWidget);
    },
  );

  testWidgets('seletor: chips de categoria filtram', (tester) async {
    await _pumpPicker(tester, FakePlaceRepository(_catalog));
    await tester.enterText(find.byKey(const Key('place-search')), 'camar');
    await tester.pump(_debounce);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilterChip, 'Bar'));
    await tester.pumpAndSettle();
    expect(find.text('Camarada Bar'), findsOneWidget);
    expect(find.text('Camarões Potiguar'), findsNothing);
  });

  testWidgets('seletor: vazio "Nenhum local com esse nome"', (tester) async {
    await _pumpPicker(tester, FakePlaceRepository(_catalog));
    await tester.enterText(find.byKey(const Key('place-search')), 'xyz');
    await tester.pump(_debounce);
    await tester.pumpAndSettle();
    expect(find.text('Nenhum local com esse nome'), findsOneWidget);
    expect(find.text('Tente só uma palavra do nome'), findsOneWidget);
  });

  testWidgets('seletor: erro mostra "Tentar de novo", que refaz a busca', (
    tester,
  ) async {
    final repo = FakePlaceRepository(_catalog);
    await _pumpPicker(tester, repo);
    repo.fail = true;
    await tester.enterText(find.byKey(const Key('place-search')), 'camar');
    await tester.pump(_debounce);
    await tester.pumpAndSettle();
    expect(find.text('Tentar de novo'), findsOneWidget);

    repo.fail = false;
    await tester.tap(find.text('Tentar de novo'));
    await tester.pumpAndSettle();
    expect(find.text('Camarões Potiguar'), findsOneWidget);
  });

  testWidgets(
    'AC: busco "camarões", vejo o local com bairro e consigo avaliar',
    (tester) async {
      final users = FakeUserRepository()..addUser('me', 'Eu');
      final auth = FakeAuthRepository(uid: 'me', users: users);
      final router = buildRouter(auth);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<FollowEvents>(create: (_) => FollowEvents()),
            ChangeNotifierProvider<AuthRepository>.value(value: auth),
            Provider<UserRepository>.value(value: users),
            Provider<PlaceRepository>.value(
              value: FakePlaceRepository(_catalog),
            ),
            Provider<ReviewRepository>.value(value: FakeReviewRepository()),
            Provider<PhotoPicker>.value(value: FakePhotoPicker()),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      router.go(Routes.pickPlace);
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('place-search')), 'camarões');
      await tester.pump(_debounce);
      await tester.pumpAndSettle();
      expect(find.text('Petrópolis · Restaurante'), findsOneWidget);
      expect(find.text('Camarada Bar'), findsNothing);

      await tester.tap(find.text('Camarões'));
      await tester.pumpAndSettle();
      expect(find.byType(ReviewView), findsOneWidget);
    },
  );

  testWidgets('seletor: toque duplo abre a avaliação uma vez só', (
    tester,
  ) async {
    final users = FakeUserRepository()..addUser('me', 'Eu');
    final auth = FakeAuthRepository(uid: 'me', users: users);
    final router = buildRouter(auth);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<FollowEvents>(create: (_) => FollowEvents()),
          ChangeNotifierProvider<AuthRepository>.value(value: auth),
          Provider<UserRepository>.value(value: users),
          Provider<PlaceRepository>.value(value: FakePlaceRepository(_catalog)),
          Provider<ReviewRepository>.value(value: FakeReviewRepository()),
          Provider<PhotoPicker>.value(value: FakePhotoPicker()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    router.go(Routes.pickPlace);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Camarões Potiguar'));
    await tester.tap(find.text('Camarões Potiguar'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(ReviewView), findsOneWidget);

    // Um pop volta direto ao seletor: só uma avaliação foi empilhada.
    router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(ReviewView), findsNothing);
    expect(find.byType(PlacePickerView), findsOneWidget);

    // Depois de voltar, o toque funciona de novo.
    await tester.tap(find.text('Camarões Potiguar'));
    await tester.pumpAndSettle();
    expect(find.byType(ReviewView), findsOneWidget);
  });

  testWidgets(
    'seletor: marcador em cada resultado; tocar salva e não abre a avaliação',
    (tester) async {
      final saved = FakeSavedRepository();
      final app = await pumpApp(tester, places: _catalog, saved: saved);
      app.router.go(Routes.pickPlace);
      await tester.pumpAndSettle();

      final marker = find.byKey(const Key('save-c1'));
      expect(marker, findsOneWidget);
      await tester.tap(marker);
      await tester.pumpAndSettle();

      expect(find.byType(ReviewView), findsNothing);
      expect(find.byType(PlacePickerView), findsOneWidget);
      expect(saved.byUser['me']!.containsKey('c1'), isTrue);
      expect(app.store(tester).isSaved('c1'), isTrue);
      expect(find.text('Salvo em Quero ir'), findsOneWidget);
    },
  );

  group('detalhe do local', () {
    FeedItem itemFor(Place p) =>
        groupReviewsIntoFeed([review(placeId: p.id)], places: {p.id: p}).single;

    testWidgets('mostra endereço, cozinha e crédito © OpenStreetMap', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PlaceDetailView(
            viewModel: detailVmFor(
              itemFor(
                place(
                  id: 'osm-n1',
                  name: 'Camarões',
                  address: 'Av. Engenheiro Roberto Freire, 2610',
                  cuisine: 'Frutos do mar',
                  source: PlaceSource.osm,
                  osmId: 'node/1',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Av. Engenheiro Roberto Freire, 2610'), findsOneWidget);
      expect(find.text('Frutos do mar'), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const Key('osm-credit')), 100);
      expect(find.text('© colaboradores do OpenStreetMap'), findsOneWidget);
    });

    testWidgets(
      'curado sem dados do OSM: sem endereço, cozinha nem crédito OSM',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: PlaceDetailView(
              viewModel: detailVmFor(
                itemFor(place(id: 'beco', name: 'Beco da Lama')),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('place-address')), findsNothing);
        expect(find.byKey(const Key('place-cuisine')), findsNothing);
        expect(find.byKey(const Key('osm-credit')), findsNothing);
      },
    );

    testWidgets('curado com dados mesclados do OSM também credita', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PlaceDetailView(
            viewModel: detailVmFor(
              itemFor(place(id: 'mangai', name: 'Mangai', osmId: 'way/1')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const Key('osm-credit')), 100);
      expect(find.byKey(const Key('osm-credit')), findsOneWidget);
    });
  });
}
