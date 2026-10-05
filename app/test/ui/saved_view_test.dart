import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/ui/saved/saved_places_store.dart';
import 'package:naarea/ui/saved/saved_view.dart';
import 'package:naarea/ui/saved/saved_view_model.dart';
import 'package:provider/provider.dart';

import '../support/builders.dart';
import '../support/fakes.dart';

final _now = DateTime.utc(2026, 9, 28, 15); // 12h em Natal

final _catalog = [
  place(
    id: 'a',
    name: 'Mangai',
    neighborhood: 'Tirol',
    category: 'Restaurante',
  ),
  place(
    id: 'b',
    name: 'Beco da Lama',
    neighborhood: 'Cidade Alta',
    category: 'Bar',
  ),
  place(
    id: 'c',
    name: 'Camarões',
    neighborhood: 'Ponta Negra',
    category: 'Frutos do mar',
  ),
];

class _Setup {
  _Setup(this.store, this.vm, this.places, this.repo);
  final SavedPlacesStore store;
  final SavedViewModel vm;
  final FakePlaceRepository places;
  final FakeSavedRepository repo;
}

_Setup _make({FakeSavedRepository? repo, List<Place>? catalog}) {
  final r = repo ?? FakeSavedRepository();
  final store = SavedPlacesStore(
    authRepository: FakeAuthRepository(uid: 'me'),
    savedRepository: r,
    clock: () => _now,
  );
  final places = FakePlaceRepository(catalog ?? _catalog);
  final vm = SavedViewModel(
    store: store,
    placeRepository: places,
    clock: () => _now,
  );
  return _Setup(store, vm, places, r);
}

Future<_Setup> _pump(WidgetTester tester, _Setup s) async {
  addTearDown(() {
    s.vm.dispose();
    s.store.dispose();
  });
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: s.store,
      child: MaterialApp(home: SavedView(viewModel: s.vm)),
    ),
  );
  await tester.pumpAndSettle();
  return s;
}

FakeSavedRepository _threeSaved() => FakeSavedRepository()
  ..seed('me', 'a', DateTime.utc(2026, 9, 28, 13)) // há 2 h
  ..seed('me', 'b', DateTime.utc(2026, 9, 27, 15)) // ontem
  ..seed('me', 'c', DateTime.utc(2026, 9, 1, 15)); // 01/09

