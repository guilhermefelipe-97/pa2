import 'models/review.dart';
import 'models/scores.dart';

/// Resultado do F07 entre duas pessoas: sim/não, nunca percentual.
class TasteMatch {
  const TasteMatch({required this.commonPlaces, this.meanDifference});

  /// Locais avaliados pelos dois com pelo menos um eixo comparável.
  final int commonPlaces;

  /// Diferença média absoluta das notas comparadas; `null` sem nenhuma.
  final double? meanDifference;

  bool get similar =>
      commonPlaces >= TasteRule.minCommonPlaces &&
      meanDifference != null &&
      meanDifference! <= TasteRule.maxMeanDifference;

  static const none = TasteMatch(commonPlaces: 0);
}

/// Regra do "gosto parecido" (F07, versão binária), decidida pela usuária em
/// 04/11/2026: pelo menos [minCommonPlaces] locais em comum e diferença média
/// de até [maxMeanDifference] ponto nas notas dos eixos que os dois deram.
/// Em cada local vale a avaliação mais recente de cada pessoa.
abstract final class TasteRule {
  static const int minCommonPlaces = 3;
  static const double maxMeanDifference = 1;

  static TasteMatch compare(Iterable<Review> mine, Iterable<Review> theirs) {
    final a = _latestByPlace(mine), b = _latestByPlace(theirs);
    var places = 0, samples = 0, total = 0;
    for (final MapEntry(key: placeId, value: x) in a.entries) {
      final y = b[placeId];
      if (y == null) continue;
      var compared = 0;
      for (final (p, q) in _axes(x.scores, y.scores)) {
        if (p == null || q == null) continue;
        compared++;
        total += (p - q).abs();
      }
      if (compared == 0) continue;
      places++;
      samples += compared;
    }
    return TasteMatch(
      commonPlaces: places,
      meanDifference: samples == 0 ? null : total / samples,
    );
  }

  static Iterable<(int?, int?)> _axes(Scores x, Scores y) => [
    (x.food, y.food),
    (x.ambience, y.ambience),
    (x.service, y.service),
  ];

  static Map<String, Review> _latestByPlace(Iterable<Review> reviews) {
    final latest = <String, Review>{};
    for (final r in reviews) {
      final old = latest[r.placeId];
      if (old == null ||
          r.createdAt.isAfter(old.createdAt) ||
          (r.createdAt == old.createdAt && r.id.compareTo(old.id) > 0)) {
        latest[r.placeId] = r;
      }
    }
    return latest;
  }
}
