/// As 3 notas independentes da avaliação (F01). Nunca há nota única agregada.
///
/// Avaliação mínima (F14): cada eixo é opcional — `null` é "não avaliado",
/// nunca zero —, mas pelo menos um precisa ter nota de 1 a 5.
class Scores {
  Scores({this.food, this.ambience, this.service}) {
    final axes = {'food': food, 'ambience': ambience, 'service': service};
    for (final MapEntry(key: axis, value: v) in axes.entries) {
      if (v != null && !isValid(v)) {
        throw ArgumentError.value(
          v,
          axis,
          'eixo "$axis" deve ser inteiro de $min a $max ou null',
        );
      }
    }
    if (food == null && ambience == null && service == null) {
      throw ArgumentError(
        'avaliação precisa de pelo menos um eixo (food, ambience ou service)',
      );
    }
  }

  static const int min = 1;
  static const int max = 5;

  static bool isValid(int? value) =>
      value != null && value >= min && value <= max;

  /// Combinação aceita pelo construtor: cada eixo vazio ou 1–5, e pelo
  /// menos um preenchido.
  static bool isValidCombination(int? food, int? ambience, int? service) {
    final axes = [food, ambience, service];
    return axes.any(isValid) && axes.every((v) => v == null || isValid(v));
  }

  /// Comida (`null` = não avaliado).
  final int? food;

  /// Ambiente (`null` = não avaliado).
  final int? ambience;

  /// Atendimento (`null` = não avaliado).
  final int? service;

  @override
  bool operator ==(Object other) =>
      other is Scores &&
      other.food == food &&
      other.ambience == ambience &&
      other.service == service;

  @override
  int get hashCode => Object.hash(food, ambience, service);

  @override
  String toString() =>
      'Scores(food: $food, ambience: $ambience, service: $service)';
}

/// Média de um eixo e quantas avaliações a compõem. Sem nenhuma nota no
/// eixo, [value] é `null` (nunca zero).
class AxisAverage {
  const AxisAverage(this.value, this.count)
    : assert(count >= 0),
      assert((value == null) == (count == 0));

  static const AxisAverage none = AxisAverage(null, 0);

  final double? value;

  /// Quantas avaliações têm este eixo.
  final int count;

  @override
  bool operator ==(Object other) =>
      other is AxisAverage && other.value == value && other.count == count;

  @override
  int get hashCode => Object.hash(value, count);

  @override
  String toString() => 'AxisAverage($value, $count)';
}

/// Média de cada eixo entre várias avaliações de um mesmo local. Continua
/// sendo 3 números independentes — nunca uma nota única agregada. Cada média
/// ignora as avaliações sem aquele eixo (F14).
class AxisAverages {
  const AxisAverages({
    required this.food,
    required this.ambience,
    required this.service,
    required this.total,
  }) : assert(total > 0);

  factory AxisAverages.of(Iterable<Scores> scores) {
    final list = scores.toList();
    if (list.isEmpty) {
      throw ArgumentError.value(scores, 'scores', 'não pode ser vazio');
    }
    AxisAverage avg(int? Function(Scores s) axis) {
      final values = list.map(axis).whereType<int>().toList();
      if (values.isEmpty) return AxisAverage.none;
      return AxisAverage(
        values.reduce((a, b) => a + b) / values.length,
        values.length,
      );
    }

    return AxisAverages(
      food: avg((s) => s.food),
      ambience: avg((s) => s.ambience),
      service: avg((s) => s.service),
      total: list.length,
    );
  }

  final AxisAverage food;
  final AxisAverage ambience;
  final AxisAverage service;

  /// Quantas avaliações entraram no cálculo (com ou sem cada eixo).
  final int total;
}

/// "4", "4,5", "3,7": uma casa decimal, vírgula e sem ",0".
String formatAverage(double value) {
  final fixed = value.toStringAsFixed(1);
  final trimmed = fixed.endsWith('.0')
      ? fixed.substring(0, fixed.length - 2)
      : fixed;
  return trimmed.replaceAll('.', ',');
}

/// Pluralização simples: "1 avaliação", "2 avaliações".
String countLabel(int count, String singular, String plural) =>
    count == 1 ? '1 $singular' : '$count $plural';

/// "1 avaliação", "2 avaliações".
String reviewCountLabel(int count) =>
    countLabel(count, 'avaliação', 'avaliações');
