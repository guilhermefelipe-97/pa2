import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/models/day_period.dart';
import 'package:naarea/domain/models/scores.dart';
import 'package:naarea/domain/owner_timeline.dart';

import '../support/builders.dart';

void main() {
  // 04/11/2026 18h em Natal.
  final now = DateTime.utc(2026, 11, 4, 21);

  test('12 meses terminando no mês corrente, em UTC−3', () {
    final months = OwnerTimeline.build(
      reviews: const [],
      visits: const [],
      now: now,
    );
    expect(months, hasLength(12));
    expect(months.first.label, 'dez/25');
    expect(months.last.label, 'nov/26');
    expect(OwnerTimeline.windowStart(now), DateTime.utc(2025, 12, 1, 3));
  });

  test('eixos separados; eixo sem nota fica vazio, nunca zero', () {
    final months = OwnerTimeline.build(
      reviews: [
        review(
          scores: Scores(food: 4, service: 2),
          createdAt: DateTime.utc(2026, 7, 10, 23),
        ),
        review(
          scores: Scores(food: 5, service: 1),
          createdAt: DateTime.utc(2026, 7, 20, 23),
        ),
        review(
          scores: Scores(food: 5, ambience: 4, service: 5),
          createdAt: DateTime.utc(2026, 8, 2, 15),
        ),
      ],
      visits: [
        visit(createdAt: DateTime.utc(2026, 7, 3, 15)),
        visit(createdAt: DateTime.utc(2026, 7, 4, 15)),
      ],
      now: now,
    );
    final july = months.firstWhere((m) => m.label == 'jul/26');
    expect(july.food.value, 4.5);
    expect(july.service.value, 1.5);
    expect(july.ambience, AxisAverage.none);
    expect(july.reviews, 2);
    expect(july.visits, 2);
    expect(july.smallSample, isTrue);
    final empty = months.firstWhere((m) => m.label == 'jan/26');
    expect(empty.reviews, 0);
    expect(empty.food.value, isNull);
    expect(empty.smallSample, isFalse);
  });

  test('virada do mês segue UTC−3, não UTC', () {
    // 01/08 01h UTC = 31/07 22h em Natal.
    final months = OwnerTimeline.build(
      reviews: [
        review(scores: Scores(food: 3), createdAt: DateTime.utc(2026, 8, 1, 1)),
      ],
      visits: const [],
      now: now,
    );
    expect(months.firstWhere((m) => m.label == 'jul/26').reviews, 1);
    expect(months.firstWhere((m) => m.label == 'ago/26').reviews, 0);
  });

  test('recorte por período do dia isola a noite', () {
    final reviews = [
      // 20h em Natal: noite.
      review(
        scores: Scores(service: 1),
        createdAt: DateTime.utc(2026, 10, 5, 23),
      ),
      // 12h em Natal: almoço.
      review(
        scores: Scores(service: 5),
        createdAt: DateTime.utc(2026, 10, 6, 15),
      ),
    ];
    final night = OwnerTimeline.build(
      reviews: reviews,
      visits: [visit(createdAt: DateTime.utc(2026, 10, 6, 15))],
      now: now,
      period: DayPeriod.noite,
    );
    final october = night.firstWhere((m) => m.label == 'out/26');
    expect(october.service.value, 1);
    expect(october.reviews, 1);
    expect(october.visits, 0);
  });

  test('fora da janela ou no futuro não entra', () {
    final months = OwnerTimeline.build(
      reviews: [
        review(createdAt: DateTime.utc(2025, 11, 30, 12)),
        review(createdAt: now.add(const Duration(minutes: 1))),
      ],
      visits: const [],
      now: now,
    );
    expect(months.fold(0, (sum, m) => sum + m.reviews), 0);
  });
}
