import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/relative_time.dart';

/// Horário de parede em Natal (UTC-3) como instante UTC.
DateTime natal(int y, int mo, int d, [int h = 0, int mi = 0]) =>
    DateTime.utc(y, mo, d, h, mi).add(const Duration(hours: 3));

void main() {
  final now = natal(2026, 9, 28, 12); // 12h em Natal

  String rel(Duration ago) => relativeTime(now.subtract(ago), now);

  test(
    'menos de 1 minuto (e horário no futuro por relógio adiantado): "agora"',
    () {
      expect(rel(Duration.zero), 'agora');
      expect(rel(const Duration(seconds: 59)), 'agora');
      expect(relativeTime(now.add(const Duration(minutes: 3)), now), 'agora');
    },
  );

  test('minutos: "há N min"', () {
    expect(rel(const Duration(minutes: 1)), 'há 1 min');
    expect(rel(const Duration(minutes: 5)), 'há 5 min');
    expect(rel(const Duration(minutes: 59, seconds: 59)), 'há 59 min');
  });

  test('mesmo dia em Natal: "há N h"', () {
    expect(rel(const Duration(hours: 1)), 'há 1 h');
    expect(rel(const Duration(hours: 2, minutes: 30)), 'há 2 h');
    expect(rel(const Duration(hours: 12)), 'há 12 h'); // 00:00 de hoje
  });

  test('dia anterior no calendário de Natal: "ontem" (não por 24–48 h)', () {
    expect(
      rel(const Duration(hours: 12, minutes: 1)),
      'ontem',
    ); // 23:59 de ontem
    expect(rel(const Duration(hours: 36)), 'ontem'); // 00:00 de ontem
    // 23:00 de ontem visto às 00:30: só 1,5 h, mas já é "ontem".
    expect(
      relativeTime(natal(2026, 9, 27, 23), natal(2026, 9, 28, 0, 30)),
      'ontem',
    );
  });

  test('2 a 7 dias de calendário: "há N dias"', () {
    expect(rel(const Duration(hours: 48)), 'há 2 dias'); // exatamente 48 h
    // 23:00 de anteontem visto às 00:30: 25,5 h, mas 2 dias de calendário.
    expect(
      relativeTime(natal(2026, 9, 26, 23), natal(2026, 9, 28, 0, 30)),
      'há 2 dias',
    );
    expect(rel(const Duration(days: 3, hours: 5)), 'há 3 dias');
    expect(rel(const Duration(days: 7)), 'há 7 dias'); // exatamente 7 dias
  });

  test(
    'depois de 7 dias: data curta no fuso de Natal (dd/mm; ano se diferente)',
    () {
      expect(rel(const Duration(days: 8)), '20/09');
      // 02:00Z do dia 1º ainda é dia 31 à noite em Natal (UTC-3)
      expect(relativeTime(DateTime.utc(2026, 9, 1, 2), now), '31/08');
      expect(relativeTime(natal(2025, 12, 25, 15), now), '25/12/2025');
    },
  );

  test('usa o calendário de Natal, não o de UTC nem o da máquina', () {
    // 02:00Z e 03:30Z do dia 28 são o mesmo dia em UTC, mas em Natal são
    // 23:00 do dia 27 e 00:30 do dia 28: "ontem", não "há 1 h".
    final at = DateTime.utc(2026, 9, 28, 2);
    final seen = DateTime.utc(2026, 9, 28, 3, 30);
    expect(relativeTime(at, seen), 'ontem');
    // O mesmo instante em horário local da máquina (qualquer fuso) dá o mesmo.
    expect(relativeTime(at.toLocal(), seen.toLocal()), 'ontem');
    expect(relativeTime(at.toLocal(), seen), 'ontem');
  });
}
