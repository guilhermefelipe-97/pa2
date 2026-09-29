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
String relativeTime(DateTime at, DateTime now) {
  final diff = now.difference(at);
  if (diff.inMinutes < 1) return 'agora';
  if (diff.inHours < 1) return 'há ${diff.inMinutes} min';

  final local = _natal(at);
  final nowLocal = _natal(now);
  final days = _calendarDay(nowLocal).difference(_calendarDay(local)).inDays;
  if (days <= 0) return 'há ${diff.inHours} h';
  if (days == 1) return 'ontem';
  if (days <= 7) return 'há $days dias';

  String two(int v) => v.toString().padLeft(2, '0');
  final short = '${two(local.day)}/${two(local.month)}';
  return local.year == nowLocal.year ? short : '$short/${local.year}';
}

/// Horário de parede em Natal, representado como DateTime UTC (independe do
/// fuso da máquina).
DateTime _natal(DateTime t) => t.toUtc().add(DayPeriod.utcOffset);

/// Meia-noite (UTC, sem horário de verão) do dia de [t]: diferença exata em dias.
DateTime _calendarDay(DateTime t) => DateTime.utc(t.year, t.month, t.day);
