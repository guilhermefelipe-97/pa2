import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/models/place_list.dart';

void main() {
  group('PlaceList', () {
    test('normalizeName apara as pontas', () {
      expect(
        PlaceList.normalizeName('  Sábado com as meninas '),
        'Sábado com as meninas',
      );
    });

    test('normalizeName e nameKey colapsam espaços internos repetidos', () {
      expect(
        PlaceList.normalizeName('  Sábado   com\tas  meninas '),
        'Sábado com as meninas',
      );
      expect(
        PlaceList.nameKey('Sábado   com as meninas'),
        PlaceList.nameKey('sabado com as meninas'),
      );
      expect(PlaceList.isValidName('${'a' * 20}     ${'b' * 19}'), isTrue);
    });

    test('nameKey: sem caixa e sem acento', () {
      expect(
        PlaceList.nameKey('  Sábado com as Meninas '),
        PlaceList.nameKey('sabado com as meninas'),
      );
      expect(
        PlaceList.nameKey('Café'),
        isNot(PlaceList.nameKey('Cafe da manha')),
      );
    });

    test('isValidName: 1–40 depois de aparar', () {
      expect(PlaceList.isValidName(''), isFalse);
      expect(PlaceList.isValidName('   '), isFalse);
      expect(PlaceList.isValidName('a'), isTrue);
      expect(PlaceList.isValidName('a' * 40), isTrue);
      expect(PlaceList.isValidName('  ${'a' * 40}  '), isTrue);
      expect(PlaceList.isValidName('a' * 41), isFalse);
    });

    test('12 emojis fixos, cada um com até 8 unidades (Rules)', () {
      expect(listEmojis, hasLength(12));
      expect(listEmojis.toSet(), hasLength(12));
      for (final e in listEmojis) {
        expect(e.length, inInclusiveRange(1, 8), reason: e);
      }
      expect(PlaceList.isValidEmoji(null), isTrue);
      expect(PlaceList.isValidEmoji('🎉'), isTrue);
      expect(PlaceList.isValidEmoji('x'), isFalse);
    });

    test('label, contains e isFull', () {
      final list = PlaceList(
        id: 'l',
        name: 'Sábado',
        emoji: '🎉',
        placeIds: const ['a'],
        createdAt: DateTime.utc(2026),
      );
      expect(list.label, '🎉 Sábado');
      expect(list.copyWith(emoji: () => null).label, 'Sábado');
      expect(list.contains('a'), isTrue);
      expect(list.isFull, isFalse);
      expect(
        list.copyWith(placeIds: [for (var i = 0; i < 200; i++) 'p$i']).isFull,
        isTrue,
      );
    });
  });
}
