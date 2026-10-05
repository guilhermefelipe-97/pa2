import 'package:flutter/material.dart';

import 'stable_hash.dart';
import 'theme.dart';

final _bar = RegExp(r'\b(bar|bares|pub|pubs)\b');

/// Ícone da categoria de um local (fallback da foto e lista do seletor). As
/// categorias seguem o vocabulário do import do OSM ("Bar", "Pizzaria"...),
/// mas a busca é por palavra-chave para tolerar texto livre; a ordem dos
/// testes importa: a primeira palavra-chave encontrada vence.
/// "bar"/"pub" só casam como palavra inteira ("Barraca", "República" não).
IconData categoryIcon(String category) {
  final c = _normalize(category);
  if (c.contains('mercado') || c.contains('feira')) return Icons.storefront;
  if (c.contains('artesanato')) return Icons.palette;
  if (c.contains('shopping') || c.contains('praca de alimentacao')) {
    return Icons.local_mall;
  }
  if (c.contains('tapioca')) return Icons.bakery_dining;
  if (c.contains('churras')) return Icons.outdoor_grill;
  if (_bar.hasMatch(c) || c.contains('cervej')) return Icons.sports_bar;
  if (c.contains('cafe')) return Icons.local_cafe;
  if (c.contains('lanchonete')) return Icons.fastfood;
  if (c.contains('pizza')) return Icons.local_pizza;
  if (c.contains('hamburg')) return Icons.lunch_dining;
  if (c.contains('sorvet') || c.contains('acai')) return Icons.icecream;
  if (c.contains('japon')) return Icons.ramen_dining;
  if (c.contains('frutos do mar')) return Icons.set_meal;
  if (c.contains('restaurante') || c.contains('comida')) return Icons.restaurant;
  return Icons.place;
}

const _gradientPairs = [
  [NaAreaColors.coral, NaAreaColors.laranja],
  [NaAreaColors.laranja, NaAreaColors.sol],
  [NaAreaColors.azulMar, NaAreaColors.coral],
  [NaAreaColors.coralEscuro, NaAreaColors.azulMar],
];

/// Gradiente do fallback da foto, estável por categoria (paleta pôr-do-sol).
LinearGradient categoryGradient(String category) {
  final pair =
      _gradientPairs[stableHash(_normalize(category)) % _gradientPairs.length];
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: pair,
  );
}

String _normalize(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[áàâã]'), 'a')
    .replaceAll(RegExp('[éê]'), 'e')
    .replaceAll('í', 'i')
    .replaceAll(RegExp('[óôõ]'), 'o')
    .replaceAll('ú', 'u')
    .replaceAll('ç', 'c');
