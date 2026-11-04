import 'package:flutter/material.dart';
import '../../data/repositories/privacy_repository.dart';

class SilentField extends StatelessWidget {
  const SilentField({
    super.key,
    required this.value,
    required this.onChanged,
    this.expandedDescription = false,
  });
  final bool expandedDescription;
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) => expandedDescription
      ? Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.visibility_off_outlined, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Não publicar no feed Amigos')),
                  Switch(value: value, onChanged: onChanged),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Sua avaliação continuará identificada com seu nome na ficha do local e no seu perfil público, mas não aparecerá no feed de atualizações dos seus amigos.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        )
      : Row(
          children: [
            Switch(value: value, onChanged: onChanged),
            const Expanded(child: Text('Modo silencioso · só no feed Amigos')),
            IconButton(
              tooltip: 'Entender o modo silencioso',
              icon: const Icon(Icons.info_outline),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Modo silencioso'),
                  content: const Text(silentScope),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Entendi'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
}
