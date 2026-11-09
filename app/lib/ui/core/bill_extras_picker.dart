import 'package:flutter/material.dart';

import '../../domain/bill_extras.dart';
import '../../domain/models/place_activity.dart';

/// Perguntas opcionais do F28 na avaliação e no "Voltei aqui": Sim/Não; um
/// toque na resposta escolhida limpa (sem resposta). Nunca bloqueia o envio.
class BillExtrasPicker extends StatelessWidget {
  const BillExtrasPicker({
    super.key,
    required this.couvert,
    required this.serviceFee,
    required this.onCouvert,
    required this.onServiceFee,
    this.enabled = true,
  });

  final bool? couvert, serviceFee;
  final ValueChanged<bool?> onCouvert, onServiceFee;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget question(
      String id,
      String text,
      bool? value,
      ValueChanged<bool?> onChanged,
    ) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(child: Text(text)),
          for (final (answer, label) in [(true, 'Sim'), (false, 'Não')])
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: ChoiceChip(
                key: Key('$id-$answer'),
                label: Text(label),
                selected: value == answer,
                onSelected: enabled
                    ? (_) => onChanged(value == answer ? null : answer)
                    : null,
              ),
            ),
        ],
      ),
    );
    final answered = [couvert, serviceFee].whereType<bool>().length;
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('bill-extras-picker'),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        initiallyExpanded: answered > 0,
        title: Text(
          'Na conta: couvert e taxa (opcional)',
          style: theme.textTheme.titleMedium,
        ),
        subtitle: answered == 0
            ? null
            : Text(answered == 1 ? '1 resposta' : '2 respostas'),
        children: [
          question('couvert', 'Cobrou couvert?', couvert, onCouvert),
          question(
            'service-fee',
            'A taxa de 10% veio na conta?',
            serviceFee,
            onServiceFee,
          ),
        ],
      ),
    );
  }
}

/// Bloco da ficha (F28): só aparece quando alguma pergunta tem conclusão.
class BillExtrasSection extends StatelessWidget {
  const BillExtrasSection({
    super.key,
    required this.activities,
    required this.now,
  });
  final List<PlaceActivity> activities;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final lines = [
      BillExtras.couvertLabel(BillExtras.couvert(activities, now: now)),
      BillExtras.serviceFeeLabel(BillExtras.serviceFee(activities, now: now)),
    ].whereType<String>().toList();
    if (lines.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      key: const Key('bill-extras-section'),
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(line, style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
          Text(
            'Últimos 12 meses, o relato mais recente de cada pessoa.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
