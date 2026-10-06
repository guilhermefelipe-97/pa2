import 'package:flutter/material.dart';

import '../../../domain/feed.dart';
import '../../../domain/relative_time.dart';
import '../../core/save_button.dart';
import 'place_photo.dart';
import 'trust_sources.dart';

/// "Bairro · Categoria", pulando partes vazias.
String placeSubtitle(String neighborhood, String category) =>
    [neighborhood, category].where((s) => s.trim().isNotEmpty).join(' · ');

/// Autores distintos (id, nome) do mais recente para o mais antigo.
List<({String id, String name})> distinctAuthors(FeedItem item) {
  final seen = <String>{};
  return [
    for (final r in item.reviews)
      if (seen.add(r.authorId)) (id: r.authorId, name: r.authorName),
  ];
}

/// Card do feed "Amigos foram aqui".
class FeedCard extends StatelessWidget {
  const FeedCard({
    super.key,
    required this.item,
    required this.now,
    this.onTap,
    this.isFollowing,
    this.onOpenPerson,
  });

  final FeedItem item;
  final DateTime now;
  final VoidCallback? onTap;

  /// Quem o leitor segue (selo "você segue" no bloco "Quem foi").
  final bool Function(String uid)? isFollowing;

  /// Toque numa pessoa do bloco "Quem foi": abre o perfil dela.
  final void Function(TrustSource source)? onOpenPerson;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final place = item.place;
    final commented = item.latestComment;
    final subtitle = placeSubtitle(place.neighborhood, place.category);

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 16),
      child: Stack(
        children: [
          Semantics(
            button: true,
            label: 'Abrir ${item.placeName}',
            child: InkWell(
              onTap: onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Hero(
                      tag: 'place-photo-${place.id}',
                      // Foto mais recente de um amigo ali; sem ela, a do
                      // catálogo; sem nenhuma, o fallback da categoria.
                      child: PlacePhoto(
                        place: place,
                        friendPhoto: item.latestPhoto,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.placeName, style: theme.textTheme.titleLarge),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                Icons.place_outlined,
                                size: 16,
                                color: scheme.tertiary,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  subtitle,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: scheme.tertiary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 10),
                        // Quem foi: cada nota tem dono (sem média no card).
                        TrustSources(
                          item: item,
                          now: now,
                          isFollowing: isFollowing,
                          onOpenPerson: onOpenPerson,
                          onShowAll: onTap,
                        ),
                        // O comentário citado pode não ser da visita mais
                        // recente: leva o próprio autor e tempo.
                        if (commented != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(14),
                              border: Border(
                                left: BorderSide(
                                  color: scheme.secondary,
                                  width: 3,
                                ),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '“${commented.comment}”',
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '— ${commented.authorName} · ${relativeTime(commented.createdAt, now)}',
                                  style: theme.textTheme.labelMedium,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Fora do InkWell: salvar não abre o detalhe. Local fora do
          // catálogo não pode ser salvo (as Rules exigem o doc em places).
          if (place.inCatalog)
            Positioned(
              top: 8,
              right: 8,
              child: SaveButton(
                placeId: place.id,
                style: SaveButtonStyle.onImage,
              ),
            ),
        ],
      ),
    );
  }
}
