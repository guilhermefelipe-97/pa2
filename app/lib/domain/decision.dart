import 'geo.dart';
import 'models/companion.dart';
import 'models/day_period.dart';
import 'models/place.dart';
import 'models/place_activity.dart';
import 'open_status.dart';

/// Um salvo que concorre no modo decisão (F09).
typedef DecisionCandidate = ({Place place, DateTime savedAt});

/// Critérios do ranking do modo decisão, na ordem em que desempatam
/// (lexicográfico, sem pesos a calibrar).
enum DecisionCriterion {
  /// Avaliações de quem você segue com a mesma companhia E o mesmo período
  /// do dia de agora.
  companionAndPeriod,

  /// Avaliações com a mesma companhia OU o mesmo período.
  companionOrPeriod,

  /// Total de avaliações de quem você segue.
  reviewCount,

  /// Média dos eixos preenchidos dessas avaliações (interna, nunca exibida).
  average,

  /// Distância crescente (sem posição ou sem coordenadas vai para o fim).
  distance,

  /// Salvo mais recentemente.
  savedAt,
}

/// Um lugar ranqueado, com os sinais que o colocaram ali e o critério que o
/// pôs à frente do seguinte ([reason]). Não há nota única: [average] só
/// ordena e nunca é exibida.
class DecisionOption {
  const DecisionOption({
    required this.place,
    required this.savedAt,
    required this.both,
    required this.either,
    required this.total,
    required this.bothPeople,
    required this.eitherPeople,
    required this.totalPeople,
    required this.average,
    required this.distanceMeters,
    this.reason = DecisionCriterion.savedAt,
  });

  final Place place;
  final DateTime savedAt;

  /// Quantas avaliações casam companhia e período ([DecisionCriterion
  /// .companionAndPeriod]).
  final int both;

  /// Quantas casam companhia ou período.
  final int either;

  /// Quantas avaliações de quem você segue o local tem.
  final int total;

  /// Pessoas distintas por trás de [both], [either] e [total] (para o texto).
  final int bothPeople;
  final int eitherPeople;
  final int totalPeople;

  /// Média interna dos eixos preenchidos; `null` sem avaliações.
  final double? average;

  /// `null` sem posição do aparelho ou sem coordenadas do local.
  final double? distanceMeters;

  /// Critério do motivo exibido: o que pôs este lugar à frente do seguinte;
  /// sem seguinte (o último, o único) ou em empate total, o sinal mais forte
  /// que ele tem. O texto ([decisionReason]) só afirma fatos do próprio
  /// lugar, nunca superlativos (a comparação é só com o seguinte).
  final DecisionCriterion reason;

  DecisionOption _withReason(DecisionCriterion r) => DecisionOption(
    place: place,
    savedAt: savedAt,
    both: both,
    either: either,
    total: total,
    bothPeople: bothPeople,
    eitherPeople: eitherPeople,
    totalPeople: totalPeople,
    average: average,
    distanceMeters: distanceMeters,
    reason: r,
  );
}

/// Ranking do modo decisão (F09), função pura.
///
/// - [candidates]: os salvos do chip ativo.
/// - [followedReviews]: avaliações de quem o usuário segue (do mesmo padrão
///   do feed e do Perto); só contam as dos candidatos. Vazio = critério
///   ignorado (ex.: a leitura falhou).
/// - [companion]: `null` = "Tanto faz" (ignora a companhia).
/// - [position]: `null` = sem localização (a distância sai do critério).
/// - [openStatuses]: local com "Fechado" relatado sai antes de ordenar.
///
/// Devolve do melhor para o pior; vazio se todos estão fechados.
List<DecisionOption> rankDecision({
  required List<DecisionCandidate> candidates,
  required Iterable<Review> followedReviews,
  required Companion? companion,
  required DateTime now,
  LatLng? position,
  Map<String, OpenStatus> openStatuses = const {},
}) {
  final period = DayPeriod.fromTimestamp(now);
  final open = [
    for (final c in candidates)
      if (openStatuses[c.place.id]?.kind != OpenStatusKind.closed) c,
  ];
  final ids = {for (final c in open) c.place.id};
  final byPlace = <String, List<Review>>{};
  final seen = <String>{};
  for (final r in followedReviews) {
    if (!ids.contains(r.placeId) || !seen.add(r.id)) continue;
    (byPlace[r.placeId] ??= []).add(r);
  }
  final options = [
    for (final c in open)
      _option(c, byPlace[c.place.id] ?? const [], companion, period, position),
  ]..sort(_compare);
  return [
    for (var i = 0; i < options.length; i++)
      options[i]._withReason(
        i + 1 < options.length
            ? _decisive(options[i], options[i + 1])
            : _strongest(options[i]),
      ),
  ];
}

DecisionOption _option(
  DecisionCandidate c,
  List<Review> reviews,
  Companion? companion,
  DayPeriod period,
  LatLng? position,
) {
  // "Tanto faz": a companhia nunca desempata (toda avaliação "casa").
  bool sameCompanion(Review r) => companion == null || r.companion == companion;
  bool samePeriod(Review r) => r.dayPeriod == period;
  final both = [
    for (final r in reviews)
      if (sameCompanion(r) && samePeriod(r)) r,
  ];
  final either = companion == null
      ? reviews
      : [
          for (final r in reviews)
            if (sameCompanion(r) || samePeriod(r)) r,
        ];
  final axes = [
    for (final r in reviews) ...[
      ?r.scores.food,
      ?r.scores.ambience,
      ?r.scores.service,
    ],
  ];
  final p = c.place;
  return DecisionOption(
    place: p,
    savedAt: c.savedAt,
    both: both.length,
    either: either.length,
    total: reviews.length,
    bothPeople: _people(both),
    eitherPeople: _people(either),
    totalPeople: _people(reviews),
    average: axes.isEmpty ? null : axes.reduce((a, b) => a + b) / axes.length,
    distanceMeters: position != null && p.hasCoordinates
        ? distanceMeters(position, (lat: p.lat!, lng: p.lng!))
        : null,
  );
}

