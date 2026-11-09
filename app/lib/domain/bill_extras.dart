import 'models/place_activity.dart';
import 'price_summary.dart' show priceReportMaxAge;

/// Conclusão de uma pergunta do F28 a partir dos relatos.
enum ExtraVerdict { yes, no, divided }

class ExtraSummary {
  const ExtraSummary(this.yes, this.no);
  final int yes, no;
  int get total => yes + no;

  /// `null` com menos de [BillExtras.minPeople] pessoas: sem conclusão.
  ExtraVerdict? get verdict {
    if (total < BillExtras.minPeople) return null;
    if (yes == no) return ExtraVerdict.divided;
    return yes > no ? ExtraVerdict.yes : ExtraVerdict.no;
  }

  int get majority => yes > no ? yes : no;
}

/// Couvert e taxa de 10% (F28), decididos pela usuária em 04/11/2026: o relato
/// mais recente de cada pessoa nos últimos 12 meses (mesma janela do preço,
/// F27); com 2 ou mais pessoas vale a maioria; empate é "relatos divergentes".
abstract final class BillExtras {
  static const int minPeople = 2;

  static ExtraSummary couvert(
    Iterable<PlaceActivity> activities, {
    required DateTime now,
  }) => _summary(activities, now, (a) => a.couvert);

  static ExtraSummary serviceFee(
    Iterable<PlaceActivity> activities, {
    required DateTime now,
  }) => _summary(activities, now, (a) => a.serviceFee);

  static ExtraSummary _summary(
    Iterable<PlaceActivity> activities,
    DateTime now,
    bool? Function(PlaceActivity) answer,
  ) {
    final oldest = now.subtract(priceReportMaxAge);
    final latest = <String, PlaceActivity>{};
    for (final a in activities) {
      if (answer(a) == null ||
          a.createdAt.isBefore(oldest) ||
          a.createdAt.isAfter(now)) {
        continue;
      }
      final current = latest[a.authorId];
      if (current == null ||
          a.createdAt.isAfter(current.createdAt) ||
          (a.createdAt == current.createdAt &&
              a.id.compareTo(current.id) > 0)) {
        latest[a.authorId] = a;
      }
    }
    var yes = 0, no = 0;
    for (final a in latest.values) {
      if (answer(a)!) {
        yes++;
      } else {
        no++;
      }
    }
    return ExtraSummary(yes, no);
  }

  static String _reports(int n) => n == 1 ? '1 relato' : '$n relatos';

  /// "Cobra couvert · 3 de 4 relatos", "Não cobra couvert · 2 de 2 relatos",
  /// "Couvert: relatos divergentes (1 sim, 1 não)" ou `null` sem conclusão.
  static String? couvertLabel(ExtraSummary s) => switch (s.verdict) {
    null => null,
    ExtraVerdict.yes => 'Cobra couvert · ${s.majority} de ${_reports(s.total)}',
    ExtraVerdict.no =>
      'Não cobra couvert · ${s.majority} de ${_reports(s.total)}',
    ExtraVerdict.divided =>
      'Couvert: relatos divergentes (${s.yes} sim, ${s.no} não)',
  };

  static String? serviceFeeLabel(ExtraSummary s) => switch (s.verdict) {
    null => null,
    ExtraVerdict.yes =>
      'Taxa de 10% vem na conta · ${s.majority} de ${_reports(s.total)}',
    ExtraVerdict.no =>
      'Taxa de 10% não vem na conta · ${s.majority} de ${_reports(s.total)}',
    ExtraVerdict.divided =>
      'Taxa de 10%: relatos divergentes (${s.yes} sim, ${s.no} não)',
  };
}
