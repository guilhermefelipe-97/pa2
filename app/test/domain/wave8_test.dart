import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/bill_extras.dart';
import 'package:naarea/domain/food_tags.dart';
import 'package:naarea/domain/models/scores.dart';
import 'package:naarea/domain/taste_match.dart';

import '../support/builders.dart';

void main() {
  final now = DateTime.utc(2026, 11, 4, 21);

  group('F07 gosto parecido', () {
    final t0 = DateTime.utc(2026, 10, 1);
    test('2 locais em comum com notas iguais: amostra insuficiente', () {
      final m = TasteRule.compare(
        [
          review(placeId: 'a', scores: Scores(food: 4)),
          review(placeId: 'b', scores: Scores(food: 4)),
        ],
        [
          review(authorId: 'b', placeId: 'a', scores: Scores(food: 4)),
          review(authorId: 'b', placeId: 'b', scores: Scores(food: 4)),
        ],
      );
      expect(m.commonPlaces, 2);
      expect(m.meanDifference, 0);
      expect(m.similar, isFalse);
    });

    test('3 locais e diferença média exatamente 1: gosto parecido', () {
      final m = TasteRule.compare(
        [
          for (final p in ['a', 'b', 'c'])
            review(placeId: p, scores: Scores(food: 5, service: 4)),
        ],
        [
          for (final p in ['a', 'b', 'c'])
            review(
              authorId: 'b',
              placeId: p,
              scores: Scores(food: 4, service: 3),
            ),
        ],
      );
      expect(m.meanDifference, 1);
      expect(m.similar, isTrue);
    });

    test('diferença média 1,2 não é gosto parecido', () {
      // diferenças: 1, 1, 2, 1, 1 → 6/5 = 1,2
      final mine = [
        review(placeId: 'a', scores: Scores(food: 5, service: 5)),
        review(placeId: 'b', scores: Scores(food: 5, service: 5)),
        review(placeId: 'c', scores: Scores(food: 5)),
      ];
      final theirs = [
        review(
          authorId: 'b',
          placeId: 'a',
          scores: Scores(food: 4, service: 4),
        ),
        review(
          authorId: 'b',
          placeId: 'b',
          scores: Scores(food: 3, service: 4),
        ),
        review(authorId: 'b', placeId: 'c', scores: Scores(food: 4)),
      ];
      final m = TasteRule.compare(mine, theirs);
      expect(m.meanDifference, closeTo(1.2, 1e-9));
      expect(m.similar, isFalse);
    });

    test(
      'local sem eixo comparável não conta; vale a avaliação mais recente',
      () {
        final mine = [
          review(placeId: 'a', scores: Scores(food: 5)),
          review(placeId: 'b', scores: Scores(food: 5)),
          review(placeId: 'c', scores: Scores(food: 5)),
          review(placeId: 'd', scores: Scores(ambience: 5)),
        ];
        final theirs = [
          review(
            authorId: 'b',
            placeId: 'a',
            scores: Scores(food: 1),
            createdAt: t0,
          ),
          review(
            authorId: 'b',
            placeId: 'a',
            scores: Scores(food: 5),
            createdAt: t0.add(const Duration(days: 1)),
          ),
          review(authorId: 'b', placeId: 'b', scores: Scores(food: 5)),
          review(authorId: 'b', placeId: 'c', scores: Scores(food: 4)),
          review(authorId: 'b', placeId: 'd', scores: Scores(food: 1)),
        ];
        final m = TasteRule.compare(mine, theirs);
        expect(m.commonPlaces, 3);
        expect(m.meanDifference, closeTo(1 / 3, 1e-9));
        expect(m.similar, isTrue);
      },
    );
  });

  group('F28 couvert e taxa', () {
    test('1 relato: sem conclusão', () {
      final s = BillExtras.couvert([
        visit(couvert: true, createdAt: now),
      ], now: now);
      expect(s.verdict, isNull);
      expect(BillExtras.couvertLabel(s), isNull);
    });

    test('2 sim, 1 não: maioria com contagem', () {
      final s = BillExtras.couvert([
        review(authorId: 'a', couvert: true, createdAt: now),
        visit(authorId: 'b', couvert: true, createdAt: now),
        review(authorId: 'c', couvert: false, createdAt: now),
      ], now: now);
      expect(BillExtras.couvertLabel(s), 'Cobra couvert · 2 de 3 relatos');
    });

    test('empate: relatos divergentes', () {
      final s = BillExtras.serviceFee([
        review(authorId: 'a', serviceFee: true, createdAt: now),
        review(authorId: 'b', serviceFee: false, createdAt: now),
      ], now: now);
      expect(
        BillExtras.serviceFeeLabel(s),
        'Taxa de 10%: relatos divergentes (1 sim, 1 não)',
      );
    });

    test(
      'relato mais recente de cada pessoa, só 12 meses, sem resposta ignorada',
      () {
        final s = BillExtras.couvert([
          review(
            authorId: 'a',
            couvert: true,
            createdAt: now.subtract(const Duration(days: 10)),
          ),
          visit(authorId: 'a', couvert: false, createdAt: now),
          visit(authorId: 'a', createdAt: now.add(const Duration(hours: 1))),
          review(
            authorId: 'b',
            couvert: true,
            createdAt: now.subtract(const Duration(days: 400)),
          ),
          review(authorId: 'c', couvert: false, createdAt: now),
        ], now: now);
        expect(s.yes, 0);
        expect(s.no, 2);
        expect(
          BillExtras.couvertLabel(s),
          'Não cobra couvert · 2 de 2 relatos',
        );
      },
    );
  });

  group('F30 comida caseira', () {
    test('tags novas são válidas e confirmadas com 3 autores', () {
      expect(validFoodTags(['marmita', 'quentinha', 'self-service']), isTrue);
      expect(validFoodTags(['self-service-por-quilo']), isFalse);
      final confirmed = confirmedFoodTags([
        for (final a in ['a', 'b', 'c'])
          review(authorId: a, tags: ['marmita', if (a != 'c') 'quentinha']),
      ]);
      expect(confirmed, {'marmita': 3});
      expect(matchesFoodTags(['marmita'], confirmed), isTrue);
      expect(matchesFoodTags(['quentinha'], confirmed), isFalse);
    });

    test('dono do local não confirma tag', () {
      final confirmed = confirmedFoodTags([
        for (final a in ['a', 'b', 'dono'])
          review(authorId: a, tags: ['self-service']),
      ], ownerUid: 'dono');
      expect(confirmed, isEmpty);
    });
  });
}
