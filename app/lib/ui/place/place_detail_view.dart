import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/place.dart';
import '../../domain/models/review.dart';
import '../../routing/routes.dart';
import '../core/osm_credit.dart';
import '../core/save_button.dart';
import '../feed/widgets/author_avatar.dart';
import '../feed/widgets/axis_scores.dart';
import '../feed/widgets/feed_card.dart';
import '../feed/widgets/place_photo.dart';
import '../feed/widgets/review_tile.dart';
import 'place_detail_view_model.dart';
import 'review_photo_strip.dart';

/// Detalhe do local: foto grande, marcador "Quero ir" e as avaliações dos
/// amigos ali. Abre por `placeId` sozinho (ex.: a partir dos salvos); com
/// dados prontos da navegação, aparece já e só atualiza.
class PlaceDetailView extends StatefulWidget {
  const PlaceDetailView({super.key, required this.viewModel});

  final PlaceDetailViewModel viewModel;

  @override
  State<PlaceDetailView> createState() => _PlaceDetailViewState();
}

class _PlaceDetailViewState extends State<PlaceDetailView> {
  @override
  void initState() {
    super.initState();
    widget.viewModel.load();
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.feed);
    }
  }

  Future<void> _review(Place place) async {
    final sent = await context.push<bool>(
      Routes.reviewFor(place.id),
      extra: place,
    );
    if (!mounted) return;
    if (sent == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Avaliação enviada! Quem segue você já pode ver.'),
        ),
      );
      // A avaliação nova aparece no detalhe (como "Você").
      widget.viewModel.load();
    }
  }

  /// Perfil de quem avaliou ("Você" abre o próprio). Seguir/deixar de seguir
  /// lá muda quem aparece aqui: recarrega ao voltar, se mudou.
  Future<void> _openPerson(Review r) async {
    await context.push(Routes.person(r.authorId));
    if (!mounted) return;
    widget.viewModel.reloadIfStale();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        final place = vm.place;
        if (place != null) return _detail(context, vm, place);
        if (vm.notFound) {
          return _Bare(
            child: _CenteredMessage(
              key: const Key('place-not-found'),
              icon: Icons.wrong_location_outlined,
              text: 'Local não encontrado',
              actionLabel: 'Voltar',
              onAction: _back,
            ),
          );
        }
        if (vm.errorMessage != null) {
          return _Bare(
            child: _CenteredMessage(
              icon: Icons.wifi_off,
              text: vm.errorMessage!,
              actionLabel: 'Tentar de novo',
              onAction: vm.load,
              secondaryLabel: 'Voltar',
              onSecondary: _back,
            ),
          );
        }
        return const _Bare(child: Center(child: CircularProgressIndicator()));
      },
    );
  }

  Widget _detail(BuildContext context, PlaceDetailViewModel vm, Place place) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final at = vm.now();
    final item = vm.item;
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
            actions: [
              if (place.inCatalog)
                SaveButton(placeId: place.id, style: SaveButtonStyle.onAppBar),
              const SizedBox(width: 4),
            ],
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                place.name,
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
                    // Crédito acima do título expandido da barra.
                    child: PlacePhoto(
                      place: place,
                      iconSize: 72,
                      friendPhoto: item?.latestPhoto,
                      friendPhotoIsOwn:
                          item?.latestPhoto != null &&
                          vm.isOwn(item!.latestPhoto!),
                      creditPadding: const EdgeInsets.fromLTRB(16, 0, 16, 64),
                    ),
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
                  if (item != null) ...[
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
                    const SizedBox(height: 16),
                    FilledButton.tonalIcon(
                      key: const Key('place-review'),
                      onPressed: () => _review(place),
                      icon: const Icon(Icons.rate_review),
                      label: Text(
                        vm.hasOwnReview ? 'Avaliar de novo' : 'Avaliar',
                      ),
                    ),
                    if (item.photoReviews.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      ReviewPhotoStrip(
                        place: place,
                        reviews: item.photoReviews,
                        now: at,
                        currentUserId: vm.currentUserId,
                      ),
                    ],
                    const SizedBox(height: 20),
                    Text(
                      vm.reviewCountLabel,
                      style: theme.textTheme.titleMedium,
                    ),
                    const Divider(height: 20),
                  ] else if (vm.reviewsKnown)
                    _NoFriendReviews(onReview: () => _review(place))
                  else if (vm.errorMessage != null)
                    _CenteredMessage(
                      icon: Icons.wifi_off,
                      text: vm.errorMessage!,
                      actionLabel: 'Tentar de novo',
                      onAction: vm.load,
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
            ),
          ),
          if (item != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              sliver: SliverList.separated(
                itemCount: item.reviews.length,
                itemBuilder: (context, i) => ReviewTile(
                  review: item.reviews[i],
                  now: at,
                  onAuthorTap: () => _openPerson(item.reviews[i]),
                ),
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

/// Nenhum amigo avaliou o local ainda: convite para ser o primeiro.
class _NoFriendReviews extends StatelessWidget {
  const _NoFriendReviews({required this.onReview});

  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nenhum amigo avaliou ainda',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('place-review'),
            onPressed: onReview,
            icon: const Icon(Icons.rate_review),
            label: const Text('Avaliar'),
          ),
        ],
      ),
    );
  }
}

/// Tela sem os dados do local (carregando, erro, não encontrado).
class _Bare extends StatelessWidget {
  const _Bare({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(), body: child);
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    super.key,
    required this.icon,
    required this.text,
    required this.actionLabel,
    required this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String text;
  final String actionLabel;
  final VoidCallback onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: scheme.primary),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (secondaryLabel != null)
                  OutlinedButton(
                    onPressed: onSecondary,
                    child: Text(secondaryLabel!),
                  ),
                FilledButton(onPressed: onAction, child: Text(actionLabel)),
              ],
            ),
          ],
        ),
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
          Flexible(
            child: Text(text, key: key, style: muted),
          ),
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
