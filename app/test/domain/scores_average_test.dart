import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/models/scores.dart';

void main() {
  group('AxisAverages.of: média de cada eixo (nunca nota única agregada)', () {
    test('uma avaliação: médias iguais às notas', () {
      final avg = AxisAverages.of([Scores(food: 4, ambience: 3, service: 5)]);
      expect(avg.food.value, 4);
      expect(avg.ambience.value, 3);
      expect(avg.service.value, 5);
    });

    test('várias avaliações: média por eixo', () {
      final avg = AxisAverages.of([
        Scores(food: 5, ambience: 2, service: 4),
        Scores(food: 4, ambience: 3, service: 5),
      ]);
      expect(avg.food.value, 4.5);
      expect(avg.ambience.value, 2.5);
      expect(avg.service.value, 4.5);
    });

    test(
      'F14: ignora eixos ausentes e conta quantas avaliações têm o eixo',
      () {
        final avg = AxisAverages.of([
          Scores(food: 4),
          Scores(food: 5, service: 3),
          Scores(service: 2),
        ]);
        expect(avg.food, const AxisAverage(4.5, 2));
        expect(avg.service, const AxisAverage(2.5, 2));
        // Nenhuma nota de ambiente: sem número (nunca zero).
        expect(avg.ambience, AxisAverage.none);
        expect(avg.ambience.value, isNull);
        expect(avg.ambience.count, 0);
      },
    );

    test('F14: avaliações completas contam todas', () {
      final avg = AxisAverages.of([
        Scores(food: 5, ambience: 2, service: 4),
        Scores(food: 4, ambience: 3, service: 5),
      ]);
      expect(avg.food.count, 2);
      expect(avg.ambience.count, 2);
      expect(avg.service.count, 2);
    });

    test('F14: antiga completa + nova parcial', () {
      final avg = AxisAverages.of([
        Scores(food: 2, ambience: 4, service: 5),
        Scores(food: 5),
      ]);
      expect(avg.total, 2);
      expect(avg.food, const AxisAverage(3.5, 2));
      expect(avg.ambience, const AxisAverage(4, 1));
      expect(avg.service, const AxisAverage(5, 1));
    });

    test('AxisAverage: count >= 0 e value nulo sse count == 0', () {
      expect(() => AxisAverage(null, -1), throwsA(isA<AssertionError>()));
      expect(() => AxisAverage(null, 2), throwsA(isA<AssertionError>()));
      expect(() => AxisAverage(4, 0), throwsA(isA<AssertionError>()));
      expect(() => const AxisAverage(4, 1), returnsNormally);
    });

    test('lista vazia é erro de programação', () {
      expect(() => AxisAverages.of([]), throwsArgumentError);
    });
  });

  group('pluralização', () {
    test('countLabel e reviewCountLabel', () {
      expect(reviewCountLabel(1), '1 avaliação');
      expect(reviewCountLabel(2), '2 avaliações');
      expect(reviewCountLabel(0), '0 avaliações');
      expect(
        countLabel(1, 'avaliação de amigo', 'avaliações de amigos'),
        '1 avaliação de amigo',
      );
    });
  });

  group('formatAverage', () {
    test('inteiro sem casa decimal; fração com 1 casa e vírgula', () {
      expect(formatAverage(4), '4');
      expect(formatAverage(4.5), '4,5');
      expect(formatAverage(11 / 3), '3,7');
      expect(formatAverage(4.96), '5');
    });
  });
}
