import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../domain/feed.dart';
import '../../../domain/relative_time.dart';
import '../../../routing/routes.dart';
import '../../core/save_button.dart';
import '../../dietary/food_tag_chips.dart';
import 'author_avatar.dart';
import 'place_photo.dart';
import 'price_chip.dart';
import 'trust_sources.dart';

String placeSubtitle(String neighborhood, String category) =>
    [neighborhood, category].where((s) => s.trim().isNotEmpty).join(' · ');

List<({String id, String name})> distinctAuthors(FeedItem item) {
  final seen = <String>{};
  return [
    for (final a in item.activities)
      if (seen.add(a.authorId)) (id: a.authorId, name: a.authorName),
  ];
}

/// Ações independentes e fontes completas, sem nota geral.
class FeedCard extends StatelessWidget {
  const FeedCard({
    super.key,
    required this.item,
    required this.now,
    this.onTap,
    this.isFollowing,
    this.onOpenPerson,
    this.confirmedTags = const {},
  });
  final FeedItem item;
  final Map<String, int> confirmedTags;
  final DateTime now;
  final VoidCallback? onTap;
  final bool Function(String uid)? isFollowing;
  final void Function(TrustSource source)? onOpenPerson;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final place = item.place;
    final authors = distinctAuthors(item);
    final names = authors.take(2).map((a) => a.name).join(' e ');
    final extra = authors.length - 2;
    final commented = item.latestComment;
    final price = item.priceAt(now);
    final subtitle = placeSubtitle(place.neighborhood, place.category);
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            color: scheme.surfaceContainerLow,
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                AuthorAvatarStack(
                  authors: authors,
                  ringColor: scheme.surfaceContainerLow,
                ),
                Text(
                  '$names${extra > 0 ? ' e mais $extra' : ''} foram aqui',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Semantics(
            button: true,
            label: 'Abrir ${item.placeName}',
            child: InkWell(
              onTap: onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      SizedBox(
                        height:
                            MediaQuery.sizeOf(context).width.clamp(0, 320) *
                            0.75,
                        width: double.infinity,
                        child: Hero(
                          tag: 'place-photo-${place.id}',
                          child: PlacePhoto(
                            place: place,
                            friendPhoto: item.latestPhoto,
                            creditPadding: const EdgeInsets.fromLTRB(
                              8,
                              0,
                              8,
                              8,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        left: 12,
                        right: 12,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Text(
                              place.category,
                              style: theme.textTheme.labelMedium,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Faixa escura mantém o nome legível com texto ampliado e o crédito visível.
                  Container(
                    width: double.infinity,
                    color: scheme.primary,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.placeName,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: scheme.onPrimary,
                          ),
                        ),
                        if (subtitle.isNotEmpty)
                          Text(
                            subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onPrimary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FoodTagChips(tags: confirmedTags),
                if (price != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: PriceChip(
                      key: const Key('feed-price'),
                      summary: price,
                    ),
                  ),
                TrustSources(
                  item: item,
                  now: now,
                  isFollowing: isFollowing,
                  onOpenPerson: onOpenPerson,
                  onShowAll: onTap,
                ),
                if (commented != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
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
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (place.inCatalog)
                      SaveButton(placeId: place.id, showLabel: true),
                    OutlinedButton.icon(
                      key: ValueKey('feed-rate-${place.id}'),
                      onPressed: () => context.push(
                        Routes.reviewFor(place.id),
                        extra: place,
                      ),
                      icon: const Icon(Icons.star_outline),
                      label: const Text('Avaliar'),
                    ),
                    TextButton(
                      onPressed: onTap,
                      child: const Text('Ver ficha'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
