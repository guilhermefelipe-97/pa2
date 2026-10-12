import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/osm_category.dart';

/// Mesmos casos que `firebase/tests/osm.test.js` usa para `category.js`: o
/// seed de Natal e os locais do Photon precisam cair na mesma categoria.
final _fixture =
    jsonDecode(
          File(
            '../firebase/tests/fixtures/osm-category.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

List<Map<String, dynamic>> _cases(String key) =>
    (_fixture[key] as List).cast<Map<String, dynamic>>();

void main() {
  group('paridade com o script (fixture compartilhada)', () {
    test('vocabulário e amenities', () {
      expect(osmCategories, _fixture['categories']);
      expect(osmAmenities, _fixture['amenities']);
    });

    test('osmCategoryFor em todos os casos', () {
      final cases = _cases('category');
      expect(cases, isNotEmpty);
      for (final c in cases) {
        expect(
          osmCategoryFor(c['amenity'] as String?, c['cuisine'] as String?),
          c['expected'],
          reason: jsonEncode(c),
        );
      }
    });

    test('osmCuisineLabel em todos os casos', () {
      for (final c in _cases('cuisine')) {
        expect(
          osmCuisineLabel(c['input'] as String?),
          c['expected'],
          reason: jsonEncode(c),
        );
      }
    });
  });

  test('amenity fora da lista não está no vocabulário', () {
    expect(osmCategoryFor('nightclub'), osmUnknownCategory);
    expect(osmCategories, isNot(contains(osmUnknownCategory)));
  });
}
