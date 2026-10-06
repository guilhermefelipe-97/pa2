import 'models/day_period.dart';

/// Tempo relativo em português curto. Função pura.
///
/// - menos de 1 min (ou no futuro, relógio do aparelho atrasado): "agora"
/// - menos de 1 h: "há N min"
/// - mesmo dia do calendário em Natal (UTC-3): "há N h"
/// - dia anterior do calendário: "ontem"
/// - 2 a 7 dias de calendário: "há N dias"
/// - depois disso: data curta em Natal ("20/09", ou "25/12/2025" se for de
///   outro ano)
///
/// Os dias são contados no calendário de Natal, não por horas decorridas:
/// 23:00 de anteontem visto às 00:30 é "há 2 dias", mesmo sendo só 25,5 h.
String relativeTime(DateTime at, DateTime now) => switch (_elapsed(at, now)) {
  _Now() => 'agora',
  _Minutes(:final n) => 'há $n min',
  _Hours(:final n) => 'há $n h',
  _Yesterday() => 'ontem',
  _Days(:final n) => 'há $n dias',
  _Date(:final local, :final sameYear) =>
    sameYear
        ? '${_two(local.day)}/${_two(local.month)}'
        : '${_two(local.day)}/${_two(local.month)}/${local.year}',
};

/// Mesmo critério de [relativeTime], por extenso para leitores de tela:
/// "agora", "há 1 minuto", "há 2 horas", "ontem", "há 3 dias",
/// "em 20 de setembro" (ou "em 25 de dezembro de 2025").
String relativeTimeSpoken(DateTime at, DateTime now) =>
    switch (_elapsed(at, now)) {
      _Now() => 'agora',
      _Minutes(:final n) => n == 1 ? 'há 1 minuto' : 'há $n minutos',
      _Hours(:final n) => n == 1 ? 'há 1 hora' : 'há $n horas',
      _Yesterday() => 'ontem',
      _Days(:final n) => 'há $n dias',
      _Date(:final local, :final sameYear) =>
        'em ${local.day} de ${_months[local.month - 1]}'
            '${sameYear ? '' : ' de ${local.year}'}',
    };

const _months = [
  'janeiro',
  'fevereiro',
  'março',
  'abril',
  'maio',
  'junho',
  'julho',
  'agosto',
  'setembro',
  'outubro',
  'novembro',
  'dezembro',
];

String _two(int v) => v.toString().padLeft(2, '0');

sealed class _Elapsed {
  const _Elapsed();
}

class _Now extends _Elapsed {
  const _Now();
}

class _Minutes extends _Elapsed {
  const _Minutes(this.n);
  final int n;
}

class _Hours extends _Elapsed {
  const _Hours(this.n);
  final int n;
}

class _Yesterday extends _Elapsed {
  const _Yesterday();
}

class _Days extends _Elapsed {
  const _Days(this.n);
  final int n;
}

class _Date extends _Elapsed {
  const _Date(this.local, {required this.sameYear});

  /// Data de parede em Natal.
  final DateTime local;
  final bool sameYear;
}

_Elapsed _elapsed(DateTime at, DateTime now) {
  final diff = now.difference(at);
  if (diff.inMinutes < 1) return const _Now();
  if (diff.inHours < 1) return _Minutes(diff.inMinutes);

  final local = _natal(at);
  final nowLocal = _natal(now);
  final days = _calendarDay(nowLocal).difference(_calendarDay(local)).inDays;
  if (days <= 0) return _Hours(diff.inHours);
  if (days == 1) return const _Yesterday();
  if (days <= 7) return _Days(days);
  return _Date(local, sameYear: local.year == nowLocal.year);
}

/// Horário de parede em Natal, representado como DateTime UTC (independe do
/// fuso da máquina).
DateTime _natal(DateTime t) => t.toUtc().add(DayPeriod.utcOffset);

/// Meia-noite (UTC, sem horário de verão) do dia de [t]: diferença exata em dias.
DateTime _calendarDay(DateTime t) => DateTime.utc(t.year, t.month, t.day);
