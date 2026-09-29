import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/ui/core/category_style.dart';
import 'package:naarea/ui/core/stable_hash.dart';

void main() {
  test('ícone por categoria do seed (sem diferenciar maiúsculas/acentos)', () {
    expect(categoryIcon('Restaurante'), Icons.restaurant);
    expect(categoryIcon('Bar'), Icons.sports_bar);
    expect(categoryIcon('Bares'), Icons.sports_bar);
    expect(categoryIcon('Bar / Casa de show'), Icons.sports_bar);
    expect(categoryIcon('Taverna Pub'), Icons.sports_bar);
    expect(categoryIcon('Cervejaria'), Icons.sports_bar);
    expect(categoryIcon('Tapiocaria'), Icons.bakery_dining);
    expect(categoryIcon('Churrascaria'), Icons.outdoor_grill);
    expect(categoryIcon('Mercado / Bares'), Icons.storefront);
    expect(categoryIcon('Feira'), Icons.storefront);
    expect(categoryIcon('Shopping / Alimentação'), Icons.local_mall);
    expect(categoryIcon('Artesanato / Café'), Icons.palette);
    expect(categoryIcon('Café'), Icons.local_cafe);
    expect(categoryIcon(''), Icons.place);
    expect(categoryIcon('Qualquer coisa'), Icons.place);
  });

  test('"bar" e "pub" só como palavra inteira', () {
    expect(categoryIcon('Barraca de praia'), isNot(Icons.sports_bar));
    expect(categoryIcon('República'), isNot(Icons.sports_bar));
    expect(categoryIcon('Barbearia'), isNot(Icons.sports_bar));
  });

  test(
    'gradiente de fallback é estável por categoria e varia entre categorias',
    () {
      expect(categoryGradient('Bar'), categoryGradient('Bar'));
      expect(
        categoryGradient('bár'),
        categoryGradient('Bar'),
        reason: 'normaliza caixa e acento',
      );
      expect(categoryGradient('Bar').colors, hasLength(2));
      expect(
        categoryGradient('Bar').colors,
        isNot(categoryGradient('Restaurante').colors),
      );
    },
  );

  group('stableHash', () {
    test('determinístico e não negativo', () {
      expect(stableHash('ana'), stableHash('ana'));
      expect(stableHash(''), 0);
      expect(stableHash('a'), 97);
      expect(stableHash('ab'), 97 * 31 + 98);
      expect(stableHash('x' * 500), greaterThanOrEqualTo(0));
    });

    test('textos diferentes costumam dar hashes diferentes', () {
      expect(stableHash('ana'), isNot(stableHash('beto')));
    });
  });
}
