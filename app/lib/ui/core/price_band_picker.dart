import 'package:flutter/material.dart';

import '../../domain/price_band.dart';

/// Título do campo de preço (F27), igual na avaliação e na visita.
const String priceBandQuestion = 'Quanto gastou por pessoa? (opcional)';

/// Dica dos limites que se tocam ("até R$ 30" e "R$ 30–60").
const String priceBandHint = 'Em caso de dúvida, escolha a faixa de cima.';

/// O que o leitor de tela fala de uma faixa do seletor: "Até 30 reais por
/// pessoa, selecionado".
String priceBandChipSemantics(PriceBand band, {required bool selected}) =>
    selected ? '${band.spokenLabel}, selecionado' : band.spokenLabel;

/// Seletor de faixa de preço por pessoa (F27): 5 chips; 1 toque escolhe, um
/// toque na faixa escolhida limpa (volta a não informado). Sempre opcional:
/// nunca bloqueia o envio. Título (cabeçalho), chips e dica ficam num grupo
/// só para o leitor de tela.
class PriceBandPicker extends StatelessWidget {
  const PriceBandPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final PriceBand? value;

  /// `null` = limpou.
  final ValueChanged<PriceBand?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      key: const Key('price-band-picker'),
      container: true,
      explicitChildNodes: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(priceBandQuestion, style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final band in PriceBand.values)
                _bandChip(band, selected: value == band),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            priceBandHint,
            key: const Key('price-band-hint'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bandChip(PriceBand band, {required bool selected}) {
    void toggle() => onChanged(selected ? null : band);
    return Semantics(
      key: Key('price-band-${band.value}'),
      container: true,
      button: true,
      enabled: enabled,
      selected: selected,
      label: priceBandChipSemantics(band, selected: selected),
      hint: selected && enabled ? 'Toque para limpar' : null,
      onTap: enabled ? toggle : null,
      excludeSemantics: true,
      child: ChoiceChip(
        label: Text(band.label),
        selected: selected,
        onSelected: enabled ? (_) => toggle() : null,
      ),
    );
  }
}
