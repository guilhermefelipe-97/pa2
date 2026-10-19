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

  group('F13: visível e crédito', () {
    final base = PlaceList(
      id: 'l',
      name: 'Sábado',
      emoji: null,
      placeIds: const ['a'],
      createdAt: DateTime.utc(2026),
      copiedFrom: const ListCredit(uid: 'ana', name: 'Ana', listId: 'x'),
    );

    test('privada por padrão; copyWith troca visible e mantém o crédito', () {
      expect(base.visible, isFalse);
      final shown = base.copyWith(visible: true, name: 'Outro');
      expect(shown.visible, isTrue);
      expect(shown.copiedFrom, base.copiedFrom);
      expect(shown.copyWith(placeIds: const []).visible, isTrue);
    });

    test('ListCredit compara por valor', () {
      expect(
        const ListCredit(uid: 'ana', name: 'Ana', listId: 'x'),
        const ListCredit(uid: 'ana', name: 'Ana', listId: 'x'),
      );
      expect(
        const ListCredit(uid: 'ana', name: 'Ana', listId: 'x'),
        isNot(const ListCredit(uid: 'ana', name: 'Ana', listId: 'y')),
      );
    });
  });

  group('F13: nome da cópia', () {
    bool none(String _) => false;

    test('nome livre: o mesmo nome', () {
      expect(PlaceList.copyName('Sábado', 'Ana', isTaken: none), 'Sábado');
    });

    test('nome já existe (sem caixa/acento): "<nome> (de <Autora>)"', () {
      final mine = {PlaceList.nameKey('sabado')};
      expect(
        PlaceList.copyName(
          'Sábado',
          'Ana',
          isTaken: (n) => mine.contains(PlaceList.nameKey(n)),
        ),
        'Sábado (de Ana)',
      );
    });

    test('corta só o nome-base: " (de <Autora>)" fica inteiro', () {
      final long = 'Sábado com as meninas da faculdade';
      final name = PlaceList.copyName(
        long,
        'Ana Beatriz',
        isTaken: (n) => n == long,
      );
      expect(name, 'Sábado com as meninas d (de Ana Beatriz)');
      expect(name.length, PlaceList.maxNameLength);
      expect(PlaceList.isValidName(name), isTrue);
    });

    test('crédito sozinho não cabe: corta o nome da autora e fecha', () {
      final author = 'Maria Eduarda de Albuquerque Cavalcanti Lins';
      final name = PlaceList.copyName(
        'Sábado',
        author,
        isTaken: (n) => n == 'Sábado',
      );
      expect(name.length, lessThanOrEqualTo(PlaceList.maxNameLength));
      expect(name, 'S (de Maria Eduarda de Albuquerque Cava)');
      expect(name, endsWith(')'));
      expect('('.allMatches(name).length, ')'.allMatches(name).length);
      expect(PlaceList.isValidName(name), isTrue);
    });

    test(
      'numerada com nome longo: base cortada, crédito e número inteiros',
      () {
        final long = 'Sábado com as meninas da faculdade';
        final taken = {long, 'Sábado com as meninas d (de Ana Beatriz)'};
        final name = PlaceList.copyName(
          long,
          'Ana Beatriz',
          isTaken: taken.contains,
        );
        expect(name, 'Sábado com as meninas (de Ana Beatriz) 2');
        expect(name.length, lessThanOrEqualTo(PlaceList.maxNameLength));
      },
    );

    test('corte por grafema: emoji com ZWJ e com tom de pele inteiros', () {
      const family = '👩‍👩‍👧'; // 8 unidades UTF-16
      final fam = PlaceList.copyName(family * 6, 'Ana', isTaken: (_) => false);
      // 48 unidades não cabem; sobram 31 para a base: 3 famílias (24).
      expect(fam, '${family * 3} (de Ana)');
      const thumbs = '👍🏽'; // 4 unidades
      final th = PlaceList.copyName(thumbs * 12, 'Ana', isTaken: (_) => false);
      expect(th, '${thumbs * 7} (de Ana)');
      // Autora com emoji de tom de pele, cortada sem partir o grafema.
      final who = PlaceList.copyName(
        'Sábado',
        'AB${'👍🏽' * 10}',
        isTaken: (n) => n == 'Sábado',
      );
      // Cabem 33 unidades para a autora: "AB" + 7 polegares (30); um corte
      // por unidade partiria o 8º.
      expect(who, 'Sába (de AB${'👍🏽' * 7})');
    });

    test('alternativo também existe (2ª cópia): numera', () {
      final taken = {'Sábado', 'Sábado (de Ana)'};
      expect(
        PlaceList.copyName('Sábado', 'Ana', isTaken: taken.contains),
        'Sábado (de Ana) 2',
      );
      taken.add('Sábado (de Ana) 2');
      expect(
        PlaceList.copyName('Sábado', 'Ana', isTaken: taken.contains),
        'Sábado (de Ana) 3',
      );
    });
  });
}
