/// Período do dia em que a avaliação foi feita (F02).
///
/// Nunca é gravado: é sempre derivado do `createdAt` (timestamp do servidor)
/// no fuso de Natal/RN (UTC-3, America/Fortaleza, sem horário de verão).
enum DayPeriod {
  madrugada('Madrugada'),
  manha('Manhã'),
  almoco('Almoço'),
  tarde('Tarde'),
  noite('Noite');

  const DayPeriod(this.label);

  final String label;

  static const Duration utcOffset = Duration(hours: -3);

  /// madrugada 0–5, manhã 5–11, almoço 11–14, tarde 14–18, noite 18–24
  /// (início inclusivo, fim exclusivo), em UTC-3.
  static DayPeriod fromTimestamp(DateTime timestamp) {
    final hour = _toNatalTime(timestamp).hour;
    if (hour < 5) return DayPeriod.madrugada;
    if (hour < 11) return DayPeriod.manha;
    if (hour < 14) return DayPeriod.almoco;
    if (hour < 18) return DayPeriod.tarde;
    return DayPeriod.noite;
  }
}

/// [timestamp] no fuso de Natal/RN (UTC-3), como um `DateTime` em UTC cujos
/// campos (dia, mês, hora) já são os de Natal. Só para exibir; fora deste
/// arquivo, use as funções de formatação.
DateTime _toNatalTime(DateTime timestamp) =>
    timestamp.toUtc().add(DayPeriod.utcOffset);

String _two(int n) => n.toString().padLeft(2, '0');

/// "12/10": dia e mês de [timestamp] em UTC-3.
String formatDayMonth(DateTime timestamp) {
  final t = _toNatalTime(timestamp);
  return '${_two(t.day)}/${_two(t.month)}';
}

/// "11/11 às 20h" (ou "11/11 às 20h05"): dia, mês e hora de [timestamp] em
/// UTC-3, sempre com a hora; minutos só quando não são zero. Segundos são
/// descartados.
String formatDayMonthHour(DateTime timestamp) {
  final t = _toNatalTime(timestamp);
  final minutes = t.minute == 0 ? '' : _two(t.minute);
  return '${formatDayMonth(timestamp)} às ${t.hour}h$minutes';
}
