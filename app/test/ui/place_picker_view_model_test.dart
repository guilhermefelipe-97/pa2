import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/ui/review/place_picker_view_model.dart';

import '../support/fakes.dart';

const _places = [
  Place(id: 'c', name: 'Camarões Potiguar', category: 'Restaurante', neighborhood: 'Ponta Negra', city: 'Natal'),
  Place(id: 'm', name: 'Mangai', category: 'Restaurante', neighborhood: 'Tirol', city: 'Natal'),
  Place(id: 'p', name: 'Paçoca de Pilão', category: 'Restaurante', neighborhood: 'Ponta Negra', city: 'Natal'),
];

void main() {
  test('carrega os locais', () async {
    final vm = PlacePickerViewModel(placeRepository: FakePlaceRepository(_places));
    await vm.load();
    expect(vm.places, hasLength(3));
    expect(vm.isLoading, isFalse);
  });

  test('filtra por nome ou bairro, ignorando acento e caixa', () async {
    final vm = PlacePickerViewModel(placeRepository: FakePlaceRepository(_places));
    await vm.load();
    vm.setQuery('camaroes');
    expect(vm.places.map((p) => p.id), ['c']);
    vm.setQuery('PACOCA');
    expect(vm.places.map((p) => p.id), ['p']);
    vm.setQuery('ponta negra');
    expect(vm.places.map((p) => p.id), ['c', 'p']);
    vm.setQuery('');
    expect(vm.places, hasLength(3));
  });

  test('erro ao carregar mostra mensagem', () async {
    final repo = FakePlaceRepository(_places)..fail = true;
    final vm = PlacePickerViewModel(placeRepository: repo);
    await vm.load();
    expect(vm.errorMessage, isNotNull);
    expect(vm.places, isEmpty);
  });
}
