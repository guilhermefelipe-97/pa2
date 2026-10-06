import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/models/scores.dart';
import 'package:naarea/domain/models/user_profile.dart';

void main() {
  test('aceita 1 a 5 nos 3 eixos', () {
    expect(() => Scores(food: 1, ambience: 5, service: 3), returnsNormally);
  });

  test('rejeita 0 e 6', () {
    expect(() => Scores(food: 0, ambience: 3, service: 3), throwsArgumentError);
    expect(() => Scores(food: 3, ambience: 6, service: 3), throwsArgumentError);
    expect(
      () => Scores(food: 3, ambience: 3, service: -1),
      throwsArgumentError,
    );
  });

  test('F14: cada eixo é opcional, mas pelo menos um tem nota', () {
    final onlyFood = Scores(food: 4);
    expect(onlyFood.food, 4);
    expect(onlyFood.ambience, isNull);
    expect(onlyFood.service, isNull);
    expect(() => Scores(ambience: 5), returnsNormally);
    expect(() => Scores(service: 1), returnsNormally);
    expect(() => Scores(), throwsArgumentError);
    expect(() => Scores(food: 0), throwsArgumentError);
    expect(() => Scores(food: 4, service: 6), throwsArgumentError);
  });

  test('F14: o erro diz qual eixo está errado', () {
    expect(
      () => Scores(food: 4, ambience: 6),
      throwsA(
        isA<ArgumentError>()
            .having((e) => e.name, 'name', 'ambience')
            .having((e) => e.message, 'message', contains('ambience')),
      ),
    );
    expect(
      () => Scores(service: 0),
      throwsA(isA<ArgumentError>().having((e) => e.name, 'name', 'service')),
    );
    expect(
      () => Scores(),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('pelo menos um eixo'),
        ),
      ),
    );
  });

  test('F14: isValidCombination espelha o construtor', () {
    expect(Scores.isValidCombination(4, null, null), isTrue);
    expect(Scores.isValidCombination(null, null, 5), isTrue);
    expect(Scores.isValidCombination(1, 2, 3), isTrue);
    expect(Scores.isValidCombination(null, null, null), isFalse);
    expect(Scores.isValidCombination(0, null, null), isFalse);
    expect(Scores.isValidCombination(4, 6, null), isFalse);
  });

  test('isValid trata null como inválido', () {
    expect(Scores.isValid(null), isFalse);
    expect(Scores.isValid(1), isTrue);
  });

  test('nome do perfil não pode ser vazio nem só espaços', () {
    expect(UserProfile.isValidName(''), isFalse);
    expect(UserProfile.isValidName('   '), isFalse);
    expect(UserProfile.isValidName(' Bia '), isTrue);
    expect(UserProfile.normalizeName(' Bia '), 'Bia');
  });

  test(
    'nome do perfil tem no máximo 60 caracteres (mesmo limite das Rules)',
    () {
      expect(UserProfile.maxNameLength, 60);
      expect(UserProfile.isValidName('a' * 60), isTrue);
      expect(UserProfile.isValidName('a' * 61), isFalse);
      expect(UserProfile.isValidName('  ${'a' * 60}  '), isTrue);
      expect(UserProfile.isNameWithinLimit('a' * 61), isFalse);
      expect(UserProfile.isNonEmptyName('a' * 61), isTrue);
    },
  );
}
