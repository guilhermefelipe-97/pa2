import 'package:flutter/material.dart';

import '../../../domain/price_summary.dart';

/// Preço relatado por quem foi (F27) no card do feed, no Perto e no topo do
/// detalhe: "R$ 30–60 por pessoa · 2 relatos". Só aparece com ao menos 1
/// relato (quem chama não monta o chip sem [summary]).
class PriceChip extends StatelessWidget {
  const PriceChip({
    super.key,
    required this.summary,
    this.countLabel,
    this.dense = false,
  });

  final PriceSummary summary;

  /// Troca a contagem ("2 relatos de amigos", no detalhe).
  final String? countLabel;

  /// Versão em linha (Perto): sem fundo.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = dense ? scheme.onSurfaceVariant : scheme.onSecondaryContainer;
    final style = theme.textTheme.bodySmall?.copyWith(
      color: color,
      fontWeight: FontWeight.w700,
    );
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.payments_outlined, size: 16, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            priceChipLabel(summary, countLabel: countLabel),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
    return Semantics(
      label: priceChipSemantics(summary, countLabel: countLabel),
      excludeSemantics: true,
      child: dense
          ? content
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: content,
            ),
    );
  }
}
