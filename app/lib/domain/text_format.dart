/// Formatação de texto em pt-BR compartilhada pelo domínio e pela UI.
library;

/// "0", "30", "1.200", "1.000.000" (separador de milhar do pt-BR). Valores
/// negativos não ocorrem (preços e contagens).
String formatReais(int value) {
  assert(value >= 0, 'formatReais: valor negativo ($value)');
  final digits = value.abs().toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write('.');
    out.write(digits[i]);
  }
  return out.toString();
}

/// Primeira letra em maiúscula: "até R$ 30" → "Até R$ 30".
String capitalizeFirst(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Lista de nomes truncada (mesmo padrão de "Ana e mais 2 foram aqui" do
/// Perto): "Ana", "Ana e Bia", "Ana, Bia e Caio" e, acima de [maxNames],
/// "Ana, Bia e mais 3".
String namesLabel(List<String> names, {int maxNames = 3}) {
  assert(maxNames >= 2);
  if (names.isEmpty) return '';
  if (names.length == 1) return names.first;
  if (names.length <= maxNames) {
    return '${names.sublist(0, names.length - 1).join(', ')} '
        'e ${names.last}';
  }
  final shown = maxNames - 1;
  return '${names.sublist(0, shown).join(', ')} '
      'e mais ${names.length - shown}';
}
