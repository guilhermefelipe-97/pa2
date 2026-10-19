import 'models/place_activity.dart';
import 'price_band.dart';

/// Relatos de preço mais antigos que isto não entram no agregado (F27):
/// preço de anos atrás não diz se cabe no orçamento hoje. Única fonte do
/// "últimos 12 meses" mostrado no detalhe.
const Duration priceReportMaxAge = Duration(days: 365);

/// Como o detalhe descreve a janela do agregado.
const String priceReportWindowLabel =
    'Considera os relatos dos últimos 12 meses (o mais recente de cada '
    'pessoa).';

/// "1 relato", "3 relatos".
String priceReportsLabel(int count) =>
    count == 1 ? '1 relato' : '$count relatos';

/// Chip do card, do Perto e do detalhe: "R$ 30–60 por pessoa · 2 relatos".
/// [countLabel] troca a contagem (o detalhe diz de quem são os relatos).
String priceChipLabel(PriceSummary summary, {String? countLabel}) =>
    '${summary.typical.perPersonLabel} · '
    '${countLabel ?? priceReportsLabel(summary.count)}';

/// O que o leitor de tela fala do chip: "De 30 a 60 reais por pessoa, 2
/// relatos".
String priceChipSemantics(PriceSummary summary, {String? countLabel}) =>
    '${summary.typical.spokenLabel}, '
    '${countLabel ?? priceReportsLabel(summary.count)}';

/// Preço relatado num local (F27): o relato mais recente de cada pessoa
/// (avaliação ou visita com faixa) dos últimos 12 meses, a faixa típica
/// (mediana; empate → a mais baixa), a distribuição e a dispersão. Só com as
/// idas que quem chama passou — amigos e o próprio usuário; nunca preço
/// anônimo.
class PriceSummary {
  PriceSummary._(this.reports, this.typical, this.distribution);

  /// `null` quando ninguém informou o preço nos 12 meses antes de [now].
  static PriceSummary? of(
    Iterable<PlaceActivity> activities, {
    required DateTime now,
  }) {
    final oldest = now.subtract(priceReportMaxAge);
    final latest = <String, PlaceActivity>{};
    for (final a in activities) {
      if (a.priceBand == null || a.createdAt.isBefore(oldest)) continue;
      final current = latest[a.authorId];
      if (current == null || _replaces(a, current)) latest[a.authorId] = a;
    }
    if (latest.isEmpty) return null;
    final reports = latest.values.toList()
      ..sort((a, b) {
        final byDate = b.createdAt.compareTo(a.createdAt);
        return byDate != 0 ? byDate : a.authorId.compareTo(b.authorId);
      });
    final bands = [for (final r in reports) r.priceBand!]
      ..sort((a, b) => a.value.compareTo(b.value));
    // Mediana; com número par de relatos, a mais baixa das duas do meio.
    final typical = bands[(bands.length - 1) ~/ 2];
    final distribution = {for (final b in PriceBand.values) b: 0};
    for (final b in bands) {
      distribution[b] = distribution[b]! + 1;
    }
    return PriceSummary._(
      List.unmodifiable(reports),
      typical,
      Map.unmodifiable(distribution),
    );
  }

  /// [a] substitui [b] como o relato da pessoa: é mais recente; com o
  /// mesmo `createdAt`, tem a faixa maior e depois o maior id
  /// (determinístico, não depende da ordem da leitura).
  static bool _replaces(PlaceActivity a, PlaceActivity b) {
    final byDate = a.createdAt.compareTo(b.createdAt);
    if (byDate != 0) return byDate > 0;
    final byBand = a.priceBand!.value.compareTo(b.priceBand!.value);
    if (byBand != 0) return byBand > 0;
    return a.id.compareTo(b.id) > 0;
  }

  /// Um relato por pessoa (o mais recente dela), do mais recente para o
  /// mais antigo.
  final List<PlaceActivity> reports;

  /// Faixa típica: mediana das faixas (empate → a mais baixa).
  final PriceBand typical;

  /// Quantas pessoas relataram cada faixa (todas as 5 faixas presentes).
  final Map<PriceBand, int> distribution;

  int get count => reports.length;

  /// Menor faixa relatada.
  PriceBand get lowest =>
      PriceBand.values.firstWhere((b) => distribution[b]! > 0);

  /// Maior faixa relatada.
  PriceBand get highest =>
      PriceBand.values.lastWhere((b) => distribution[b]! > 0);

  /// "varia de até R$ 30 a R$ 150+" quando os relatos cobrem faixas a 2
  /// posições ou mais de distância (a mediana sozinha esconderia isso);
  /// `null` caso contrário.
  String? get spreadLabel => highest.index - lowest.index >= 2
      ? 'varia de ${lowest.label} a ${highest.label}'
      : null;
}
