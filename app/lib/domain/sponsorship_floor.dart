import 'models/review.dart';
import 'models/scores.dart';

/// Resultado do piso do Destaque (F26).
enum FloorStatus {
  /// Média e amostra suficientes: o Destaque pode aparecer.
  eligible,

  /// Média abaixo do piso: Destaque suspenso.
  belowFloor,

  /// Menos avaliações que o mínimo na janela: suspenso por falta de prova.
  insufficientSample,
}

class FloorCheck {
  const FloorCheck(this.status, this.average, this.reviews);

  final FloorStatus status;

  /// Média de todas as notas de eixo na janela; `null` sem nenhuma nota.
  final double? average;

  /// Quantas avaliações caíram na janela.
  final int reviews;

  bool get eligible => status == FloorStatus.eligible;
}

/// Regra do freio do Destaque (F26), decidida pela usuária em 04/11/2026:
/// nas avaliações dos últimos [window], pelo menos [minReviews] avaliações e
/// média de todas as notas de eixo (eixo vazio não conta) maior ou igual a
/// [floor]. Abaixo disso o Destaque fica suspenso e volta sozinho quando a
/// regra passar.
abstract final class SponsorshipFloor {
  static const Duration window = Duration(days: 90);
  static const int minReviews = 5;
  static const double floor = 3.5;

  static DateTime windowStart(DateTime now) => now.subtract(window);

  static FloorCheck check(Iterable<Review> reviews, DateTime now) {
    final start = windowStart(now);
    var count = 0, samples = 0, total = 0;
    for (final review in reviews) {
      if (review.createdAt.isBefore(start) || review.createdAt.isAfter(now)) {
        continue;
      }
      count++;
      for (final value in _axes(review.scores)) {
        samples++;
        total += value;
      }
    }
    final average = samples == 0 ? null : total / samples;
    if (count < minReviews) {
      return FloorCheck(FloorStatus.insufficientSample, average, count);
    }
    if (average == null || average < floor) {
      return FloorCheck(FloorStatus.belowFloor, average, count);
    }
    return FloorCheck(FloorStatus.eligible, average, count);
  }

  static Iterable<int> _axes(Scores s) =>
      [s.food, s.ambience, s.service].whereType<int>();

  /// Frase para o titular (Divulgação).
  static String describe(FloorCheck check) {
    final avg = check.average == null
        ? 'sem notas'
        : 'média ${formatAverage(check.average!)}';
    final sample = reviewCountLabel(check.reviews);
    return switch (check.status) {
      FloorStatus.eligible =>
        'Destaque liberado: $avg em $sample nos últimos 90 dias.',
      FloorStatus.belowFloor =>
        'Destaque suspenso: $avg em $sample nos últimos 90 dias, abaixo do piso de ${formatAverage(floor)}.',
      FloorStatus.insufficientSample =>
        'Destaque suspenso: $sample nos últimos 90 dias. São necessárias pelo menos $minReviews.',
    };
  }
}
