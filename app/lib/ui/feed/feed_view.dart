import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/feed.dart';
import '../../domain/models/review.dart';
import '../../routing/routes.dart';
import 'feed_view_model.dart';

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
        const SnackBar(content: Text('Avaliação enviada! Quem segue você já pode ver.')),
      );
    }
    widget.viewModel.load();
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Amigos foram aqui'),
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
            return _Message(
              icon: Icons.wifi_off,
              text: vm.errorMessage!,
              actionLabel: 'Tentar de novo',
              onAction: vm.load,
            );
          }
          if (vm.followsNobody) {
            return _Message(
              icon: Icons.group_add,
              text: 'Siga pessoas para ver onde elas foram.',
              actionLabel: 'Encontrar pessoas',
              onAction: _openPeople,
            );
          }
          if (vm.items.isEmpty) {
            return RefreshIndicator(
              onRefresh: vm.load,
              child: ListView(
                children: const [
                  SizedBox(height: 120),
                  _Message(
                    icon: Icons.restaurant,
                    text: 'Quem você segue ainda não avaliou nenhum lugar.',
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: vm.load,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              itemCount: vm.items.length + (vm.errorMessage != null ? 1 : 0),
              itemBuilder: (context, i) {
                if (vm.errorMessage != null && i == 0) {
                  return MaterialBanner(
                    content: Text(vm.errorMessage!),
                    actions: [
                      TextButton(onPressed: vm.load, child: const Text('Tentar de novo')),
                    ],
                  );
                }
                final offset = vm.errorMessage != null ? 1 : 0;
                return _FeedCard(item: vm.items[i - offset]);
              },
            ),
          );
        },
      ),
    );
  }
}

class _FeedCard extends StatelessWidget {
  const _FeedCard({required this.item});

  final FeedItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.placeName,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(item.headline,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
            const Divider(height: 24),
            for (final r in item.reviews) _ReviewTile(review: r),
          ],
        ),
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});

  final Review review;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = [
      review.dayPeriod.label,
      if (review.companion != null) review.companion!.label,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(review.authorName, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _ScoreChip(label: 'Comida', value: review.scores.food),
              _ScoreChip(label: 'Ambiente', value: review.scores.ambience),
              _ScoreChip(label: 'Atendimento', value: review.scores.service),
            ],
          ),
          const SizedBox(height: 4),
          Text(details, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ScoreChip extends StatelessWidget {
  const _ScoreChip({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text('$label $value/5',
          style: TextStyle(color: scheme.onSecondaryContainer, fontSize: 13)),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center),
            if (actionLabel != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
