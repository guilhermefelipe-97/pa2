import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/models/day_period.dart';
import 'package:naarea/domain/visit_lock.dart';

void main() {
  group('visit_lock (F15)', () {
    // 12/10/2030 às 20h em Natal = 23h UTC.
    final lastAt = DateTime.utc(2030, 10, 12, 23);

    test('intervalo é de 12 h exatas; timeout de 5 s', () {
      expect(visitCooldown, const Duration(hours: 12));
      expect(visitAllowedAt(lastAt), DateTime.utc(2030, 10, 13, 11));
      expect(visitLockTimeout, const Duration(seconds: 5));
    });

    test('sem trava nunca bloqueia; bloqueia até o instante da liberação', () {
      expect(isVisitBlocked(null, lastAt), isFalse);
      expect(isVisitBlocked(lastAt, lastAt), isTrue);
      expect(
        isVisitBlocked(lastAt, lastAt.add(const Duration(hours: 3))),
        isTrue,
      );
      expect(
        isVisitBlocked(
          lastAt,
          visitAllowedAt(lastAt).subtract(const Duration(seconds: 1)),
        ),
        isTrue,
      );
      expect(isVisitBlocked(lastAt, visitAllowedAt(lastAt)), isFalse);
    });

    test('mensagem com data e hora, como no F03 (UTC-3)', () {
      expect(
        visitBlockedMessage(lastAt),
        'Você registrou uma visita em 12/10 às 20h. '
        'De novo a partir de 13/10 às 8h.',
      );
    });

    test('minutos aparecem; segundos arredondam a liberação para cima', () {
      expect(
        visitBlockedMessage(DateTime.utc(2030, 10, 12, 23, 5)),
        'Você registrou uma visita em 12/10 às 20h05. '
        'De novo a partir de 13/10 às 8h05.',
      );
      expect(
        visitBlockedMessage(DateTime.utc(2030, 10, 12, 23, 0, 13)),
        'Você registrou uma visita em 12/10 às 20h. '
        'De novo a partir de 13/10 às 8h01.',
      );
    });

    test('formatador único de hora: sem zero à esquerda, em Natal', () {
      expect(formatHour(DateTime.utc(2030, 1, 5, 3)), '0h');
      expect(formatHour(DateTime.utc(2030, 1, 5, 11)), '8h');
      expect(formatHour(DateTime.utc(2030, 1, 5, 23, 5)), '20h05');
      expect(formatHour(DateTime.utc(2030, 1, 5, 11).toLocal()), '8h');
      expect(formatDayMonthHour(DateTime.utc(2030, 1, 5, 11)), '05/01 às 8h');
    });

    test("visitCooldown = duration.value(N, 'h') da trava nas Rules "
        '(paridade, tolerante a espaços e indentação)', () {
      final rules = File('../firebase/firestore.rules').readAsStringSync();
      final block = RegExp(
        r'match\s+/visitLocks/\{\s*placeId\s*\}\s*\{([\s\S]*?)\n\s*\}',
      ).firstMatch(rules);
      expect(block, isNotNull, reason: 'match /visitLocks ausente');
      final durations = RegExp(
        r"duration\s*\.\s*value\s*\(\s*(\d+)\s*,\s*'([a-z]+)'\s*\)",
      ).allMatches(block!.group(1)!).toList();
      expect(durations, hasLength(1));
      expect(durations.single.group(2), 'h');
      expect(int.parse(durations.single.group(1)!), visitCooldown.inHours);
      expect(visitCooldown, Duration(hours: visitCooldown.inHours));
    });
  });
}
