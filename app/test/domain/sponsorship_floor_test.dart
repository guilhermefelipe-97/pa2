import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/models/review.dart';
import 'package:naarea/domain/models/scores.dart';
import 'package:naarea/domain/sponsorship_floor.dart';

import '../support/builders.dart';

void main() {
  final now = DateTime.utc(2026, 11, 4, 15);
  List<Review> many(int n, Scores scores, {Duration age = Duration.zero}) => [
    for (var i = 0; i < n; i++)
      review(
        scores: scores,
        createdAt: now.subtract(age + Duration(hours: i)),
      ),
  ];

  test('média exatamente no piso com 5 avaliações libera o Destaque', () {
    final check = SponsorshipFloor.check([
      ...many(4, Scores(food: 4, ambience: 3)),
      review(scores: Scores(service: 3, food: 4), createdAt: now),
    ], now);
    expect(check.status, FloorStatus.eligible);
    expect(check.average, 3.5);
    expect(check.reviews, 5);
  });

  test('média abaixo do piso suspende', () {
    final check = SponsorshipFloor.check(
      many(6, Scores(food: 4, ambience: 3, service: 2)),
      now,
    );
    expect(check.status, FloorStatus.belowFloor);
    expect(check.average, 3);
    expect(SponsorshipFloor.describe(check), contains('abaixo do piso de 3,5'));
  });

  test('menos de 5 avaliações na janela suspende mesmo com média alta', () {
    final check = SponsorshipFloor.check(
      many(4, Scores(food: 5, ambience: 5, service: 5)),
      now,
    );
    expect(check.status, FloorStatus.insufficientSample);
    expect(check.average, 5);
    expect(SponsorshipFloor.describe(check), contains('pelo menos 5'));
  });

  test('avaliações com mais de 90 dias ou futuras não contam', () {
    final old = many(10, Scores(food: 1), age: const Duration(days: 91));
    final recent = many(5, Scores(food: 4));
    final future = [
      review(
        scores: Scores(food: 1),
        createdAt: now.add(const Duration(hours: 1)),
      ),
    ];
    final check = SponsorshipFloor.check([...old, ...recent, ...future], now);
    expect(check.status, FloorStatus.eligible);
    expect(check.reviews, 5);
    expect(check.average, 4);
  });

  test('a queda recente suspende e a recuperação volta sozinha', () {
    final good = many(5, Scores(food: 5, service: 5));
    final bad = many(
      10,
      Scores(food: 2, service: 1),
      age: const Duration(days: 1),
    );
    expect(
      SponsorshipFloor.check([...good, ...bad], now).status,
      FloorStatus.belowFloor,
    );
    final later = now.add(const Duration(days: 92));
    final recovered = [
      for (var i = 0; i < 5; i++)
        review(
          scores: Scores(food: 4, service: 4),
          createdAt: later.subtract(Duration(hours: i)),
        ),
    ];
    expect(
      SponsorshipFloor.check([...good, ...bad, ...recovered], later).status,
      FloorStatus.eligible,
    );
  });
}
