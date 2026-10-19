import 'text_format.dart';

/// Faixa de quanto a pessoa gastou por pessoa (F27), relatada por quem foi:
/// nunca preço do dono nem valor exato. Gravada como `priceBand` inteiro
/// ([value], 1–5) ou `null` em avaliações e visitas.
///
/// Os limites das faixas vizinhas se tocam ("até R$ 30" e "R$ 30–60"): na
/// dúvida, o seletor orienta escolher a faixa de cima.
///
/// MESMOS limites de `validPriceBand` em `firebase/firestore.rules`
/// (`priceBand >= 1 && priceBand <= 5`; teste de paridade em
/// test/domain/price_band_test.dart).
enum PriceBand {
  upTo30(1, 0, 30),
  from30To60(2, 30, 60),
  from60To100(3, 60, 100),
  from100To150(4, 100, 150),
  from150(5, 150, null);

  const PriceBand(this.value, this.min, this.max);

  /// Valor gravado no Firestore (1–5).
  final int value;

  /// Limite inferior em reais por pessoa (0 na primeira faixa).
  final int min;

  /// Limite superior em reais por pessoa; `null` na última ("R$ 150+").
  final int? max;

  /// Menor e maior [value] aceitos pelas Rules.
  static const int minValue = 1;
  static const int maxValue = 5;

  /// Faixa do valor gravado; `null` (não informado) ou fora de 1–5 →
  /// `null`.
  static PriceBand? fromValue(int? value) {
    if (value == null) return null;
    for (final b in values) {
      if (b.value == value) return b;
    }
    return null;
  }

  /// Inteiro de 1 a 5, como nas Rules (`is int`). Rejeita `double`
  /// explicitamente: na VM, `2.0` é `double` e nunca `int`. Na web todo
  /// número é um `double` do JS (`2 is double` é verdade), então lá só dá
  /// para exigir um valor inteiro: o SDK web não distingue 2 de 2.0 (e as
  /// Rules já negam gravar 2.0).
  static bool isValidValue(Object? value) {
    if (value is! int) return false;
    if (!_runningOnWeb && value is double) return false;
    return value >= minValue && value <= maxValue;
  }

  /// `true` só no JavaScript, onde 0 e 0.0 são o mesmo valor.
  static const bool _runningOnWeb = identical(0, 0.0);

  /// "até R$ 30", "R$ 30–60", "R$ 150+".
  String get label => switch (this) {
    upTo30 => 'até R\$ ${formatReais(max!)}',
    from150 => 'R\$ ${formatReais(min)}+',
    _ => 'R\$ ${formatReais(min)}–${formatReais(max!)}',
  };

  /// "R$ 30–60 por pessoa"; no começo da frase, "Até R$ 30 por pessoa".
  String get perPersonLabel => capitalizeFirst('$label por pessoa');

  /// O que o leitor de tela fala: "Até 30 reais por pessoa", "De 30 a 60
  /// reais por pessoa", "Mais de 150 reais por pessoa".
  String get spokenLabel => switch (this) {
    upTo30 => 'Até ${max!} reais por pessoa',
    from150 => 'Mais de $min reais por pessoa',
    _ => 'De $min a ${max!} reais por pessoa',
  };
}

/// Leitura tolerante do `priceBand` de um doc (avaliação ou visita),
/// espelhando as Rules: chave ausente (build antigo) ou `null` = não
/// informado; int de 1 a 5 = a faixa. Qualquer outra coisa (0, 6, "2", 2.5,
/// 2.0) lança [FormatException] e o doc é ignorado, como um eixo inválido
/// (F14).
PriceBand? readPriceBand(Map<String, dynamic> doc) {
  final v = doc['priceBand'];
  if (v == null) return null;
  if (PriceBand.isValidValue(v)) return PriceBand.fromValue(v as int);
  throw FormatException('priceBand inválido: $v (${v.runtimeType})');
}

/// Estimativa para rachar: a faixa vezes [people]. "Para 4 pessoas: R$
/// 120–240"; primeira faixa "Para 4 pessoas: até R$ 120"; última "Para 3
/// pessoas: a partir de R$ 450". Nunca uma média inventada: só os limites
/// da faixa multiplicados.
String splitEstimateLabel(PriceBand band, int people) {
  assert(people >= 1);
  final n = people;
  final value = switch (band) {
    PriceBand.upTo30 => 'até R\$ ${formatReais(band.max! * n)}',
    PriceBand.from150 => 'a partir de R\$ ${formatReais(band.min * n)}',
    _ => 'R\$ ${formatReais(band.min * n)}–${formatReais(band.max! * n)}',
  };
  return 'Para $n pessoas: $value';
}

/// O que o leitor de tela fala da estimativa: "Para 4 pessoas: de 120 a 240
/// reais", "Para 4 pessoas: até 120 reais", "Para 3 pessoas: a partir de
/// 450 reais".
String splitEstimateSpoken(PriceBand band, int people) {
  assert(people >= 1);
  final n = people;
  final value = switch (band) {
    PriceBand.upTo30 => 'até ${formatReais(band.max! * n)} reais',
    PriceBand.from150 => 'a partir de ${formatReais(band.min * n)} reais',
    _ =>
      'de ${formatReais(band.min * n)} a '
          '${formatReais(band.max! * n)} reais',
  };
  return 'Para $n pessoas: $value';
}
