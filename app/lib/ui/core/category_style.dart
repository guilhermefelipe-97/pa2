import 'package:flutter/material.dart';

import 'stable_hash.dart';
import 'theme.dart';

final _bar = RegExp(r'\b(bar|bares|pub|pubs)\b');

/// Ícone da categoria de um local (usado no fallback da foto). As categorias
/// do seed são texto livre ("Mercado / Bares", "Bar / Casa de show"...), então
/// a ordem dos testes importa: a primeira palavra-chave encontrada vence.
/// "bar"/"pub" só casam como palavra inteira ("Barraca", "República" não).
IconData categoryIcon(String category) {
  final c = _normalize(category);
  if (c.contains('mercado') || c.contains('feira')) return Icons.storefront;
  if (c.contains('artesanato')) return Icons.palette;
  if (c.contains('shopping')) return Icons.local_mall;
  if (c.contains('tapioca')) return Icons.bakery_dining;
  if (c.contains('churras')) return Icons.outdoor_grill;
  if (_bar.hasMatch(c) || c.contains('cervej')) return Icons.sports_bar;
  if (c.contains('cafe')) return Icons.local_cafe;
  if (c.contains('restaurante')) return Icons.restaurant;
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
