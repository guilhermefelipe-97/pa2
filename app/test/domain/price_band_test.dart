import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/feed.dart';
import 'package:naarea/domain/price_band.dart';
import 'package:naarea/domain/price_summary.dart';
import 'package:naarea/domain/text_format.dart';

import '../support/builders.dart';
import '../support/rules_source.dart';

void main() {
  final now = DateTime.utc(2026, 10, 12, 20);
  DateTime daysAgo(int d) => now.subtract(Duration(days: d));

  group('PriceBand (faixas e rótulos)', () {
    test('5 faixas com valores 1–5 e rótulos fixos', () {
      expect(PriceBand.values.map((b) => b.value), [1, 2, 3, 4, 5]);
      expect(PriceBand.values.map((b) => b.label), [
        'até R\$ 30',
        'R\$ 30–60',
        'R\$ 60–100',
        'R\$ 100–150',
        'R\$ 150+',
      ]);
      expect(PriceBand.upTo30.perPersonLabel, 'Até R\$ 30 por pessoa');
      expect(PriceBand.from60To100.perPersonLabel, 'R\$ 60–100 por pessoa');
    });

    test('rótulo falado para o leitor de tela', () {
      expect(PriceBand.upTo30.spokenLabel, 'Até 30 reais por pessoa');
      expect(PriceBand.from30To60.spokenLabel, 'De 30 a 60 reais por pessoa');
      expect(PriceBand.from150.spokenLabel, 'Mais de 150 reais por pessoa');
    });

    test('fromValue: 1–5 viram faixa; null e fora da faixa, null', () {
      for (final b in PriceBand.values) {
        expect(PriceBand.fromValue(b.value), b);
      }
      expect(PriceBand.fromValue(null), isNull);
      expect(PriceBand.fromValue(0), isNull);
      expect(PriceBand.fromValue(6), isNull);
    });

    test('readPriceBand: ausente/null = não informado; inválido lança', () {
      expect(readPriceBand({}), isNull);
      expect(readPriceBand({'priceBand': null}), isNull);
      expect(readPriceBand({'priceBand': 2}), PriceBand.from30To60);
      for (final bad in [
        0,
        6,
        -1,
        '2',
        2.5,
        true,
        <int>[2],
      ]) {
        expect(
          () => readPriceBand({'priceBand': bad}),
          throwsFormatException,
          reason: '$bad',
        );
      }
    });

    test('readPriceBand rejeita double mesmo inteiro (2.0), como as Rules', () {
      expect(() => readPriceBand({'priceBand': 2.0}), throwsFormatException);
      expect(PriceBand.isValidValue(2.0), isFalse);
      expect(PriceBand.isValidValue(2), isTrue);
    });

    test('limites 1–5 = validPriceBand nas Rules (paridade; tolerante a '
        'espaços, comentários e chaves internas)', () {
      final rules = readFirestoreRules();
      final body = rulesFunctionBody(rules, 'validPriceBand');
      expect(body, isNotNull, reason: 'validPriceBand ausente nas Rules');
      final min = RegExp(
        r'data\.priceBand\s*>=\s*(\d+)',
      ).firstMatch(body!)?.group(1);
      final max = RegExp(
        r'data\.priceBand\s*<=\s*(\d+)',
      ).firstMatch(body)?.group(1);
      expect(int.parse(min!), PriceBand.minValue);
      expect(int.parse(max!), PriceBand.maxValue);
      expect(body, matches(RegExp(r'data\.priceBand\s+is\s+int')));
      expect(PriceBand.values.first.value, PriceBand.minValue);
      expect(PriceBand.values.last.value, PriceBand.maxValue);
      // Opcional nas duas coleções: permitida, nunca exigida.
      expect(rulesFunctionBody(rules, 'reviewKeys'), contains("'priceBand'"));
      expect(
        rulesFunctionBody(rules, 'visitAllowedKeys'),
        contains("'priceBand'"),
      );
      expect(
        rulesFunctionBody(rules, 'reviewRequiredKeys'),
        isNot(contains('priceBand')),
      );
      expect(
        rulesFunctionBody(rules, 'visitKeys'),
        isNot(contains('priceBand')),
      );
      // E é validada nas duas.
      expect(
        rulesFunctionBody(rules, 'validReview'),
        contains('validPriceBand(data)'),
      );
      expect(
        rulesFunctionBody(rules, 'validVisit'),
        contains('validPriceBand(data)'),
      );
    });

    test('rulesFunctionBody ignora "}" em comentário e balanceia chaves', () {
      const rules = '''
        function f(data) {
          // comentário com } e { soltos
          return data.keys().hasAll(['a']) && { 'x': 1 }.size() > 0
            && data.priceBand >= 1;
        }
        function g() { return true; }
      ''';
      final body = rulesFunctionBody(rules, 'f')!;
      expect(body, contains('data.priceBand >= 1'));
      expect(body, isNot(contains('return true')));
      expect(body, isNot(contains('comentário')));
    });
  });

  group('PriceSummary (agregado)', () {
    test('sem relatos: null', () {
      expect(PriceSummary.of([], now: now), isNull);
      expect(PriceSummary.of([review(), visit()], now: now), isNull);
    });

    test('relato mais recente de cada pessoa; mediana (matriz do spec)', () {
      final s = PriceSummary.of([
        review(
          authorId: 'ana',
          createdAt: daysAgo(30),
          priceBand: PriceBand.from30To60,
        ),
        visit(
          authorId: 'ana',
          createdAt: daysAgo(1),
          priceBand: PriceBand.from60To100,
        ),
        review(
          authorId: 'bia',
          createdAt: daysAgo(3),
          priceBand: PriceBand.from30To60,
        ),
        review(
          authorId: 'caio',
          createdAt: daysAgo(5),
          priceBand: PriceBand.from100To150,
        ),
      ], now: now)!;
      expect(s.count, 3);
      expect(s.typical, PriceBand.from60To100);
      expect(s.reports.map((r) => r.authorId), ['ana', 'bia', 'caio']);
      expect(s.distribution[PriceBand.from30To60], 1);
      expect(s.distribution[PriceBand.from60To100], 1);
      expect(s.distribution[PriceBand.from100To150], 1);
      expect(s.distribution[PriceBand.upTo30], 0);
      expect(priceChipLabel(s), 'R\$ 60–100 por pessoa · 3 relatos');
    });

    test('ida mais recente sem preço não apaga o relato anterior', () {
      final s = PriceSummary.of([
        review(
          authorId: 'ana',
          createdAt: daysAgo(10),
          priceBand: PriceBand.from150,
        ),
        visit(authorId: 'ana', createdAt: daysAgo(1)),
      ], now: now)!;
      expect(s.typical, PriceBand.from150);
      expect(s.count, 1);
      expect(priceChipLabel(s), 'R\$ 150+ por pessoa · 1 relato');
    });

    test('empate (número par): a faixa mais baixa', () {
      final s = PriceSummary.of([
        review(authorId: 'ana', priceBand: PriceBand.upTo30),
        review(authorId: 'bia', priceBand: PriceBand.from30To60),
      ], now: now)!;
      expect(s.typical, PriceBand.upTo30);
      expect(s.typical.label, 'até R\$ 30');
    });

    test('mesmo createdAt: vence a faixa maior, depois o maior id, em '
        'qualquer ordem', () {
      final at = daysAgo(2);
      final a = review(
        id: 'r-a',
        authorId: 'ana',
        createdAt: at,
        priceBand: PriceBand.from30To60,
      );
      final b = visit(
        id: 'v-b',
        authorId: 'ana',
        createdAt: at,
        priceBand: PriceBand.from100To150,
      );
      for (final order in [
        [a, b],
        [b, a],
      ]) {
        final s = PriceSummary.of(order, now: now)!;
        expect(s.reports.single.id, 'v-b');
        expect(s.typical, PriceBand.from100To150);
      }
      final x = review(
        id: 'x1',
        authorId: 'ana',
        createdAt: at,
        priceBand: PriceBand.from30To60,
      );
      final y = visit(
        id: 'x2',
        authorId: 'ana',
        createdAt: at,
        priceBand: PriceBand.from30To60,
      );
      for (final order in [
        [x, y],
        [y, x],
      ]) {
        expect(PriceSummary.of(order, now: now)!.reports.single.id, 'x2');
      }
    });

    test('relatos com mais de 12 meses são ignorados', () {
      expect(priceReportMaxAge, const Duration(days: 365));
      final old = review(
        authorId: 'ana',
        createdAt: now.subtract(priceReportMaxAge + const Duration(days: 1)),
        priceBand: PriceBand.from150,
      );
      expect(PriceSummary.of([old], now: now), isNull);
      final edge = review(
        authorId: 'bia',
        createdAt: now.subtract(priceReportMaxAge),
        priceBand: PriceBand.upTo30,
      );
      final s = PriceSummary.of([old, edge], now: now)!;
      expect(s.reports.map((r) => r.authorId), ['bia']);
      // O relato antigo não "vence" um mais novo sem preço: a pessoa some.
      final anaNew = review(
        authorId: 'ana',
        createdAt: daysAgo(1),
        priceBand: PriceBand.from30To60,
      );
      expect(
        PriceSummary.of([old, anaNew], now: now)!.typical,
        PriceBand.from30To60,
      );
      expect(priceReportWindowLabel, contains('relatos dos últimos 12 meses'));
    });

    test('dispersão: faixas a 2+ posições de distância mostram "varia de"', () {
      final wide = PriceSummary.of([
        review(authorId: 'ana', priceBand: PriceBand.upTo30),
        review(authorId: 'bia', priceBand: PriceBand.from60To100),
        review(authorId: 'caio', priceBand: PriceBand.from150),
      ], now: now)!;
      expect(wide.typical, PriceBand.from60To100);
      expect(wide.spreadLabel, 'varia de até R\$ 30 a R\$ 150+');
      expect(
        priceChipLabel(wide),
        'R\$ 60–100 por pessoa · 3 relatos',
        reason: 'o chip continua com a mediana',
      );
      final near = PriceSummary.of([
        review(authorId: 'ana', priceBand: PriceBand.upTo30),
        review(authorId: 'bia', priceBand: PriceBand.from30To60),
      ], now: now)!;
      expect(near.spreadLabel, isNull);
      final two = PriceSummary.of([
        review(authorId: 'ana', priceBand: PriceBand.from30To60),
        review(authorId: 'bia', priceBand: PriceBand.from100To150),
      ], now: now)!;
      expect(two.spreadLabel, 'varia de R\$ 30–60 a R\$ 100–150');
    });

    test('FeedItem.priceAt usa as idas do card', () {
      final item = FeedItem(
        place: place(),
        activities: [
          review(authorId: 'ana', priceBand: PriceBand.from30To60),
          visit(authorId: 'bia', priceBand: PriceBand.from30To60),
        ],
      );
      final s = item.priceAt(now)!;
      expect(priceChipLabel(s), 'R\$ 30–60 por pessoa · 2 relatos');
      expect(identical(item.priceAt(now), s), isTrue, reason: 'cache');
      expect(
        priceChipSemantics(s, countLabel: '2 relatos de amigos'),
        'De 30 a 60 reais por pessoa, 2 relatos de amigos',
      );
    });
  });

  group('splitEstimateLabel (rachar)', () {
    test('faixa × pessoas', () {
      expect(
        splitEstimateLabel(PriceBand.from60To100, 4),
        'Para 4 pessoas: R\$ 240–400',
      );
      expect(
        splitEstimateLabel(PriceBand.from30To60, 4),
        'Para 4 pessoas: R\$ 120–240',
      );
      expect(
        splitEstimateLabel(PriceBand.upTo30, 4),
        'Para 4 pessoas: até R\$ 120',
      );
    });

    test('última faixa: a partir de', () {
      expect(
        splitEstimateLabel(PriceBand.from150, 3),
        'Para 3 pessoas: a partir de R\$ 450',
      );
      expect(
        splitEstimateLabel(PriceBand.from150, 2),
        'Para 2 pessoas: a partir de R\$ 300',
      );
    });

    test('rótulo falado', () {
      expect(
        splitEstimateSpoken(PriceBand.from30To60, 4),
        'Para 4 pessoas: de 120 a 240 reais',
      );
      expect(
        splitEstimateSpoken(PriceBand.from150, 3),
        'Para 3 pessoas: a partir de 450 reais',
      );
      expect(
        splitEstimateSpoken(PriceBand.upTo30, 4),
        'Para 4 pessoas: até 120 reais',
      );
    });

    test('milhar com ponto', () {
      expect(
        splitEstimateLabel(PriceBand.from100To150, 12),
        'Para 12 pessoas: R\$ 1.200–1.800',
      );
    });
  });

  group('text_format', () {
    test('formatReais: 0, centenas, milhar e valores grandes', () {
      expect(formatReais(0), '0');
      expect(formatReais(30), '30');
      expect(formatReais(999), '999');
      expect(formatReais(1000), '1.000');
      expect(formatReais(1800), '1.800');
      expect(formatReais(1000000), '1.000.000');
      expect(formatReais(123456789), '123.456.789');
    });

    test('formatReais: negativo é erro de programação (assert)', () {
      expect(() => formatReais(-1), throwsA(isA<AssertionError>()));
    });

    test('capitalizeFirst', () {
      expect(capitalizeFirst(''), '');
      expect(capitalizeFirst('até R\$ 30'), 'Até R\$ 30');
    });

    test('namesLabel trunca como "Ana, Bia e mais N"', () {
      expect(namesLabel([]), '');
      expect(namesLabel(['Ana']), 'Ana');
      expect(namesLabel(['Ana', 'Bia']), 'Ana e Bia');
      expect(namesLabel(['Ana', 'Bia', 'Caio']), 'Ana, Bia e Caio');
      expect(namesLabel(['Ana', 'Bia', 'Caio', 'Duda']), 'Ana, Bia e mais 2');
      expect(namesLabel(['A', 'B', 'C', 'D', 'E', 'F']), 'A, B e mais 4');
    });
  });
}
