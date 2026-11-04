import 'package:flutter/material.dart';

class NearbySkeleton extends StatelessWidget {
  const NearbySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget bar(double height, {double? width}) => Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
    );
    return Semantics(
      label: 'Carregando experiências próximas...',
      liveRegion: true,
      child: ExcludeSemantics(
        child: ListView(
          key: const Key('nearby-skeleton'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Carregando experiências próximas...',
              style: theme.textTheme.labelSmall,
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < 2; i++)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AspectRatio(aspectRatio: 2, child: bar(double.infinity)),
                      const SizedBox(height: 12),
                      bar(18, width: 180),
                      const SizedBox(height: 8),
                      bar(12, width: 120),
                      const SizedBox(height: 12),
                      bar(36),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
