/// As 3 notas independentes da avaliação (F01). Nunca há nota única agregada.
class Scores {
  Scores({required this.food, required this.ambience, required this.service}) {
    for (final v in [food, ambience, service]) {
      if (!isValid(v)) {
        throw ArgumentError.value(v, 'score', 'deve ser inteiro de 1 a 5');
      }
    }
  }

  static const int min = 1;
  static const int max = 5;

  static bool isValid(int? value) =>
      value != null && value >= min && value <= max;

  /// Comida.
  final int food;

  /// Ambiente.
  final int ambience;

  /// Atendimento.
  final int service;

  @override
  bool operator ==(Object other) =>
      other is Scores &&
      other.food == food &&
      other.ambience == ambience &&
      other.service == service;

  @override
  int get hashCode => Object.hash(food, ambience, service);
}

/// Média de cada eixo entre várias avaliações de um mesmo local. Continua
/// sendo 3 números independentes — nunca uma nota única agregada.
class AxisAverages {
  const AxisAverages({
    required this.food,
    required this.ambience,
    required this.service,
  });

  factory AxisAverages.of(Iterable<Scores> scores) {
    final list = scores.toList();
    if (list.isEmpty) {
      throw ArgumentError.value(scores, 'scores', 'não pode ser vazio');
    }
    double avg(int Function(Scores s) axis) =>
        list.map(axis).reduce((a, b) => a + b) / list.length;
    return AxisAverages(
      food: avg((s) => s.food),
      ambience: avg((s) => s.ambience),
      service: avg((s) => s.service),
    );
  }

  final double food;
  final double ambience;
  final double service;
}

/// "4", "4,5", "3,7": uma casa decimal, vírgula e sem ",0".
String formatAverage(double value) {
  final fixed = value.toStringAsFixed(1);
  final trimmed = fixed.endsWith('.0')
      ? fixed.substring(0, fixed.length - 2)
      : fixed;
  return trimmed.replaceAll('.', ',');
}
