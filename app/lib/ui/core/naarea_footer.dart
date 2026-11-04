import 'package:flutter/material.dart';

class NaAreaFooter extends StatelessWidget {
  const NaAreaFooter({super.key});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surface,
    child: SafeArea(
      top: false,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('NaÁrea', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                '© 2026. Todos os direitos reservados.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
