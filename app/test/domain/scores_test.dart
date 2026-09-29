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
    expect(() => Scores(food: 3, ambience: 3, service: -1), throwsArgumentError);
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

  test('nome do perfil tem no máximo 60 caracteres (mesmo limite das Rules)', () {
    expect(UserProfile.maxNameLength, 60);
    expect(UserProfile.isValidName('a' * 60), isTrue);
    expect(UserProfile.isValidName('a' * 61), isFalse);
    expect(UserProfile.isValidName('  ${'a' * 60}  '), isTrue);
    expect(UserProfile.isNameWithinLimit('a' * 61), isFalse);
    expect(UserProfile.isNonEmptyName('a' * 61), isTrue);
  });
}
