import 'package:flutter/material.dart';

import '../../domain/price_band.dart';
import '../../domain/price_summary.dart';
import '../../domain/text_format.dart';
import '../feed/widgets/trust_sources.dart' show displayAuthorName;

/// Sem relatos de preço no local (F27).
const String noPriceText = 'Ninguém informou o preço ainda';

/// Título da seção.
const String priceSectionTitle = 'Quanto se gasta por pessoa';

/// Pessoas no seletor "Vai rachar?" (F27): de 2 a 12, começa em 2.
const int minSplitPeople = 2;
const int maxSplitPeople = 12;
const int defaultSplitPeople = 2;

/// "Relatado por Ana", "... Ana e Bia", "... Ana, Bia e mais 3".
String reportersLabel(List<String> names) =>
    'Relatado por ${namesLabel(names)}';

/// "De 30 a 60 reais por pessoa: 2 relatos" (barra da distribuição).
String distributionSemantics(PriceBand band, int count) =>
    '${band.spokenLabel}: ${priceReportsLabel(count)}';

/// Preço no detalhe do local (F27): faixa típica com a contagem e quem
/// relatou, a dispersão quando os relatos variam muito, a distribuição por
/// faixa e a estimativa para rachar com seletor de pessoas (2–12, padrão
/// 2). Sem relatos, só "Ninguém informou o preço ainda".
class PriceSection extends StatefulWidget {
  const PriceSection({super.key, required this.summary, this.countLabel});

  final PriceSummary? summary;

  /// "3 relatos de amigos" (o detalhe sabe quais relatos são do usuário);
  /// o mesmo do chip do topo.
  final String? countLabel;

  @override
  State<PriceSection> createState() => _PriceSectionState();
}

class _PriceSectionState extends State<PriceSection> {
  int _people = defaultSplitPeople;

  void _setPeople(int value) =>
      setState(() => _people = value.clamp(minSplitPeople, maxSplitPeople));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final small = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final summary = widget.summary;
    final title = Semantics(
      header: true,
      child: Text(priceSectionTitle, style: theme.textTheme.labelLarge),
    );
    if (summary == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          const SizedBox(height: 4),
          Text(noPriceText, key: const Key('place-price-empty'), style: muted),
        ],
      );
    }
    final typical = summary.typical;
    final countLabel = widget.countLabel ?? priceReportsLabel(summary.count);
    final spread = summary.spreadLabel;
    final names = [
      for (final r in summary.reports) displayAuthorName(r.authorName),
    ];
    final maxCount = summary.distribution.values.fold<int>(
      1,
      (a, b) => b > a ? b : a,
    );
    return Column(
      key: const Key('place-price'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        title,
        const SizedBox(height: 4),
        Semantics(
          label: '${typical.spokenLabel}, $countLabel',
          excludeSemantics: true,
          child: Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(Icons.payments_outlined, size: 20, color: scheme.primary),
              Text(
                typical.perPersonLabel,
                key: const Key('place-price-typical'),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '· $countLabel',
                key: const Key('place-price-count'),
                style: muted,
              ),
            ],
          ),
        ),
        if (spread != null)
          Text(spread, key: const Key('place-price-spread'), style: muted),
        const SizedBox(height: 2),
        Text(
          reportersLabel(names),
          key: const Key('place-price-reporters'),
          style: small,
        ),
        Text(
          priceReportWindowLabel,
          key: const Key('place-price-window'),
          style: small,
        ),
        const SizedBox(height: 10),
        for (final band in PriceBand.values)
          _DistributionBar(
            band: band,
            count: summary.distribution[band]!,
            maxCount: maxCount,
            highlighted: band == typical,
          ),
        const SizedBox(height: 12),
        Semantics(
          header: true,
          child: Text('Vai rachar?', style: theme.textTheme.labelLarge),
        ),
        Row(
          children: [
            IconButton(
              key: const Key('place-price-people-less'),
              tooltip: 'Menos pessoas',
              onPressed: _people > minSplitPeople
                  ? () => _setPeople(_people - 1)
                  : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            // Falado junto com a estimativa (uma região só, abaixo).
            Flexible(
              child: ExcludeSemantics(
                child: Text(
                  '$_people pessoas',
                  key: const Key('place-price-people'),
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            ),
            IconButton(
              key: const Key('place-price-people-more'),
              tooltip: 'Mais pessoas',
              onPressed: _people < maxSplitPeople
                  ? () => _setPeople(_people + 1)
                  : null,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
        Semantics(
          key: const Key('place-price-split-live'),
          liveRegion: true,
          label: splitEstimateSpoken(typical, _people),
          excludeSemantics: true,
          child: Text(
            splitEstimateLabel(typical, _people),
            key: const Key('place-price-split'),
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text('Estimativa pela faixa típica de quem foi.', style: small),
      ],
    );
  }
}

/// Uma faixa da distribuição: rótulo, barra proporcional e contagem. Sem
/// larguras fixas: com fonte grande o rótulo quebra linha em vez de
/// estourar.
class _DistributionBar extends StatelessWidget {
  const _DistributionBar({
    required this.band,
    required this.count,
    required this.maxCount,
    required this.highlighted,
  });

  final PriceBand band;
  final int count;
  final int maxCount;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = theme.textTheme.bodySmall?.copyWith(
      fontWeight: highlighted ? FontWeight.w700 : null,
    );
    return Semantics(
      key: Key('place-price-bar-${band.value}'),
      label: distributionSemantics(band, count),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(flex: 3, child: Text(band.label, style: style)),
            const SizedBox(width: 8),
            Expanded(
              flex: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  height: 10,
                  color: scheme.surfaceContainerHighest,
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: count / maxCount,
                    child: Container(
                      color: highlighted ? scheme.primary : scheme.secondary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text('$count', textAlign: TextAlign.end, style: style),
          ],
        ),
      ),
    );
  }
}
