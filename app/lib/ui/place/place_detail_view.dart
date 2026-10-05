import 'package:flutter/material.dart';

import '../../domain/feed.dart';
import '../../domain/models/place.dart';
import '../core/osm_credit.dart';
import '../feed/widgets/author_avatar.dart';
import '../feed/widgets/axis_scores.dart';
import '../feed/widgets/feed_card.dart';
import '../feed/widgets/place_photo.dart';
import '../feed/widgets/review_tile.dart';

/// Detalhe do local: foto grande e todas as avaliações dos amigos ali.
/// Os dados chegam prontos do feed (`FeedItem`); não há leitura extra.
class PlaceDetailView extends StatelessWidget {
  const PlaceDetailView({
    super.key,
    required this.item,
    this.now = DateTime.now,
  });

  final FeedItem item;
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final place = item.place;
    final at = now();
    final subtitle = [
      placeSubtitle(place.neighborhood, place.category),
      if (place.city.trim().isNotEmpty) place.city,
    ].where((s) => s.isNotEmpty).join(' · ');

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 280,
            foregroundColor: Colors.white,
            backgroundColor: scheme.primary,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                item.placeName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: 'place-photo-${place.id}',
                    child: PlacePhoto(place: place, iconSize: 72),
                  ),
                  // Escurece a base para o título branco ficar legível.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x55000000),
                          Color(0x00000000),
                          Color(0x99000000),
                        ],
                        stops: [0, 0.45, 1],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PhotoCredit(place: place),
                  if (subtitle.isNotEmpty)
                    Row(
                      children: [
                        Icon(
                          Icons.place_outlined,
                          size: 18,
                          color: scheme.tertiary,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            subtitle,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: scheme.tertiary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  PlaceFacts(place: place),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      AuthorAvatarStack(
                        authors: distinctAuthors(item),
                        ringColor: scheme.surface,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.headline,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Média dos amigos', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 6),
                  AxisScores.averages(item.averages),
                  const SizedBox(height: 20),
                  Text(
                    item.reviews.length == 1
                        ? '1 avaliação de amigo'
                        : '${item.reviews.length} avaliações de amigos',
                    style: theme.textTheme.titleMedium,
                  ),
                  const Divider(height: 20),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            sliver: SliverList.separated(
              itemCount: item.reviews.length,
              itemBuilder: (context, i) =>
                  ReviewTile(review: item.reviews[i], now: at),
              separatorBuilder: (context, i) => const Divider(height: 1),
            ),
          ),
          if (place.hasOsmData)
            const SliverToBoxAdapter(
              child: OsmCredit(padding: EdgeInsets.fromLTRB(20, 0, 20, 24)),
            ),
        ],
      ),
    );
  }
}

/// `Foto: autor · licença` (+ selo "ilustrativa"): atribuição exigida
/// pelas licenças CC BY / CC BY-SA das fotos do seed.
class PhotoCredit extends StatelessWidget {
  const PhotoCredit({super.key, required this.place});

  final Place place;

  static String? creditText(Place place) {
    if (place.photoUrl == null) return null;
    final parts = [
      place.photoAuthor,
      place.photoLicense,
    ].whereType<String>().toList();
    if (parts.isEmpty) return null;
    return 'Foto: ${parts.join(' · ')}';
  }

  @override
  Widget build(BuildContext context) {
    final text = creditText(place);
    if (text == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(text, key: const Key('photo-credit'), style: muted),
          if (place.photoIllustrative)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('ilustrativa', style: muted),
            ),
        ],
      ),
    );
  }
}

/// Endereço e cozinha do local (dados do OSM), quando existem.
class PlaceFacts extends StatelessWidget {
  const PlaceFacts({super.key, required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    Widget fact(IconData icon, String text, Key key) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Flexible(child: Text(text, key: key, style: muted)),
        ],
      ),
    );
    final address = place.address;
    final cuisine = place.cuisine;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (address != null)
          fact(Icons.signpost_outlined, address, const Key('place-address')),
        if (cuisine != null)
          fact(Icons.restaurant_menu, cuisine, const Key('place-cuisine')),
      ],
    );
  }
}
