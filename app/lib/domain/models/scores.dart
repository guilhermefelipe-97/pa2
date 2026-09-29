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
