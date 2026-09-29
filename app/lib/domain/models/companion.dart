/// Com quem a pessoa estava na visita (F02 — contexto da avaliação).
enum Companion {
  sozinho('Sozinho(a)'),
  casal('Casal'),
  amigos('Amigos'),
  familia('Família'),
  trabalho('Trabalho');

  const Companion(this.label);

  final String label;

  /// Valor gravado no Firestore (o próprio nome do enum).
  String get value => name;

  static Companion? fromValue(String? value) {
    if (value == null) return null;
    for (final c in Companion.values) {
      if (c.name == value) return c;
    }
    return null;
  }
}
