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
    final hour = timestamp.toUtc().add(utcOffset).hour;
    if (hour < 5) return DayPeriod.madrugada;
    if (hour < 11) return DayPeriod.manha;
    if (hour < 14) return DayPeriod.almoco;
    if (hour < 18) return DayPeriod.tarde;
    return DayPeriod.noite;
  }
}
