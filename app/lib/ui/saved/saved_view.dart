import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../domain/models/place_list.dart';
import '../../domain/relative_time.dart';
import '../../routing/routes.dart';
import '../core/messages.dart';
import '../core/save_button.dart';
import '../feed/widgets/feed_card.dart' show placeSubtitle;
import '../feed/widgets/place_photo.dart';
import '../lists/add_to_list_sheet.dart';
import '../lists/list_dialogs.dart';
import '../lists/lists_store.dart';
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
          final refreshable = RefreshIndicator(
            onRefresh: viewModel.refresh,
            child: _body(context),
          );
          final chips = viewModel.lists.isNotEmpty;
          final listsFailed = viewModel.listsFailed;
          if (!chips && !listsFailed) return refreshable;
          return Column(
            children: [
              if (listsFailed) _ListsErrorBanner(onRetry: viewModel.retryLists),
              if (chips) ListChips(viewModel: viewModel),
              Expanded(child: refreshable),
            ],
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
    if (vm.isListLoading && items.isEmpty) {
      // Locais da lista ainda sem dados do catálogo.
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    }
    if (vm.isListEmpty) {
      return _Message(
        icon: Icons.playlist_add,
        text: 'Nada nesta lista ainda',
        actionLabel: 'Ver todos os salvos',
        onAction: () => vm.selectList(null),
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
          SaveButton(placeId: place.id),
          _CardMenu(placeId: place.id, placeName: place.name),
        ],
      ),
    );
  }
}

/// Menu do card salvo: "Adicionar a lista" e "Remover do Quero ir".
class _CardMenu extends StatelessWidget {
  const _CardMenu({required this.placeId, required this.placeName});

  final String placeId;
  final String placeName;

  static const removeLabel = 'Remover do Quero ir';

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      key: Key('saved-menu-$placeId'),
      tooltip: 'Mais opções para $placeName',
      onSelected: (value) {
        switch (value) {
          case 'add':
            showAddToListSheet(context, placeId);
          case 'remove':
            QueroIrActions.remove(context, placeId);
        }
      },
      itemBuilder: (context) => [
        // Lido ao abrir o menu: o card não precisa reconstruir com as listas.
        if (context.read<ListsStore?>() != null)
          const PopupMenuItem(
            value: 'add',
            child: ListTile(
              leading: Icon(Icons.playlist_add),
              title: Text(QueroIrActions.addToListLabel),
            ),
          ),
        const PopupMenuItem(
          value: 'remove',
          child: ListTile(
            leading: Icon(Icons.bookmark_remove_outlined),
            title: Text(removeLabel),
          ),
        ),
      ],
    );
  }
}

/// Chips do topo da aba: "Todos" + uma por lista, com contagem. O chip da
/// lista ativa abre o menu Renomear/Excluir.
class ListChips extends StatelessWidget {
  const ListChips({super.key, required this.viewModel});

  final SavedViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final selected = vm.selectedList;
    // Altura mínima, não fixa: com fonte grande o chip cresce sem cortar.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            ChoiceChip(
              key: const Key('list-chip-all'),
              label: Text('Todos · ${vm.savedCount}'),
              selected: selected == null,
              onSelected: (_) => vm.selectList(null),
            ),
            for (final list in vm.lists) ...[
              const SizedBox(width: 8),
              if (list.id == selected?.id)
                _ActiveListChip(viewModel: vm, list: list)
              else
                ChoiceChip(
                  key: Key('list-chip-${list.id}'),
                  label: Text('${list.label} · ${vm.countOf(list)}'),
                  selected: false,
                  onSelected: (_) => vm.selectList(list.id),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActiveListChip extends StatelessWidget {
  const _ActiveListChip({required this.viewModel, required this.list});

  final SavedViewModel viewModel;
  final PlaceList list;

  void _fail(ScaffoldMessengerState messenger) {
    if (!messenger.mounted) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text(saveFailureMessage)));
  }

  Future<void> _rename(BuildContext context) async {
    final lists = viewModel.listsStore;
    if (lists == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showRenameListDialog(context, lists, list);
    if (ok == false) _fail(messenger);
  }

  Future<void> _delete(BuildContext context) async {
    final lists = viewModel.listsStore;
    if (lists == null) return;
    final messenger = ScaffoldMessenger.of(context);
    if (!await confirmDeleteList(context, list)) return;
    viewModel.selectList(null);
    if (!await lists.delete(list.id)) {
      _fail(messenger);
      // A lista voltou: volta a selecioná-la (se a pessoa não escolheu outra).
      if (viewModel.selectedList == null) viewModel.selectList(list.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.edit_outlined),
          onPressed: () => _rename(context),
          child: const Text('Renomear lista'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.delete_outline),
          onPressed: () => _delete(context),
          child: const Text('Excluir lista'),
        ),
      ],
      builder: (context, controller, _) {
        void toggle() =>
            controller.isOpen ? controller.close() : controller.open();
        // Botão de menu para leitores de tela.
        return Semantics(
          container: true,
          button: true,
          selected: true,
          label: 'Opções da lista ${list.label}',
          hint: 'Abre Renomear e Excluir',
          onTap: toggle,
          excludeSemantics: true,
          child: ChoiceChip(
            key: Key('list-chip-${list.id}'),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${list.label} · ${viewModel.countOf(list)}'),
                const Icon(Icons.arrow_drop_down, size: 18),
              ],
            ),
            selected: true,
            onSelected: (_) => toggle(),
          ),
        );
      },
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

/// Erro ao carregar as listas: discreto, acima dos cards (o "Quero ir"
/// continua funcionando).
class _ListsErrorBanner extends StatelessWidget {
  const _ListsErrorBanner({required this.onRetry});

  final Future<void> Function() onRetry;

  static const message = 'Não foi possível carregar suas listas';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      key: const Key('lists-error-banner'),
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        child: Row(
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(message, style: theme.textTheme.bodyMedium)),
            TextButton(onPressed: onRetry, child: const Text('Tentar de novo')),
          ],
        ),
      ),
    );
  }
}