int _people(List<Review> reviews) =>
    {for (final r in reviews) r.authorId}.length;

/// `null` vai para o fim; [higherFirst] inverte a ordem dos presentes.
int _nullableCompare(double? a, double? b, {required bool higherFirst}) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return higherFirst ? b.compareTo(a) : a.compareTo(b);
}

/// Comparação de [a] e [b] só no critério [c] (negativo = [a] melhor).
int _by(DecisionCriterion c, DecisionOption a, DecisionOption b) => switch (c) {
  DecisionCriterion.companionAndPeriod => b.both.compareTo(a.both),
  DecisionCriterion.companionOrPeriod => b.either.compareTo(a.either),
  DecisionCriterion.reviewCount => b.total.compareTo(a.total),
  DecisionCriterion.average => _nullableCompare(
    a.average,
    b.average,
    higherFirst: true,
  ),
  DecisionCriterion.distance => _nullableCompare(
    a.distanceMeters,
    b.distanceMeters,
    higherFirst: false,
  ),
  DecisionCriterion.savedAt => b.savedAt.compareTo(a.savedAt),
};

int _compare(DecisionOption a, DecisionOption b) {
  for (final c in DecisionCriterion.values) {
    final r = _by(c, a, b);
    if (r != 0) return r;
  }
  // Empate total: ordem estável pelo id.
  return a.place.id.compareTo(b.place.id);
}

/// Primeiro critério em que [a] fica à frente de [b]. Empate total (até no
/// `savedAt`): nenhum critério desempatou, vale o sinal mais forte de [a].
DecisionCriterion _decisive(DecisionOption a, DecisionOption b) {
  for (final c in DecisionCriterion.values) {
    if (_by(c, a, b) != 0) return c;
  }
  return _strongest(a);
}

/// O sinal mais forte que o lugar tem (sem um seguinte para comparar, ou
/// empatado com ele).
DecisionCriterion _strongest(DecisionOption o) {
  if (o.both > 0) return DecisionCriterion.companionAndPeriod;
  if (o.either > 0) return DecisionCriterion.companionOrPeriod;
  if (o.total > 0) return DecisionCriterion.reviewCount;
  if (o.distanceMeters != null) return DecisionCriterion.distance;
  return DecisionCriterion.savedAt;
}

/// "com amigos", "em casal"...
String companionPhrase(Companion c) => switch (c) {
  Companion.sozinho => 'sem companhia',
  Companion.casal => 'em casal',
  Companion.amigos => 'com amigos',
  Companion.familia => 'com a família',
  Companion.trabalho => 'a trabalho',
};

/// "à noite", "no almoço"...
String periodPhrase(DayPeriod p) => switch (p) {
  DayPeriod.madrugada => 'de madrugada',
  DayPeriod.manha => 'de manhã',
  DayPeriod.almoco => 'no almoço',
  DayPeriod.tarde => 'à tarde',
  DayPeriod.noite => 'à noite',
};

/// "1 pessoa que você segue foi" / "2 pessoas que você segue foram".
String _peopleWent(int n) =>
    n == 1 ? '1 pessoa que você segue foi' : '$n pessoas que você segue foram';

/// Média a partir da qual o texto diz "Bem avaliado" (só o texto; o
/// ranking usa a média crua).
const double _wellRatedFrom = 4;

/// Motivo exibido para [o], a partir do critério que desempatou. Só fatos
/// do próprio lugar: "2 pessoas que você segue foram com amigos à noite",
/// "A 500 m de você", "Salvo no Quero ir em 12/10". Nunca mostra nota nem
/// afirma superlativos ("o mais perto"), porque a comparação é só com o
/// seguinte.
String decisionReason(
  DecisionOption o, {
  required Companion? companion,
  required DateTime now,
}) {
  final period = periodPhrase(DayPeriod.fromTimestamp(now));
  var reason = o.reason;
  // "Tanto faz": "companhia ou período" é o mesmo que o total.
  if (companion == null && reason == DecisionCriterion.companionOrPeriod) {
    reason = DecisionCriterion.reviewCount;
  }
  // Média baixa não vira elogio: o fato que sobra é quem avaliou.
  if (reason == DecisionCriterion.average &&
      (o.average ?? 0) < _wellRatedFrom) {
    reason = DecisionCriterion.reviewCount;
  }
  return switch (reason) {
    DecisionCriterion.companionAndPeriod =>
      companion == null
          ? '${_peopleWent(o.bothPeople)} lá $period'
          : '${_peopleWent(o.bothPeople)} ${companionPhrase(companion)} '
                '$period',
    DecisionCriterion.companionOrPeriod =>
      '${_peopleWent(o.eitherPeople)} ${companionPhrase(companion!)} '
          'ou $period',
    DecisionCriterion.reviewCount =>
      o.totalPeople == 1
          ? 'Avaliado por 1 pessoa que você segue'
          : 'Avaliado por ${o.totalPeople} pessoas que você segue',
    DecisionCriterion.average => 'Bem avaliado por quem você segue',
    DecisionCriterion.distance =>
      'A ${formatDistance(o.distanceMeters!)} de você',
    DecisionCriterion.savedAt =>
      'Salvo no Quero ir em ${formatDayMonth(o.savedAt)}',
  };
}
