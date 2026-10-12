import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/models/day_period.dart';
import 'package:naarea/domain/review_lock.dart';

void main() {
  group('review_lock (F03)', () {
    // 12/10/2030 às 20h em Natal = 23h UTC (longe do relógio real).
    final lastAt = DateTime.utc(2030, 10, 12, 23);

    test('período é de 30 dias exatos', () {
      expect(reviewCooldown, const Duration(days: 30));
      expect(reviewAllowedAt(lastAt), DateTime.utc(2030, 11, 11, 23));
    });

    test('timeout da leitura da trava é de 5 s', () {
      expect(reviewLockTimeout, const Duration(seconds: 5));
    });

    test('sem trava nunca bloqueia (avaliação legada ou 1ª)', () {
      expect(isReviewBlocked(null, lastAt), isFalse);
    });

    test('bloqueia até o instante de liberação, inclusive 1 s antes', () {
      expect(isReviewBlocked(lastAt, lastAt), isTrue);
      expect(
        isReviewBlocked(lastAt, lastAt.add(const Duration(days: 10))),
        isTrue,
      );
      expect(
        isReviewBlocked(
          lastAt,
          reviewAllowedAt(lastAt).subtract(const Duration(seconds: 1)),
        ),
        isTrue,
      );
      expect(isReviewBlocked(lastAt, reviewAllowedAt(lastAt)), isFalse);
      expect(
        isReviewBlocked(lastAt, lastAt.add(const Duration(days: 31))),
        isFalse,
      );
    });

    test('mensagem com data e hora em UTC-3', () {
      expect(
        reviewBlockedMessage(lastAt),
        'Você avaliou este lugar em 12/10. '
        'Pode avaliar de novo a partir de 11/11 às 20h.',
      );
      expect(
        reviewAgainFromLabel(lastAt),
        'Pode avaliar de novo a partir de 11/11 às 20h',
      );
    });

    test('minutos aparecem; segundos arredondam para o minuto seguinte', () {
      expect(
        reviewAgainFromLabel(DateTime.utc(2030, 10, 12, 23, 5)),
        'Pode avaliar de novo a partir de 11/11 às 20h05',
      );
      // 20h00min13s: liberação real depois das 20h → "20h01".
      expect(
        reviewAgainFromLabel(DateTime.utc(2030, 10, 12, 23, 0, 13)),
        'Pode avaliar de novo a partir de 11/11 às 20h01',
      );
    });

    test('datas e horas viram as de Natal, não as de UTC', () {
      // 13/10 01h UTC = 12/10 22h em Natal.
      final late = DateTime.utc(2030, 10, 13, 1);
      expect(formatDayMonth(late), '12/10');
      expect(formatDayMonthHour(late), '12/10 às 22h');
      expect(
        reviewBlockedMessage(late),
        'Você avaliou este lugar em 12/10. '
        'Pode avaliar de novo a partir de 11/11 às 22h.',
      );
      // Igual com DateTime local.
      expect(formatDayMonthHour(late.toLocal()), '12/10 às 22h');
    });

    test('dia e mês com dois dígitos; meia-noite é 0h', () {
      expect(formatDayMonth(DateTime.utc(2030, 1, 5, 12)), '05/01');
      expect(formatDayMonthHour(DateTime.utc(2030, 1, 5, 3)), '05/01 às 0h');
    });

    test('reviewCooldown = duration.value(N, \'d\') da trava nas Rules '
        '(paridade)', () {
      final rules = File('../firebase/firestore.rules').readAsStringSync();
      final block = RegExp(
        r'match /reviewLocks/\{placeId\} \{([\s\S]*?)\n      \}',
      ).firstMatch(rules);
      expect(block, isNotNull, reason: 'match /reviewLocks ausente');
      final durations = RegExp(
        r"duration\.value\((\d+), 'd'\)",
      ).allMatches(block!.group(1)!).toList();
      expect(durations, hasLength(1));
      expect(int.parse(durations.single.group(1)!), reviewCooldown.inDays);
      expect(reviewCooldown, Duration(days: reviewCooldown.inDays));
    });
  });
}
