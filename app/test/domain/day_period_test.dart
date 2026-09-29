import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/models/day_period.dart';

/// Monta um instante a partir da hora local de Natal (UTC-3).
DateTime natal(int hour, [int minute = 0]) =>
    DateTime.utc(2026, 9, 10, hour + 3, minute);

void main() {
  group('DayPeriod.fromTimestamp (UTC-3)', () {
    final cases = <(int, int, DayPeriod)>[
      (0, 0, DayPeriod.madrugada),
      (4, 59, DayPeriod.madrugada),
      (5, 0, DayPeriod.manha),
      (10, 59, DayPeriod.manha),
      (11, 0, DayPeriod.almoco),
      (13, 59, DayPeriod.almoco),
      (14, 0, DayPeriod.tarde),
      (17, 59, DayPeriod.tarde),
      (18, 0, DayPeriod.noite),
      (23, 59, DayPeriod.noite),
    ];
    for (final (h, m, expected) in cases) {
      test('${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} -> ${expected.name}', () {
        expect(DayPeriod.fromTimestamp(natal(h, m)), expected);
      });
    }

    test('usa UTC-3, não UTC: 02:00Z é 23:00 do dia anterior em Natal', () {
      expect(DayPeriod.fromTimestamp(DateTime.utc(2026, 9, 10, 2)), DayPeriod.noite);
    });

    test('independe do fuso do DateTime de entrada', () {
      final utc = DateTime.utc(2026, 9, 10, 9); // 06:00 em Natal
      expect(DayPeriod.fromTimestamp(utc.toLocal()), DayPeriod.manha);
    });
  });
}
