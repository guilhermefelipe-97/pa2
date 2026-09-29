import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/feed.dart';
import '../../routing/routes.dart';
import 'feed_view_model.dart';
import 'widgets/feed_card.dart';

class FeedView extends StatefulWidget {
  const FeedView({super.key, required this.viewModel});

  final FeedViewModel viewModel;

  @override
  State<FeedView> createState() => _FeedViewState();
}

class _FeedViewState extends State<FeedView> {
  @override
  void initState() {
    super.initState();
    widget.viewModel.load();
  }

  Future<void> _openPeople() async {
    await context.push(Routes.people);
    if (mounted) widget.viewModel.load();
  }

  Future<void> _signOut() async {
    try {
      await widget.viewModel.signOut();
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível sair. Tente de novo.')),
      );
    }
  }

  Future<void> _openReview() async {
    final saved = await context.push<bool>(Routes.pickPlace);
    if (!mounted) return;
    if (saved == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Avaliação enviada! Quem segue você já pode ver.'),
        ),
      );
    }
    widget.viewModel.load();
  }

  void _openPlace(FeedItem item) {
    context.push(Routes.placeDetail(item.placeId), extra: item);
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'NaÁrea',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            Text('Amigos foram aqui', style: theme.textTheme.bodySmall),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Pessoas',
            icon: const Icon(Icons.person_search),
            onPressed: _openPeople,
          ),
          IconButton(
            tooltip: 'Sair',
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('feed-review'),
        onPressed: _openReview,
        icon: const Icon(Icons.rate_review),
        label: const Text('Avaliar'),
      ),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) {
          if (vm.isLoading && !vm.loadedOnce) {
            return const Center(child: CircularProgressIndicator());
          }
          if (vm.errorMessage != null && vm.items.isEmpty) {
            return _PullToRefresh(
              onRefresh: vm.load,
              child: _Message(
                icon: Icons.wifi_off,
                text: vm.errorMessage!,
                actionLabel: 'Tentar de novo',
                onAction: vm.load,
              ),
            );
          }
          if (vm.followsNobody) {
            return _PullToRefresh(
              onRefresh: vm.load,
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
              onRefresh: vm.load,
              child: const _Message(
                icon: Icons.restaurant,
                text: 'Quem você segue ainda não avaliou nenhum lugar.',
              ),
            );
          }
          final now = vm.now();
          final offset = vm.errorMessage != null ? 1 : 0;
          return RefreshIndicator(
            onRefresh: vm.load,
            child: ListView.builder(
              // Pull-to-refresh funciona mesmo com poucos cards.
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: vm.items.length + offset,
              itemBuilder: (context, i) {
                if (offset == 1 && i == 0) {
                  return MaterialBanner(
                    content: Text(vm.errorMessage!),
                    actions: [
                      TextButton(
                        onPressed: vm.load,
                        child: const Text('Tentar de novo'),
                      ),
                    ],
                  );
                }
                final item = vm.items[i - offset];
                return FeedCard(
                  item: item,
                  now: now,
                  onTap: () => _openPlace(item),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Estado vazio/erro que também aceita puxar para atualizar.
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
