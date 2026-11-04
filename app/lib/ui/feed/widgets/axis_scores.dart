import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/models/scores.dart';

/// Texto de eixo sem nota: no seletor da avaliação e nas médias (F14).
const String noScoresLabel = 'sem notas';

/// Um eixo mostrado: valor já formatado ("4", "4,5") ou `null` quando não
/// há nota; [count] só nas médias (quantas avaliações têm o eixo) e
/// [showCount] quando essa contagem difere do total do local.
typedef _AxisValue = ({String? value, int? count, bool showCount});

/// Os eixos lado a lado: 🍽️ comida, ✨ ambiente, 🤝 atendimento — nunca uma
/// nota única. Numa avaliação, mostra só os eixos avaliados (F14: eixo sem
/// nota não aparece nem é falado). Nas médias, os 3 aparecem; eixo sem
/// nenhuma nota no local mostra [noScoresLabel] (nunca zero).
class AxisScores extends StatelessWidget {
  AxisScores.scores(
    Scores scores, {
    super.key,
    this.dense = false,
    this.stitchLayout = false,
  }) : _food = _one(scores.food),
       _ambience = _one(scores.ambience),
       _service = _one(scores.service),
       _isAverage = false;

  AxisScores.averages(AxisAverages averages, {super.key, this.dense = false})
    : _food = _avg(averages.food, averages.total),
      _ambience = _avg(averages.ambience, averages.total),
      _service = _avg(averages.service, averages.total),
      _isAverage = true,
      stitchLayout = false;

  static _AxisValue _one(int? score) =>
      (value: score?.toString(), count: null, showCount: false);

  static _AxisValue _avg(AxisAverage a, int total) => (
    value: a.value == null ? null : formatAverage(a.value!),
    count: a.count,
    // "(n)" visível só quando nem todas as avaliações têm o eixo; na
    // semântica a contagem é sempre falada.
    showCount: a.count != total,
  );

  final _AxisValue _food;
  final _AxisValue _ambience;
  final _AxisValue _service;
  final bool _isAverage;

  /// Pílulas menores (linhas compactas do card).
  final bool dense;
  final bool stitchLayout;

  @override
  Widget build(BuildContext context) {
    final axes = [
      ('🍽️', 'Comida', _food),
      ('✨', 'Ambiente', _ambience),
      ('🤝', 'Atendimento', _service),
    ];
    if (stitchLayout) {
      final theme = Theme.of(context);
      Widget cell(String label, _AxisValue axis) => Semantics(
        container: true,
        label: axis.value == null
            ? '$label não avaliado'
            : '$label ${axis.value} de 5',
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
              ),
              const SizedBox(height: 4),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 3,
                children: [
                  if (axis.value != null)
                    Icon(
                      Icons.star,
                      size: 14,
                      color: theme.colorScheme.secondary,
                    ),
                  Text(
                    axis.value == null ? 'Não avaliado' : '${axis.value},0',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
        ),
        child: MediaQuery.textScalerOf(context).scale(1) > 1.3
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (_, label, axis) in axes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: cell(label, axis),
                    ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (_, label, axis) in axes)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: cell(label, axis),
                      ),
                    ),
                ],
              ),
      );
    }
    return Wrap(
      spacing: dense ? 4 : 8,
      runSpacing: dense ? 4 : 6,
      children: [
        for (final (emoji, label, axis) in axes)
          if (_isAverage || axis.value != null)
            _AxisPill(
              emoji: emoji,
              label: label,
              value: axis.value,
              count: axis.count,
              showCount: axis.showCount,
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
    required this.count,
    required this.showCount,
    required this.dense,
  });

  final String emoji;
  final String label;

  /// `null` = sem notas neste eixo (só nas médias).
  final String? value;

  /// Quantas avaliações compõem a média; `null` numa avaliação individual.
  final int? count;

  /// Mostra "(n)" ao lado do valor.
  final bool showCount;
  final bool dense;

  /// Menor fonte das pílulas, inclusive a contagem no modo denso.
  static const double minFontSize = 12;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fontSize = dense ? minFontSize : 14.0;
    final empty = value == null;
    final semantics = empty
        ? '$label $noScoresLabel'
        : [
            '$label $value de 5',
            if (count != null) reviewCountLabel(count!),
          ].join(', ');
    // Tooltip (toque longo/hover) revela o nome do eixo para quem vê só o
    // emoji; o Semantics dá o texto completo ao leitor de tela.
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        label: semantics,
        excludeSemantics: true,
        child: Container(
          padding: dense
              ? const EdgeInsets.symmetric(horizontal: 7, vertical: 1)
              : const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: empty
                ? scheme.surfaceContainerHighest
                : scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Wrap(
            children: [
              Text(
                empty ? '$label $noScoresLabel' : '$label $value',
                style: TextStyle(
                  color: empty
                      ? scheme.onSurfaceVariant
                      : scheme.onSecondaryContainer,
                  fontSize: fontSize,
                  fontWeight: empty ? FontWeight.w500 : FontWeight.w700,
                ),
              ),
              if (!empty && count != null && showCount)
                Text(
                  ' ($count)',
                  // Mesma cor do valor (contraste AA); só o peso diminui.
                  style: TextStyle(
                    color: scheme.onSecondaryContainer,
                    fontSize: math.max(minFontSize, fontSize - 2),
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
