import '../queue/queue_section.dart';
import '../owner/reply_line.dart';
import 'package:flutter/material.dart';
import '../share/place_share_sheet.dart';
import '../share/share_service.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/place.dart';
import '../../domain/feed.dart' show FeedItem;
import '../../domain/models/place_activity.dart';
import '../../domain/models/scores.dart' show formatAverage;
import '../../routing/routes.dart';
import '../core/osm_credit.dart';
import '../core/save_button.dart';
import '../feed/widgets/author_avatar.dart';
import '../feed/widgets/axis_scores.dart';
import '../feed/widgets/feed_card.dart';
import '../feed/widgets/price_chip.dart';
import '../feed/widgets/review_tile.dart';
import '../feed/widgets/trust_sources.dart' show RecurrenceBadge;
import '../feed/widgets/visit_tile.dart';
import '../open/open_now_section.dart';
import '../visit/visit_sheet.dart';
import '../visit/visit_view_model.dart';
import 'place_detail_view_model.dart';
import '../dietary/food_tag_chips.dart';
import '../owner/owner_view.dart';
import '../owner/place_presentation_view.dart';
import 'price_section.dart';
import 'review_photo_strip.dart';
import 'place_gallery.dart';

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Avaliação registrada.')));
    }

    if (sent == false) widget.viewModel.markVisited();
    if (sent != null) widget.viewModel.load();
  }

  Future<void> _visit(Place place) async {
    final registered = await showVisitSheet(context, place: place);
    if (!mounted || !registered) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(VisitViewModel.successMessage)),
    );

    widget.viewModel
      ..markVisited()
      ..load();
  }

  Future<void> _openPerson(PlaceActivity r) async {
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

  Widget _primaryActions(
    BuildContext context,
    PlaceDetailViewModel vm,
    Place place,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          key: const Key('place-primary-actions'),
          children: [
            Expanded(
              child: FilledButton.icon(
                key: const Key('place-review'),
                onPressed: vm.reviewAgainLabel == null
                    ? () => _review(place)
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.secondary,
                  foregroundColor: scheme.onSecondary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  minimumSize: const Size(0, 44),
                  textStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.rate_review_outlined, size: 16),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Avaliar', maxLines: 1, softWrap: false),
                ),
              ),
            ),
            if (place.inCatalog) ...[
              const SizedBox(width: 8),
              Expanded(
                child: SaveButton(
                  placeId: place.id,
                  showLabel: true,
                  compact: true,
                ),
              ),
            ],
          ],
        ),
        if (vm.reviewAgainLabel != null) ...[
          const SizedBox(height: 8),
          _ReviewAgainLater(label: vm.reviewAgainLabel!),
        ],
      ],
    );
  }

  Widget _detail(BuildContext context, PlaceDetailViewModel vm, Place place) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final at = vm.now();
    final item = vm.item;
    final overall = item == null ? null : friendsOverallScore(item);

    final priceSection = PriceSection(
      key: const Key('place-price-section'),
      summary: vm.price,
      countLabel: vm.priceCountLabel,
    );
    final subtitle = [
      placeSubtitle(place.neighborhood, place.category),
      if (place.city.trim().isNotEmpty) place.city,
    ].where((s) => s.isNotEmpty).join(' · ');

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 256,
            foregroundColor: scheme.onSurface,
            backgroundColor: scheme.surface,
            leading: BackButton(onPressed: _back),
            title: const Text('Detalhes do local'),
            actions: [
              if (context.read<ShareService?>() != null)
                IconButton(
                  key: const Key('place-share'),
                  tooltip: 'Compartilhar',
                  icon: const Icon(Icons.share_outlined),
                  onPressed: () => showPlaceShareSheet(
                    context,
                    place: place,
                    averages: item?.averages,
                  ),
                ),
              OwnershipAction(placeId: place.id),
              const SizedBox(width: 4),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Padding(
                padding: const EdgeInsets.only(top: kToolbarHeight),
                child: Hero(
                  tag: 'place-photo-${place.id}',
                  child: PlaceGallery(
                    place: place,
                    reviews: item?.photoReviews ?? const [],
                    currentUserId: vm.currentUserId,
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    place.category.toUpperCase(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          place.name,
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
                      if (overall != null) ...[
                        const SizedBox(width: 8),
                        Semantics(
                          label:
                              'Nota das experiências exibidas ${formatAverage(overall)} de 5',
                          excludeSemantics: true,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.star,
                                  size: 16,
                                  color: scheme.secondary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  formatAverage(overall),
                                  style: theme.textTheme.titleMedium,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  PhotoCredit(place: place),
                  if (subtitle.isNotEmpty)
                    Row(
                      children: [
                        Icon(
                          Icons.place_outlined,
                          size: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  PlaceFacts(place: place),
                  FoodTagChips(tags: vm.confirmedTags),
                  if (vm.tagsFailed)
                    TextButton(
                      onPressed: vm.loadTags,
                      child: const Text(
                        'Não foi possível carregar tags. Tentar novamente',
                      ),
                    ),

                  if (vm.openNow != null)
                    OpenNowSection(viewModel: vm.openNow!, place: place),
                  QueueSection(place: place, compact: true),
                  const SizedBox(height: 16),
                  if (vm.reviewsKnown) _primaryActions(context, vm, place),
                  if (item != null) ...[
                    const SizedBox(height: 16),
                    _FriendsAvatars(
                      item: item,
                      currentUserId: vm.currentUserId,
                      onPerson: (id) => _openPerson(
                        item.activities.firstWhere((a) => a.authorId == id),
                      ),
                    ),

                    if (vm.recurrenceLabel != null) ...[
                      const SizedBox(height: 12),
                      RecurrenceBadge(
                        key: const Key('place-recurrence'),
                        label: vm.recurrenceLabel!,
                      ),
                    ],

                    if (vm.price != null) ...[
                      const SizedBox(height: 12),
                      PriceChip(
                        key: const Key('place-price-chip'),
                        summary: vm.price!,
                        countLabel: vm.priceCountLabel,
                      ),
                    ],
                    const SizedBox(height: 16),
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
                      'Avaliações e visitas',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(vm.reviewCountLabel, style: theme.textTheme.bodySmall),
                    const SizedBox(height: 16),
                  ] else if (vm.reviewsKnown) ...[
                    _NoFriendReviews(
                      showActions: false,
                      onReview: () => _review(place),
                      reviewAgainLabel: vm.reviewAgainLabel,
                      visitAction: _VisitAction(
                        blockedLabel: vm.visitBlockedLabel,
                        onVisit: () => _visit(place),
                      ),
                    ),
                    priceSection,
                  ] else if (vm.errorMessage != null)
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
              sliver: SliverToBoxAdapter(
                child: Column(
                  children: [
                    for (final activity in item.activities) ...[
                      switch (activity) {
                        final Review r => Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ReviewTile(
                                  review: r,
                                  isOwn: vm.isOwn(r),
                                  now: at,
                                  onAuthorTap: () => _openPerson(r),
                                  stitchLayout: true,
                                ),
                                ReplyLine(reviewId: r.id, framed: true),
                              ],
                            ),
                          ),
                        ),
                        final Visit v => VisitTile(
                          visit: v,
                          now: at,
                          isOwn: vm.isOwn(v),
                          onAuthorTap: () => _openPerson(v),
                        ),
                      },
                      const Divider(height: 1),
                    ],
                  ],
                ),
              ),
            ),
          if (vm.reviewsKnown)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverToBoxAdapter(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _VisitAction(
                    blockedLabel: vm.visitBlockedLabel,
                    onVisit: () => _visit(place),
                  ),
                ),
              ),
            ),

          if (item != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Informações úteis',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    if (item.averages != null)
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('Médias das avaliações exibidas'),
                        children: [AxisScores.averages(item.averages!)],
                      ),
                    Card(
                      semanticContainer: false,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: priceSection,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: PlacePresentationSection(
                key: ValueKey(place.id),
                placeId: place.id,
              ),
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

class _FriendsAvatars extends StatelessWidget {
  const _FriendsAvatars({
    required this.item,
    required this.currentUserId,
    required this.onPerson,
  });
  final FeedItem item;
  final String? currentUserId;
  final void Function(String) onPerson;
  @override
  Widget build(BuildContext context) {
    final friends = distinctAuthors(
      item,
    ).where((a) => a.id != currentUserId).toList();
    if (friends.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Container(
      key: const Key('place-friends-avatars'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.people_outline,
                size: 16,
                color: theme.colorScheme.secondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Amigos que já foram',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text('${friends.length}', style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final friend in friends)
                Semantics(
                  button: true,
                  label: 'Abrir perfil de ${friend.name}',
                  excludeSemantics: true,
                  child: Tooltip(
                    message: friend.name,
                    child: InkWell(
                      onTap: () => onPerson(friend.id),
                      customBorder: const CircleBorder(),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: AuthorAvatar(
                          id: friend.id,
                          name: friend.name,
                          radius: 20,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NoFriendReviews extends StatelessWidget {
  const _NoFriendReviews({
    required this.onReview,
    required this.visitAction,
    this.reviewAgainLabel,
    this.showActions = true,
  });

  final VoidCallback onReview;

  final Widget visitAction;
  final bool showActions;

  final String? reviewAgainLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            reviewAgainLabel != null
                ? 'Você já avaliou este lugar'
                : 'Nenhum amigo avaliou ainda',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          if (showActions)
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (reviewAgainLabel != null)
                  _ReviewAgainLater(label: reviewAgainLabel!)
                else
                  FilledButton.icon(
                    key: const Key('place-review'),
                    onPressed: onReview,
                    icon: const Icon(Icons.rate_review),
                    label: const Text('Avaliar'),
                  ),
                visitAction,
              ],
            ),
        ],
      ),
    );
  }
}

class _ReviewAgainLater extends StatelessWidget {
  const _ReviewAgainLater({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Row(
      key: const Key('place-review-locked'),
      children: [
        Icon(Icons.event_repeat, size: 20, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class _VisitAction extends StatelessWidget {
  const _VisitAction({required this.onVisit, this.blockedLabel});

  final VoidCallback onVisit;

  final String? blockedLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final button = OutlinedButton.icon(
      key: const Key('place-visit'),
      onPressed: blockedLabel == null ? onVisit : null,
      icon: const Icon(Icons.replay),
      label: const Text(visitActionLabel),
    );
    if (blockedLabel == null) return button;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        button,
        const SizedBox(height: 4),
        Text(
          blockedLabel!,
          key: const Key('place-visit-locked'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

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
