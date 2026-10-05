import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/relative_time.dart';
import '../../routing/routes.dart';
import '../core/save_button.dart';
import '../feed/widgets/feed_card.dart' show placeSubtitle;
import '../feed/widgets/place_photo.dart';
import 'saved_view_model.dart';

/// "salvo há 2 h", "salvo ontem", "salvo em 20/09".
String savedAgo(DateTime savedAt, DateTime now) {
  final rel = relativeTime(savedAt, now);
  final isDate =
      rel.isNotEmpty && rel.codeUnitAt(0) >= 0x30 && rel.codeUnitAt(0) <= 0x39;
  return isDate ? 'salvo em $rel' : 'salvo $rel';
}

/// Aba "Quero ir" (F11).
class SavedView extends StatelessWidget {
  const SavedView({super.key, required this.viewModel});

  final SavedViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quero ir',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            Text('Só você vê esta lista', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: viewModel,
        builder: (context, _) {
          if (viewModel.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          // Puxar para atualizar em todos os estados (lista, vazio, erro).
          return RefreshIndicator(
            onRefresh: viewModel.refresh,
            child: _body(context),
          );
        },
      ),
    );
  }

  Widget _body(BuildContext context) {
    final vm = viewModel;
    final items = vm.items;
    if (vm.errorMessage != null && items.isEmpty) {
      return _Message(
        icon: Icons.wifi_off,
        text: vm.errorMessage!,
        actionLabel: 'Tentar de novo',
        onAction: vm.refresh,
      );
    }
    if (vm.isEmpty) {
      return _Message(
        icon: Icons.bookmark_add_outlined,
        text: 'Toque no marcador de um lugar para guardar aqui',
        actionLabel: 'Ver onde os amigos foram',
        onAction: () => context.go(Routes.feed),
      );
    }
    final now = vm.now();
    final banner = vm.errorMessage != null;
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: items.length + (banner ? 1 : 0),
      itemBuilder: (context, i) {
        if (banner && i == 0) {
          return MaterialBanner(
            content: Text(vm.errorMessage!),
            actions: [
              TextButton(
                onPressed: vm.refresh,
                child: const Text('Tentar de novo'),
              ),
            ],
          );
        }
        final item = items[i - (banner ? 1 : 0)];
        return SavedCard(
          key: ValueKey('saved-${item.place.id}'),
          item: item,
          now: now,
          onTap: () => context.push(
            Routes.placeDetail(item.place.id),
            extra: item.place,
          ),
        );
      },
    );
  }
}

/// Card compacto de um salvo: foto (ou fallback), nome, bairro · categoria e
/// há quanto tempo foi salvo.
class SavedCard extends StatelessWidget {
  const SavedCard({
    super.key,
    required this.item,
    required this.now,
    this.onTap,
  });

  final SavedItem item;
  final DateTime now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final place = item.place;
    final subtitle = placeSubtitle(place.neighborhood, place.category);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: 'Abrir ${place.name}',
              child: InkWell(
                onTap: onTap,
                child: Row(
                  children: [
                    SizedBox(
                      width: 96,
                      height: 96,
                      child: Hero(
                        tag: 'place-photo-${place.id}',
                        child: PlacePhoto(place: place, iconSize: 32),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              place.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium,
                            ),
                            if (subtitle.isNotEmpty)
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: scheme.tertiary,
                                ),
                              ),
                            const SizedBox(height: 4),
                            Text(
                              savedAgo(item.savedAt, now),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: SaveButton(placeId: place.id),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: (constraints.maxHeight - 64).clamp(0, double.infinity),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 44,
                backgroundColor: scheme.primaryContainer,
                child: Icon(icon, size: 44, color: scheme.primary),
              ),
              const SizedBox(height: 16),
              Text(
                text,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ),
        ),
      ),
    );
  }
}
