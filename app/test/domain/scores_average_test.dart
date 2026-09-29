import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/models/scores.dart';

void main() {
  group('AxisAverages.of: média de cada eixo (nunca nota única agregada)', () {
    test('uma avaliação: médias iguais às notas', () {
      final avg = AxisAverages.of([Scores(food: 4, ambience: 3, service: 5)]);
      expect(avg.food, 4);
      expect(avg.ambience, 3);
      expect(avg.service, 5);
    });

    test('várias avaliações: média por eixo', () {
      final avg = AxisAverages.of([
        Scores(food: 5, ambience: 2, service: 4),
        Scores(food: 4, ambience: 3, service: 5),
      ]);
      expect(avg.food, 4.5);
      expect(avg.ambience, 2.5);
      expect(avg.service, 4.5);
    });

    test('lista vazia é erro de programação', () {
      expect(() => AxisAverages.of([]), throwsArgumentError);
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
