import 'package:flutter/material.dart';

import '../../../domain/models/visit.dart';
import '../../../domain/relative_time.dart';
import 'author_avatar.dart';
import 'trust_sources.dart' show displayAuthorName;

/// Rótulo de uma visita sem nota ("Voltei aqui", F15) nas listas.
const String visitTileLabel = 'Voltou aqui';

/// Uma visita no detalhe do local: autor e contexto (período · companhia ·
/// tempo), sem notas — nunca um número sem dono, nem um zero no lugar da
/// nota.
class VisitTile extends StatelessWidget {
  const VisitTile({
    super.key,
    required this.visit,
    required this.now,
    this.isOwn = false,
    this.onAuthorTap,
  });

  final Visit visit;
  final DateTime now;

  /// Visita do próprio usuário (aparece como "Você"): o toque é lido como
  /// "Abrir seu perfil".
  final bool isOwn;

  /// Toque na linha do autor: abre o perfil de quem voltou.
  final VoidCallback? onAuthorTap;

  static const double minTapTarget = 48;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final meta = visitMeta(visit, now);
    final tappable = onAuthorTap != null;
    final name = displayAuthorName(visit.authorName);

    Widget author = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: minTapTarget),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: AuthorAvatar(id: visit.authorId, name: name, radius: 18),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              name,
              style: tappable
                  ? theme.textTheme.titleMedium?.copyWith(
                      decoration: TextDecoration.underline,
                      decorationColor: theme.colorScheme.outlineVariant,
                    )
                  : theme.textTheme.titleMedium,
            ),
          ),
          if (tappable) const SizedBox(width: 8),
        ],
      ),
    );
    if (tappable) {
      author = Semantics(
        key: ValueKey('visit-author-${visit.id}'),
        button: true,
        label: isOwn ? 'Abrir seu perfil' : 'Abrir perfil de $name',
        excludeSemantics: true,
        onTap: onAuthorTap,
        child: InkWell(
          onTap: onAuthorTap,
          borderRadius: BorderRadius.circular(24),
          child: author,
        ),
      );
    }

    return Padding(
      key: ValueKey('visit-tile-${visit.id}'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          author,
          Padding(
            padding: const EdgeInsets.only(left: 48),
            child: Row(
              children: [
                Icon(Icons.replay, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 4),
                Flexible(child: Text('$visitTileLabel · $meta', style: muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Noite · Amigos · há 2 h": período, companhia (se houver) e tempo.
String visitMeta(Visit v, DateTime now) => [
  v.dayPeriod.label,
  if (v.companion != null) v.companion!.label,
  relativeTime(v.createdAt, now),
].join(' · ');
