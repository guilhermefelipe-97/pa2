import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/search_tokens.dart';

/// Mesmos casos que `firebase/tests/osm.test.js` usa para `tokens.js`: o app
/// e o script precisam normalizar igual, senão a busca não acha o token.
final _fixture =
    jsonDecode(
          File(
            '../firebase/tests/fixtures/search-tokens.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

List<Map<String, dynamic>> _cases(String key) =>
    (_fixture[key] as List).cast<Map<String, dynamic>>();

void main() {
  group('paridade com o script (fixture compartilhada)', () {
    for (final c in _cases('tokens')) {
      test('searchTokens(${jsonEncode(c['input'])})', () {
        expect(searchTokens(c['input'] as String), c['expected']);
      });
    }
    for (final c in _cases('words')) {
      test('normalizeQuery(${jsonEncode(c['input'])})', () {
        expect(normalizeQuery(c['input'] as String), c['expected']);
      });
    }
    for (final c in _cases('nameLower')) {
      test('nameLower(${jsonEncode(c['input'])})', () {
        expect(nameLower(c['input'] as String), c['expected']);
      });
    }
  });

  test('foldAccents', () {
    expect(foldAccents('ÁGUA Ê ÇÃO'), 'agua e cao');
  });

  test(
    'serverTerm: termo mais longo com 2+ letras (empate: o 1º); null na busca curta',
    () {
      expect(serverTerm(normalizeQuery('camar pot')), 'camar');
      expect(serverTerm(normalizeQuery('de camarões')), 'camaroes');
      expect(serverTerm(normalizeQuery('bar pub')), 'bar');
      expect(serverTerm(normalizeQuery("d'água")), 'agua');
      expect(serverTerm(normalizeQuery('c')), isNull);
      expect(serverTerm(normalizeQuery('')), isNull);
    },
  );

  test('nameMatchesTerms: cada termo é prefixo de alguma palavra', () {
    expect(nameMatchesTerms('Camarões Potiguar', ['camar', 'pot']), isTrue);
    expect(nameMatchesTerms('Camarões Potiguar', ['pot', 'ca']), isTrue);
    expect(nameMatchesTerms('Camarões Potiguar', ['tiguar']), isFalse);
    expect(nameMatchesTerms("Farofa d'Água", ['d']), isTrue);
    expect(nameMatchesTerms('Qualquer', []), isTrue);
  });
}
