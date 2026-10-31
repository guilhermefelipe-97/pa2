import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../routing/routes.dart';

class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Configurações',
    icon: const Icon(Icons.settings_outlined),
    onPressed: () => context.push(Routes.settings),
  );
}

/// Carregamento sem dados simulados; um único anúncio para leitores de tela.
class EditorialLoading extends StatelessWidget {
  const EditorialLoading({super.key});
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHigh;
    Widget bar(double height) => Container(
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
    );
    return Semantics(
      label: 'Carregando conteúdo',
      liveRegion: true,
      child: ExcludeSemantics(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const LinearProgressIndicator(),
            const SizedBox(height: 24),
            for (var i = 0; i < 2; i++)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      bar(160),
                      const SizedBox(height: 16),
                      bar(24),
                      const SizedBox(height: 8),
                      bar(16),
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

/// Hierarquia editorial compartilhada; cada tela mantém seus dados e ações.
class EditorialHeading extends StatelessWidget {
  const EditorialHeading({
    super.key,
    required this.eyebrow,
    required this.title,
    this.description,
  });
  final String eyebrow;
  final String title;
  final String? description;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow.toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.secondary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(title, style: theme.textTheme.headlineSmall),
          if (description != null) ...[
            const SizedBox(height: 8),
            Text(description!, style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}
