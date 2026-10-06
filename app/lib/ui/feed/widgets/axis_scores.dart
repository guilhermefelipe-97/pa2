import 'package:flutter/material.dart';

import '../../../domain/models/scores.dart';

/// Os 3 eixos lado a lado: 🍽️ comida, ✨ ambiente, 🤝 atendimento. Sempre
/// três valores — nunca uma nota única.
class AxisScores extends StatelessWidget {
  AxisScores.scores(Scores scores, {super.key, this.dense = false})
    : food = '${scores.food}',
      ambience = '${scores.ambience}',
      service = '${scores.service}';

  AxisScores.averages(AxisAverages averages, {super.key, this.dense = false})
    : food = formatAverage(averages.food),
      ambience = formatAverage(averages.ambience),
      service = formatAverage(averages.service);

  final String food;
  final String ambience;
  final String service;

  /// Pílulas menores (linhas compactas do card).
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: dense ? 4 : 8,
      runSpacing: dense ? 4 : 6,
      children: [
        _AxisPill(emoji: '🍽️', label: 'Comida', value: food, dense: dense),
        _AxisPill(emoji: '✨', label: 'Ambiente', value: ambience, dense: dense),
        _AxisPill(
          emoji: '🤝',
          label: 'Atendimento',
          value: service,
          dense: dense,
        ),
      ],
    );
  }
}

class _AxisPill extends StatelessWidget {
  const _AxisPill({
    required this.emoji,
    required this.label,
    required this.value,
    required this.dense,
  });

  final String emoji;
  final String label;
  final String value;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Tooltip (toque longo/hover) revela o nome do eixo para quem vê só o
    // emoji; o Semantics dá o texto completo ao leitor de tela.
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        label: '$label $value de 5',
        excludeSemantics: true,
        child: Container(
          padding: dense
              ? const EdgeInsets.symmetric(horizontal: 7, vertical: 1)
              : const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$emoji $value',
            style: TextStyle(
              color: scheme.onSecondaryContainer,
              fontSize: dense ? 12 : 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
