import 'models/day_period.dart';
import 'models/review.dart';
import 'models/scores.dart';
import 'models/visit.dart';

/// Um mês do painel do titular (F23), no fuso de Natal (UTC−3).
class TimelineMonth {
  const TimelineMonth({
    required this.year,
    required this.month,
    required this.food,
    required this.ambience,
    required this.service,
    required this.reviews,
    required this.visits,
  });

  final int year, month;

  /// Médias separadas por eixo. Sem nota no eixo, [AxisAverage.none]
  /// (nunca zero): o gráfico deixa o ponto vazio.
  final AxisAverage food, ambience, service;

  /// Avaliações do mês (com qualquer eixo).
  final int reviews;

  /// "Voltei aqui" do mês (recorrência, F15).
  final int visits;

  /// Poucas avaliações: média pouco confiável.
  bool get smallSample =>
      reviews > 0 && reviews < OwnerTimeline.smallSampleBelow;

  static const _names = [
    'jan', 'fev', 'mar', 'abr', 'mai', 'jun', //
    'jul', 'ago', 'set', 'out', 'nov', 'dez',
  ];

  /// "nov/26".
  String get label =>
      '${_names[month - 1]}/${(year % 100).toString().padLeft(2, '0')}';
}

/// Série temporal dos 3 eixos para o titular (F23): 12 meses terminando no
/// mês corrente, recorte opcional por período do dia (F02). Cálculo puro.
abstract final class OwnerTimeline {
  static const int months = 12;
  static const int smallSampleBelow = 3;

  static ({int year, int month}) _monthOf(DateTime t) {
    final local = t.toUtc().add(DayPeriod.utcOffset);
    return (year: local.year, month: local.month);
  }

  static ({int year, int month}) _shift(({int year, int month}) m, int by) {
    final index = m.year * 12 + (m.month - 1) + by;
    return (year: index ~/ 12, month: index % 12 + 1);
  }

  /// Início (instante UTC) do primeiro mês da janela: dia 1, 00h em UTC−3.
  static DateTime windowStart(DateTime now) {
    final first = _shift(_monthOf(now), -(months - 1));
    return DateTime.utc(first.year, first.month).subtract(DayPeriod.utcOffset);
  }

  static List<TimelineMonth> build({
    required Iterable<Review> reviews,
    required Iterable<Visit> visits,
    required DateTime now,
    DayPeriod? period,
  }) {
    final start = windowStart(now);
    bool inWindow(DateTime t, DayPeriod p) =>
        !t.isBefore(start) &&
        !t.isAfter(now) &&
        (period == null || p == period);

    final byMonth = <({int year, int month}), List<Scores>>{};
    final visitsByMonth = <({int year, int month}), int>{};
    for (final r in reviews) {
      if (!inWindow(r.createdAt, r.dayPeriod)) continue;
      byMonth.putIfAbsent(_monthOf(r.createdAt), () => []).add(r.scores);
    }
    for (final v in visits) {
      if (!inWindow(v.createdAt, v.dayPeriod)) continue;
      final key = _monthOf(v.createdAt);
      visitsByMonth[key] = (visitsByMonth[key] ?? 0) + 1;
    }

    final first = _shift(_monthOf(now), -(months - 1));
    return [
      for (var i = 0; i < months; i++)
        _month(_shift(first, i), byMonth, visitsByMonth),
    ];
  }

  static TimelineMonth _month(
    ({int year, int month}) key,
    Map<({int year, int month}), List<Scores>> byMonth,
    Map<({int year, int month}), int> visits,
  ) {
    final scores = byMonth[key];
    final averages = scores == null ? null : AxisAverages.of(scores);
    return TimelineMonth(
      year: key.year,
      month: key.month,
      food: averages?.food ?? AxisAverage.none,
      ambience: averages?.ambience ?? AxisAverage.none,
      service: averages?.service ?? AxisAverage.none,
      reviews: scores?.length ?? 0,
      visits: visits[key] ?? 0,
    );
  }
}
