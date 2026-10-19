import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/data/photon/photon_client.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/ui/review/place_picker_view_model.dart';

import '../support/builders.dart';
import '../support/fakes.dart';

final _places = [
  place(
    id: 'c',
    name: 'Camarões Potiguar',
    category: 'Frutos do mar',
    photoUrl: 'https://f/c.jpg',
  ),
  place(
    id: 'c2',
    name: 'Camarões',
    category: 'Restaurante',
    neighborhood: 'Petrópolis',
    photoUrl: 'https://f/c2.jpg',
  ),
  place(
    id: 'm',
    name: 'Mangai',
    category: 'Restaurante',
    neighborhood: 'Tirol',
  ),
  place(
    id: 'o',
    name: 'Camarada Bar',
    category: 'Bar',
    source: PlaceSource.osm,
    osmId: 'node/1',
  ),
];

const _debounce = Duration(milliseconds: 300);

void main() {
  late FakePlaceRepository repo;
  late PlacePickerViewModel vm;

  setUp(() {
    repo = FakePlaceRepository(_places);
    vm = PlacePickerViewModel(placeRepository: repo);
  });

  test('carga inicial: sugestões = curados com foto, sem busca', () async {
    await vm.load();
    expect(vm.isShowingSuggestions, isTrue);
    expect(vm.places.map((p) => p.id), ['c2', 'c'], reason: 'por nome');
    expect(repo.searchCalls, isEmpty);
    expect(vm.showNoResults, isFalse);
  });

  test('busca curta (0–1 caractere) mostra sugestões e não consulta', () {
    fakeAsync((async) {
      vm.load();
      async.flushMicrotasks();
      vm.setQuery('c');
      async.elapse(_debounce * 2);
      expect(vm.isShowingSuggestions, isTrue);
      expect(vm.isLoading, isFalse);
      expect(vm.places, hasLength(2));
      expect(repo.searchCalls, isEmpty);
    });
  });

  test('debounce de 300 ms: várias teclas viram uma consulta', () {
    fakeAsync((async) {
      vm.setQuery('ca');
      async.elapse(const Duration(milliseconds: 100));
      vm.setQuery('cam');
      async.elapse(const Duration(milliseconds: 100));
      vm.setQuery('camar');
      expect(vm.isLoading, isTrue, reason: 'skeleton desde a 1ª tecla');
      async.elapse(const Duration(milliseconds: 299));
      expect(repo.searchCalls, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      async.flushMicrotasks();
      expect(repo.searchCalls, ['camar']);
      expect(vm.isLoading, isFalse);
      expect(vm.places.map((p) => p.id), [
        'o',
        'c2',
        'c',
      ], reason: 'por nameLower');
    });
  });

  test('"camarões" acha sem acento/caixa; termos extras filtram', () {
    fakeAsync((async) {
      vm.setQuery('CAMAROES pot');
      async.elapse(_debounce);
      async.flushMicrotasks();
      expect(vm.places.map((p) => p.id), ['c']);
    });
  });

  test('sem resultado: "Nenhum local com esse nome"', () {
    fakeAsync((async) {
      vm.setQuery('xyz');
      async.elapse(_debounce);
      async.flushMicrotasks();
      expect(vm.places, isEmpty);
      expect(vm.showNoResults, isTrue);
    });
  });

  test('erro: mensagem e "Tentar de novo" refaz a busca na hora', () {
    fakeAsync((async) {
      repo.fail = true;
      vm.setQuery('camar');
      async.elapse(_debounce);
      async.flushMicrotasks();
      expect(vm.errorMessage, isNotNull);
      expect(vm.showNoResults, isFalse);

      repo.fail = false;
      vm.retry();
      async.flushMicrotasks();
      expect(vm.errorMessage, isNull);
      expect(vm.places, hasLength(3));
      expect(repo.searchCalls, ['camar', 'camar']);
    });
  });

  test('erro nas sugestões: mensagem e retry', () async {
    repo.fail = true;
    await vm.load();
    expect(vm.errorMessage, isNotNull);
    repo.fail = false;
    await vm.retry();
    expect(vm.errorMessage, isNull);
    expect(vm.places, hasLength(2));
  });

  test('resposta antiga não sobrescreve a mais recente', () {
    fakeAsync((async) {
      final slow = Completer<List<Place>>();
      repo.searchOverride = (q) =>
          q == 'mang' ? slow.future : Future.value([_places[0]]);
      vm.setQuery('mang');
      async.elapse(_debounce);
      vm.setQuery('camar');
      async.elapse(_debounce);
      async.flushMicrotasks();
      slow.complete([_places[2]]);
      async.flushMicrotasks();
      expect(vm.places.map((p) => p.id), ['c']);
    });
  });

  test('chips de categoria filtram a lista atual; tocar de novo limpa', () {
    fakeAsync((async) {
      vm.setQuery('camar');
      async.elapse(_debounce);
      async.flushMicrotasks();
      expect(vm.categories, ['Bar', 'Frutos do mar', 'Restaurante']);
      vm.selectCategory('Bar');
      expect(vm.places.map((p) => p.id), ['o']);
      vm.selectCategory('Bar');
      expect(vm.selectedCategory, isNull);
      expect(vm.places, hasLength(3));

      vm.selectCategory('Bar');
      vm.setQuery('mang');
      expect(vm.selectedCategory, isNull, reason: 'nova busca limpa o chip');
    });
  });

  test('20 resultados: avisa que a lista foi cortada', () {
    fakeAsync((async) {
      final many = PlacePickerViewModel(
        placeRepository: FakePlaceRepository([
          for (var i = 0; i < 25; i++)
            place(id: 'b$i', name: 'Bar ${i.toString().padLeft(2, '0')}'),
        ]),
      );
      many.setQuery('bar');
      async.elapse(_debounce);
      async.flushMicrotasks();
      expect(many.places, hasLength(20));
      expect(many.isResultCapped, isTrue);

      many.setQuery('bar 01');
      async.elapse(_debounce);
      async.flushMicrotasks();
      expect(many.isResultCapped, isFalse);

      many.setQuery('');
      expect(
        many.isResultCapped,
        isFalse,
        reason: 'sugestões não são cortadas',
      );
    });
  });

  test('dispose cancela o debounce pendente', () {
    fakeAsync((async) {
      vm.setQuery('camar');
      vm.dispose();
      async.elapse(_debounce);
      expect(repo.searchCalls, isEmpty);
    });
  });

  group('viés pela posição (G2)', () {
    test(
      'permissão já dada: busca com a posição, sem pedir ao sistema',
      () async {
        final location = FakeLocationService(
          position: (lat: -3.7319, lng: -38.5267),
          granted: true,
        );
        final vm = PlacePickerViewModel(
          placeRepository: repo,
          locationService: location,
          debounce: Duration.zero,
        );
        await vm.load();
        vm.setQuery('pizzaria');
        await pumpEventQueue();
        expect(repo.searchCalls, ['pizzaria']);
        expect(repo.searchNear.single, (lat: -3.7319, lng: -38.5267));
        expect(location.locateCalls, 0);
        expect(location.lastKnownCalls, 1);
        // Posição pedida uma vez por tela.
        vm.setQuery('bar do');
        await pumpEventQueue();
        expect(location.lastKnownCalls, 1);
        expect(repo.searchNear.last, isNotNull);
      },
    );

    test(
      'sem permissão: busca sem posição (viés no centro do Brasil)',
      () async {
        final location = FakeLocationService(
          position: (lat: -3.7319, lng: -38.5267),
        );
        final vm = PlacePickerViewModel(
          placeRepository: repo,
          locationService: location,
          debounce: Duration.zero,
        );
        vm.setQuery('pizzaria');
        await pumpEventQueue();
        expect(repo.searchNear.single, isNull);
        expect(location.locateCalls, 0);
      },
    );

    test(
      'sem posição conhecida: segue sem viés e tenta de novo na próxima',
      () async {
        final location = FakeLocationService(granted: true)
          ..useLastKnown = true;
        final vm = PlacePickerViewModel(
          placeRepository: repo,
          locationService: location,
          debounce: Duration.zero,
        );
        vm.setQuery('pizzaria');
        await pumpEventQueue();
        expect(repo.searchNear.single, isNull);
        location.lastKnown = (lat: -3.7319, lng: -38.5267);
        vm.setQuery('pizzaria bella');
        await pumpEventQueue();
        expect(repo.searchNear.last, (lat: -3.7319, lng: -38.5267));
        expect(location.lastKnownCalls, 2);
      },
    );

    test(
      'erro: mensagem com "Verifique sua conexão"; 429: muitas buscas',
      () async {
        final vm = PlacePickerViewModel(
          placeRepository: repo,
          debounce: Duration.zero,
        );
        repo.fail = true;
        vm.setQuery('pizzaria');
        await pumpEventQueue();
        expect(vm.errorMessage, PlacePickerViewModel.searchErrorMessage);
        expect(vm.errorMessage, contains('Verifique sua conexão'));
        repo.searchOverride = (_) async =>
            throw const PhotonRateLimitedException();
        vm.setQuery('pizzaria bella');
        await pumpEventQueue();
        expect(vm.errorMessage, PhotonRateLimitedException.userMessage);
      },
    );
  });
}
