import '../core/place_location_chip.dart';
import 'package:provider/provider.dart';
import '../dietary/dietary_store.dart';
import '../dietary/dietary_filter_panel.dart';
import '../dietary/food_filter_options.dart';
import '../core/editorial.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/feed.dart';
import '../../routing/routes.dart';
import '../core/app_shell.dart';
import 'feed_view_model.dart';
import 'widgets/feed_card.dart';

class FeedView extends StatefulWidget {
  const FeedView({super.key, required this.viewModel});

  final FeedViewModel viewModel;

  @override
  State<FeedView> createState() => _FeedViewState();
}

class _FeedViewState extends State<FeedView> {
  bool? _active;
  bool popularFirst = false;

  @override
  void initState() {
    super.initState();
    widget.viewModel.load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final active = ActiveTab.maybeOf(context);
    if (active == true && _active == false) widget.viewModel.reloadIfStale();
    _active = active;
  }

  void _openPeople() => context.go(Routes.people);

  Future<void> _openReview() async {
    final saved = await context.push<bool>(Routes.pickPlace);
    if (!mounted) return;
    if (saved == true) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Avaliação registrada.')));
    }
    widget.viewModel.load();
  }

  void _openPlace(FeedItem item) {
    context.push(Routes.placeDetail(item.placeId), extra: item);
  }

  void _openPerson(TrustSource source) {
    context.push(Routes.person(source.authorId));
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final theme = Theme.of(context);
    final dietary = context.watch<DietaryStore?>();
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64 * MediaQuery.textScalerOf(context).scale(1),
        titleSpacing: 20,
        title: Row(
          children: [
            Text(
              'NaÁrea',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            const Flexible(child: PlaceLocationChip()),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              key: const Key('feed-filters'),
              tooltip: 'Filtrar feed',
              onPressed: dietary == null
                  ? null
                  : () => showFeedFilters(context),
              icon: Badge.count(
                backgroundColor: theme.colorScheme.secondary,
                textColor: Colors.white,
                count: dietary?.tags.length ?? 0,
                isLabelVisible:
                    dietary?.ready == true && dietary!.tags.isNotEmpty,
                child: Icon(
                  Icons.tune_rounded,
                  color: dietary?.tags.isNotEmpty == true
                      ? theme.colorScheme.secondary
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ],
        bottom: dietary?.ready == true && dietary!.tags.isNotEmpty
            ? PreferredSize(
                preferredSize: Size.fromHeight(
                  44 * MediaQuery.textScalerOf(context).scale(1),
                ),
                child: SizedBox(
                  height: 44 * MediaQuery.textScalerOf(context).scale(1),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        for (final option in foodFilterOptions)
                          if (dietary.tags.contains(option.tag))
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ActionChip(
                                avatar: Icon(option.icon, size: 16),
                                label: Text(option.label),
                                onPressed: () => showFeedFilters(context),
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
              )
            : null,
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('feed-review'),
        onPressed: _openReview,
        icon: const Icon(Icons.rate_review_outlined),
        label: const Text('Avaliar'),
      ),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) {
          if (vm.isLoading && (!vm.loadedOnce || vm.items.isEmpty)) {
            return const EditorialLoading();
          }
          if (vm.errorMessage != null && vm.items.isEmpty) {
            return _PullToRefresh(
              onRefresh: vm.retry,
              child: _Message(
                icon: Icons.wifi_off,
                text: vm.errorMessage!,
                actionLabel: 'Tentar de novo',
                onAction: vm.retry,
              ),
            );
          }
          if (vm.followsNobody) {
            return _PullToRefresh(
              onRefresh: vm.retry,
              child: _Message(
                icon: Icons.group_add,
                text: 'Siga pessoas para ver onde elas foram.',
                actionLabel: 'Encontrar pessoas',
                onAction: _openPeople,
              ),
            );
          }
          if (vm.items.isEmpty) {
            return _PullToRefresh(
              onRefresh: vm.retry,
              child: _Message(
                icon: Icons.restaurant,
                actionLabel: vm.hasFoodFilter
                    ? 'Editar ou limpar filtro'
                    : null,
                onAction: vm.hasFoodFilter
                    ? () => showFeedFilters(context)
                    : null,
                text: vm.hasFoodFilter
                    ? 'Nenhum local dos amigos tem todas as tags confirmadas do seu filtro alimentar.'
                    : 'Quem você segue ainda não avaliou nenhum lugar.',
              ),
            );
          }
          final now = vm.now();
          final items = [...vm.items];
          if (popularFirst) {
            items.sort((a, b) {
              final byPeople = b.sources.length.compareTo(a.sources.length);
              return byPeople != 0
                  ? byPeople
                  : b.latestAt.compareTo(a.latestAt);
            });
          }
          final offset = vm.errorMessage != null ? 1 : 0;
          return RefreshIndicator(
            onRefresh: vm.retry,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: items.length + offset + 2,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const EditorialHeading(title: 'Feed de Amigos'),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ChoiceChip(
                              label: const Text('Mais recentes'),
                              avatar: const Icon(Icons.auto_awesome, size: 18),
                              selected: !popularFirst,
                              onSelected: (_) =>
                                  setState(() => popularFirst = false),
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: const Text('Em alta no grupo'),
                              avatar: const Icon(
                                Icons.local_fire_department_outlined,
                                size: 18,
                              ),
                              selected: popularFirst,
                              onSelected: (_) =>
                                  setState(() => popularFirst = true),
                            ),
                            const SizedBox(width: 8),
                            ActionChip(
                              label: const Text('Perto de mim'),
                              avatar: const Icon(Icons.map_outlined, size: 18),
                              onPressed: () => context.go(Routes.nearby),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  );
                }
                final i = index - 1;
                if (i == items.length + offset) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          const Icon(Icons.local_cafe_outlined, size: 32),
                          const SizedBox(height: 12),
                          Text(
                            'Você está em dia com os amigos!',
                            style: theme.textTheme.titleLarge,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Compartilhe sua experiência recente.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (offset == 1 && i == 0) {
                  return MaterialBanner(
                    content: Text(vm.errorMessage!),
                    actions: [
                      IconButton(
                        tooltip: 'Perfil alimentar',
                        icon: const Icon(Icons.tune),
                        onPressed: () async {
                          await context.push('/perfil-alimentar');
                          if (mounted) widget.viewModel.load();
                        },
                      ),
                      TextButton(
                        onPressed: vm.retry,
                        child: const Text('Tentar de novo'),
                      ),
                    ],
                  );
                }
                final item = items[i - offset];
                return FeedCard(
                  item: item,
                  confirmedTags: vm.confirmedTags[item.placeId] ?? const {},
                  now: now,
                  onTap: () => _openPlace(item),
                  isFollowing: vm.isFollowing,
                  onOpenPerson: _openPerson,
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _PullToRefresh extends StatelessWidget {
  const _PullToRefresh({required this.onRefresh, required this.child});

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(child: child),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: scheme.primaryContainer,
            child: Icon(icon, size: 40, color: scheme.primary),
          ),
          const SizedBox(height: 16),
          Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
