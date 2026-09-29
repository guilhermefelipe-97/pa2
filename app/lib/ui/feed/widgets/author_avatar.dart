import 'package:flutter/material.dart';

import '../../core/stable_hash.dart';
import '../../core/theme.dart';

/// Avatar com a inicial do nome (sem foto de perfil ainda). A cor é estável
/// por pessoa.
class AuthorAvatar extends StatelessWidget {
  const AuthorAvatar({
    super.key,
    required this.id,
    required this.name,
    this.radius = 16,
  });

  final String id;
  final String name;
  final double radius;

  static const _colors = [
    NaAreaColors.coralEscuro,
    NaAreaColors.azulMar,
    Color(0xFFB5651D),
    Color(0xFF7A4EAB),
    Color(0xFF2E8B57),
  ];

  static String initial(String name) {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: _colors[stableHash(id) % _colors.length],
      child: Text(
        initial(name),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.9,
        ),
      ),
    );
  }
}

/// Até 3 avatares sobrepostos e "+N" (no máximo "+99") para o resto. É só
/// decorativo para leitores de tela: a frase "A e B foram aqui" já nomeia
/// as pessoas.
class AuthorAvatarStack extends StatelessWidget {
  const AuthorAvatarStack({
    super.key,
    required this.authors,
    required this.ringColor,
    this.radius = 14,
  });

  /// (id, nome), do mais recente para o mais antigo, sem repetição.
  final List<({String id, String name})> authors;

  /// Cor do anel entre avatares: a do fundo onde a pilha está desenhada.
  final Color ringColor;
  final double radius;

  static const int maxShown = 3;

  static String overflowLabel(int extra) => extra > 99 ? '+99' : '+$extra';

  @override
  Widget build(BuildContext context) {
    if (authors.isEmpty) return const SizedBox.shrink();
    final shown = authors.take(maxShown).toList();
    final extra = authors.length - shown.length;
    final step = radius * 1.4;
    final count = shown.length + (extra > 0 ? 1 : 0);
    Widget ringed(Widget child) => Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: ringColor, shape: BoxShape.circle),
      child: child,
    );
    return ExcludeSemantics(
      child: SizedBox(
        width: step * (count - 1) + (radius + 2) * 2,
        height: (radius + 2) * 2,
        child: Stack(
          children: [
            for (var i = 0; i < shown.length; i++)
              Positioned(
                left: step * i,
                child: ringed(
                  AuthorAvatar(
                    id: shown[i].id,
                    name: shown[i].name,
                    radius: radius,
                  ),
                ),
              ),
            if (extra > 0)
              Positioned(
                left: step * shown.length,
                child: ringed(
                  CircleAvatar(
                    radius: radius,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHigh,
                    child: Text(
                      overflowLabel(extra),
                      style: TextStyle(
                        fontSize: radius * 0.7,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
