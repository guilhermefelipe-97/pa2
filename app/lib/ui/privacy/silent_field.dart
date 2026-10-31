import 'package:flutter/material.dart';
import '../../data/repositories/privacy_repository.dart';

/// Controle compacto; alcance completo fica disponível ao lado da escolha.
class SilentField extends StatelessWidget {
  const SilentField({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) => Row(
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
