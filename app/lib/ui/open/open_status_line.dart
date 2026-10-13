import 'package:flutter/material.dart';

import '../../domain/open_status.dart';

/// Linha de status "Aberto · confirmado por Ana há 20 min" (F20), com ícone
/// por tipo e o texto por extenso para leitores de tela. Sempre diz quem
/// informou.
class OpenStatusLine extends StatelessWidget {
  const OpenStatusLine({
    super.key,
    required this.status,
    required this.now,
    this.currentUserId,
    this.dense = false,
  });

  final OpenStatus status;
  final DateTime now;
  final String? currentUserId;

  /// Versão compacta (itens do Perto).
  final bool dense;

  static IconData iconFor(OpenStatusKind kind) => switch (kind) {
    OpenStatusKind.open => Icons.storefront,
    OpenStatusKind.closed => Icons.block,
    OpenStatusKind.divergent => Icons.help_outline,
  };

  static Color colorFor(OpenStatusKind kind, ColorScheme scheme) =>
      switch (kind) {
        OpenStatusKind.open => const Color(0xFF2E7D32),
        OpenStatusKind.closed => scheme.error,
        OpenStatusKind.divergent => scheme.onSurfaceVariant,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = colorFor(status.kind, theme.colorScheme);
    final style =
        (dense ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium)
            ?.copyWith(color: color, fontWeight: FontWeight.w700);
    return Semantics(
      label: openStatusSemantics(status, now, currentUserId: currentUserId),
      excludeSemantics: true,
      child: Row(
        children: [
          Icon(iconFor(status.kind), size: dense ? 16 : 20, color: color),
          SizedBox(width: dense ? 4 : 8),
          Expanded(
            child: Text(
              openStatusLabel(status, now, currentUserId: currentUserId),
              maxLines: dense ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}
