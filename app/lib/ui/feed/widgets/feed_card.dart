import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../domain/feed.dart';
import '../../../domain/models/scores.dart';
import '../../../domain/price_summary.dart';
import '../../../routing/routes.dart';
import '../../core/save_button.dart';
import 'author_avatar.dart';
import 'place_photo.dart';
import 'trust_sources.dart' show sourceSemanticsLabel;

String placeSubtitle(String neighborhood, String category) =>
    [neighborhood, category].where((s) => s.trim().isNotEmpty).join(' · ');

List<({String id, String name})> distinctAuthors(FeedItem item) {
  final seen = <String>{};
  return [
    for (final a in item.activities)
      if (seen.add(a.authorId)) (id: a.authorId, name: a.authorName),
  ];
}

/// Cada amigo contribui uma vez, com a avaliação mais recente e os eixos que preencheu.
double? friendsOverallScore(FeedItem item) {
  final perPerson = <double>[];
  for (final source in item.sources) {
    final scores = source.latestReview?.scores;
    if (scores == null) continue;
    final values = [
      scores.food,
      scores.ambience,
      scores.service,
    ].whereType<int>().toList();
    if (values.isNotEmpty) {
      perPerson.add(values.reduce((a, b) => a + b) / values.length);
    }
  }
  if (perPerson.isEmpty) return null;
  return perPerson.reduce((a, b) => a + b) / perPerson.length;
}

/// Local, nota dos amigos e comentário recente com autoria.
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

  void _openAuthor(BuildContext context, String id) {
    final source = item.sources.firstWhere((s) => s.authorId == id);
    if (onOpenPerson != null) {
      onOpenPerson!(source);
    } else {
      context.push(Routes.person(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final place = item.place;
    final authors = distinctAuthors(item);
    final extra = authors.length - 2;
    final price = item.priceAt(now);
    final overall = friendsOverallScore(item);
    final comment = item.latestComment;
    final location = [place.address, place.neighborhood, place.city]
        .whereType<String>()
        .where((part) => part.trim().isNotEmpty)
        .take(2)
        .join(' · ');
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
                for (var i = 0; i < authors.take(2).length; i++) ...[
                  if (i > 0) Text('e', style: theme.textTheme.bodySmall),
                  Semantics(
                    key: ValueKey('trust-source-${authors[i].id}'),
                    container: true,
                    button: true,
                    excludeSemantics: true,
                    label: sourceSemanticsLabel(
                      item.sources.firstWhere(
                        (s) => s.authorId == authors[i].id,
                      ),
                      following: isFollowing?.call(authors[i].id) ?? false,
                      now: now,
                    ),
                    onTap: () => _openAuthor(context, authors[i].id),
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 48),
                        foregroundColor: scheme.onSurface,
                        textStyle: theme.textTheme.bodySmall,
                      ),
                      onPressed: () => _openAuthor(context, authors[i].id),
                      child: Text(authors[i].name),
                    ),
                  ),
                ],
                Text(
                  '${extra > 0 ? 'e mais $extra ' : ''}${authors.length == 1 ? 'visitou' : 'visitaram'}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Semantics(
            container: true,
            button: true,
            label: 'Abrir ${item.placeName}',
            onTap: onTap,
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
                              92,
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
                              place.category.isEmpty ? 'Local' : place.category,
                              style: theme.textTheme.labelMedium,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(16, 32, 16, 14),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Color(0xE6000000)],
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.placeName,
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(color: Colors.white),
                                    ),
                                  ),
                                  if (overall != null)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 8),
                                      child: Tooltip(
                                        message: 'Nota dos amigos',
                                        child: Semantics(
                                          label:
                                              'Nota dos amigos ${formatAverage(overall)} de 5',
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 9,
                                              vertical: 5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: scheme.secondary,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.star,
                                                  color: Colors.white,
                                                  size: 17,
                                                ),
                                                const SizedBox(width: 3),
                                                Text(
                                                  formatAverage(overall),
                                                  style: theme
                                                      .textTheme
                                                      .labelLarge
                                                      ?.copyWith(
                                                        color: Colors.white,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              if (location.isNotEmpty)
                                Text(
                                  location,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.white,
                                  ),
                                ),
                              if (price != null)
                                Semantics(
                                  key: const Key('feed-price'),
                                  button: true,
                                  onTap: onTap,
                                  label:
                                      'Abrir ${place.name}, ${priceChipSemantics(price)}',
                                  excludeSemantics: true,
                                  child: Text(
                                    priceChipLabel(price),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (comment != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '“${comment.comment!.trim()}”',
                      key: ValueKey('feed-comment-${place.id}'),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '— ${comment.authorName}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              spacing: 8,
              children: [
                if (place.inCatalog)
                  Expanded(
                    child: SaveButton(placeId: place.id, showLabel: true),
                  ),
                Expanded(
                  child: OutlinedButton.icon(
                    key: ValueKey('feed-rate-${place.id}'),
                    onPressed: () =>
                        context.push(Routes.reviewFor(place.id), extra: place),
                    icon: const Icon(Icons.star_outline),
                    label: const Text('Avaliar'),
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Ver ficha de ${place.name}',
                  onPressed: onTap,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