void main() {
  group('savedAgo', () {
    test('"salvo há 2 h", "salvo ontem", "salvo em 01/09", "salvo agora"', () {
      expect(savedAgo(DateTime.utc(2026, 9, 28, 13), _now), 'salvo há 2 h');
      expect(savedAgo(DateTime.utc(2026, 9, 27, 15), _now), 'salvo ontem');
      expect(savedAgo(DateTime.utc(2026, 9, 1, 15), _now), 'salvo em 01/09');
      expect(savedAgo(_now, _now), 'salvo agora');
    });
  });

  testWidgets('3 salvos: cards compactos, mais recente primeiro', (
    tester,
  ) async {
    await _pump(tester, _make(repo: _threeSaved()));

    final cards = find.byType(SavedCard);
    expect(cards, findsNWidgets(3));
    final names = [
      for (final e in cards.evaluate())
        ((e.widget as SavedCard).item.place.name),
    ];
    expect(names, ['Mangai', 'Beco da Lama', 'Camarões']);
    expect(find.text('Tirol · Restaurante'), findsOneWidget);
    expect(find.text('salvo há 2 h'), findsOneWidget);
    expect(find.text('salvo ontem'), findsOneWidget);
    expect(find.text('salvo em 01/09'), findsOneWidget);
    expect(find.byKey(const Key('place-photo-fallback')), findsNWidgets(3));
  });

  testWidgets('vazio: ilustração, texto e "Ver onde os amigos foram"', (
    tester,
  ) async {
    await _pump(tester, _make());
    expect(
      find.text('Toque no marcador de um lugar para guardar aqui'),
      findsOneWidget,
    );
    expect(find.text('Ver onde os amigos foram'), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_add_outlined), findsOneWidget);
  });

  testWidgets('salvo cujo local sumiu do catálogo é omitido', (tester) async {
    final repo = _threeSaved()
      ..seed('me', 'sumiu', DateTime.utc(2026, 9, 28, 14));
    await _pump(tester, _make(repo: repo));
    expect(find.byType(SavedCard), findsNWidgets(3));
  });

  testWidgets('só salvos de locais ausentes: estado vazio', (tester) async {
    final repo = FakeSavedRepository()
      ..seed('me', 'sumiu', DateTime.utc(2026, 9, 28));
    await _pump(tester, _make(repo: repo));
    expect(
      find.text('Toque no marcador de um lugar para guardar aqui'),
      findsOneWidget,
    );
  });

  testWidgets('erro de rede nos salvos: mensagem e "Tentar de novo"', (
    tester,
  ) async {
    final repo = _threeSaved()..listError = Exception('offline');
    await _pump(tester, _make(repo: repo));
    expect(find.text(SavedViewModel.errorText), findsOneWidget);

    repo.listError = null;
    await tester.tap(find.text('Tentar de novo'));
    await tester.pumpAndSettle();
    expect(find.byType(SavedCard), findsNWidgets(3));
  });

  testWidgets('erro de rede nos locais: mensagem e "Tentar de novo"', (
    tester,
  ) async {
    final s = _make(repo: _threeSaved());
    s.places.fail = true;
    await _pump(tester, s);
    expect(find.text(SavedViewModel.errorText), findsOneWidget);

    s.places.fail = false;
    await tester.tap(find.text('Tentar de novo'));
    await tester.pumpAndSettle();
    expect(find.byType(SavedCard), findsNWidgets(3));
  });

  testWidgets('salvar em outra tela põe o local no topo sem recarregar', (
    tester,
  ) async {
    final s = await _pump(
      tester,
      _make(
        repo: FakeSavedRepository()..seed('me', 'b', DateTime.utc(2026, 9, 1)),
      ),
    );
    final listCalls = s.repo.listCalls;

    s.store.toggle('a');
    await tester.pumpAndSettle();
    final first = tester.widget<SavedCard>(find.byType(SavedCard).first);
    expect(first.item.place.id, 'a');
    expect(find.text('salvo agora'), findsOneWidget);
    expect(s.repo.listCalls, listCalls);
  });

  testWidgets('remover pelo marcador do card tira da lista', (tester) async {
    await _pump(tester, _make(repo: _threeSaved()));
    await tester.tap(find.byKey(const Key('save-a')));
    await tester.pumpAndSettle();
    expect(find.byType(SavedCard), findsNWidgets(2));
    expect(find.text('Removido de Quero ir'), findsOneWidget);
  });

  testWidgets(
    'id salvo depois de uma falha nos locais tenta resolver de novo',
    (tester) async {
      final s = _make(
        repo: FakeSavedRepository()..seed('me', 'b', DateTime.utc(2026, 9, 1)),
      );
      s.places.fail = true;
      await _pump(tester, s);
      expect(find.text(SavedViewModel.errorText), findsOneWidget);

      s.places.fail = false;
      s.store.toggle('a');
      await tester.pumpAndSettle();
      expect(find.byType(SavedCard), findsNWidgets(2));
      expect(find.text(SavedViewModel.errorText), findsNothing);
    },
  );

  testWidgets(
    'puxar para atualizar relê os salvos e revalida locais ausentes',
    (tester) async {
      final repo = FakeSavedRepository()
        ..seed('me', 'novo', DateTime.utc(2026, 9, 28, 14));
      final s = _make(repo: repo, catalog: [..._catalog]);
      await _pump(tester, s);
      expect(
        find.text('Toque no marcador de um lugar para guardar aqui'),
        findsOneWidget,
      );
      final listCalls = repo.listCalls;

      // O local entrou no catálogo e outro aparelho salvou mais um.
      s.places.places.add(place(id: 'novo', name: 'Recém-importado'));
      repo.seed('me', 'a', DateTime.utc(2026, 9, 28, 13));
      await tester.fling(
        find.byType(SingleChildScrollView),
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();

      expect(repo.listCalls, listCalls + 1);
      expect(s.places.refreshMissingCalls.last, isTrue);
      expect(find.text('Recém-importado'), findsOneWidget);
      expect(find.text('Mangai'), findsOneWidget);
    },
  );
}
