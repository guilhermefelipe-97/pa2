import 'package:flutter/material.dart';

/// Atribuição exigida pela ODbL para os dados vindos do OpenStreetMap.
class OsmCredit extends StatelessWidget {
  const OsmCredit({super.key, this.padding = EdgeInsets.zero});

  static const text = '© colaboradores do OpenStreetMap';

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Semantics(
        label: 'Dados de locais: colaboradores do OpenStreetMap, licença ODbL',
        excludeSemantics: true,
        child: Text(
          text,
          key: const Key('osm-credit'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
