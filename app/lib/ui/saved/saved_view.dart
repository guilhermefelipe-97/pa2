import '../core/place_location_chip.dart';
import 'saved_place_rating.dart';
import '../lists/list_category.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../domain/models/place_list.dart';
import '../../domain/relative_time.dart';
import '../../routing/routes.dart';
import '../core/messages.dart';
import '../core/editorial.dart';
import '../core/save_button.dart';
import '../decision/decision_sheet.dart';
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

  static const privateCaption = 'Só você vê esta lista';

  /// Lista ativa com "Visível para quem me segue" (F13).
  static const visibleCaption = 'Quem te segue vê esta lista';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            const Flexible(child: PlaceLocationChip(shortLabel: true)),
          ],
        ),
        actions: [
          if (MediaQuery.textScalerOf(context).scale(1) <= 1.3)
            ListenableBuilder(
              listenable: viewModel,
              builder: (context, _) {
                final items = viewModel.items;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: TextButton(
                    key: const Key('saved-decide'),
                    // Sem salvos no chip ativo: nada a decidir.
                    onPressed: items.isEmpty
                        ? null
                        : () => showDecisionSheet(context, candidates: items),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      padding: EdgeInsets.zero,
                    ),
                    child: const Tooltip(
                      message: decideLabel,
                      child: Icon(Icons.casino_outlined, size: 20),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      body: ListenableBuilder(
        listenable: viewModel,
        builder: (context, _) {
          if (viewModel.isLoading) {
            return const EditorialLoading();
          }
          // Puxar para atualizar em todos os estados (lista, vazio, erro).
          final refreshable = RefreshIndicator(
            onRefresh: viewModel.refresh,
            child: _body(context),
          );
          final listsFailed = viewModel.listsFailed;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'Quero ir',
                              maxLines: 1,
                              style: TextStyle(
                                fontFamily: 'Epilogue',
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            '(${viewModel.items.length} ${viewModel.items.length == 1 ? 'salvo' : 'salvos'})',
                            key: const Key('saved-count'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (context.watch<ListsStore?>() case final lists?)
                      SizedBox(
                        width: 118,
                        child: FilledButton.tonalIcon(
                          key: const Key('saved-new-list'),
                          onPressed: lists.canCreate
                              ? () => showCreateListDialog(context, lists)
                              : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: theme.colorScheme.surfaceContainer,
                            foregroundColor: theme.colorScheme.secondary,
                            minimumSize: const Size(48, 40),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            textStyle: theme.textTheme.labelMedium,
                          ),
                          icon: const Icon(Icons.add, size: 16),
                          label: const FittedBox(
                            child: Text('Nova lista', maxLines: 1),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (MediaQuery.textScalerOf(context).scale(1) > 1.3)
                TextButton.icon(
                  key: const Key('saved-decide'),
                  onPressed: viewModel.items.isEmpty
                      ? null
                      : () => showDecisionSheet(
                          context,
                          candidates: viewModel.items,
                        ),
                  icon: const Icon(Icons.casino_outlined),
                  label: const Text(decideLabel),
                ),
              if (listsFailed) _ListsErrorBanner(onRetry: viewModel.retryLists),
              ListChips(viewModel: viewModel),
              if (viewModel.selectedList != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Text(
                    viewModel.isSelectedListVisible
                        ? SavedView.visibleCaption
                        : SavedView.privateCaption,
                    key: const Key('saved-caption'),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
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
        final offset = banner ? 1 : 0;
        final item = items[i - offset];
        return SavedCard(
          key: ValueKey('saved-${item.place.id}'),
          item: item,
          now: now,
          revision: vm.revision,
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
    this.revision = 0,
  });

  final int revision;
  final SavedItem item;
  final DateTime now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final place = item.place;
    final subtitle = placeSubtitle(place.neighborhood, place.category);
    return Tooltip(
      message: savedAgo(item.savedAt, now),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                label: 'Abrir ${place.name}',
                child: InkWell(
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child: SizedBox(
                            width: 52,
                            height: 52,
                            child: Hero(
                              tag: 'place-photo-${place.id}',
                              child: PlacePhoto(place: place, iconSize: 26),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      place.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                  SavedPlaceRating(
                                    key: ValueKey(
                                      'rating-${place.id}-$revision',
                                    ),
                                    placeId: place.id,
                                  ),
                                ],
                              ),
                              if (subtitle.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SaveButton(placeId: place.id),
            _CardMenu(placeId: place.id, placeName: place.name),
          ],
        ),
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
      icon: Icon(
        Icons.chevron_right,
        color: Theme.of(context).colorScheme.secondary,
        size: 20,
      ),
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
              avatar: Icon(
                Icons.bookmarks_outlined,
                size: 16,
                color: selected == null
                    ? Theme.of(context).colorScheme.onPrimary
                    : null,
              ),
              showCheckmark: false,
              label: Text('Todos os salvos · ${vm.savedCount}'),
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
                  avatar: Icon(
                    listCategoryIcon(list.emoji),
                    size: 16,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                  showCheckmark: false,
                  label: Text('${list.name} · ${vm.countOf(list)}'),
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

class _ActiveListChip extends StatefulWidget {
  const _ActiveListChip({required this.viewModel, required this.list});

  final SavedViewModel viewModel;
  final PlaceList list;

  @override
  State<_ActiveListChip> createState() => _ActiveListChipState();
}

class _ActiveListChipState extends State<_ActiveListChip> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Scrollable.ensureVisible(context, alignment: .5);
    });
  }

  /// "Copiada N vezes" (F13, N32), lido ao abrir o menu; `null` = ainda não
  /// leu ou falhou (oculto).
  int? _copies;
  int _countSeq = 0;

  SavedViewModel get viewModel => widget.viewModel;
  PlaceList get list => widget.list;

  @override
  void didUpdateWidget(_ActiveListChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Outra lista: o contador lido era da anterior (e uma leitura em voo
    // dela é descartada).
    if (oldWidget.list.id != widget.list.id) {
      _copies = null;
      _countSeq++;
    }
  }

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

  /// "Visível para quem me segue" (otimista): falha reverte e avisa.
  Future<void> _toggleVisible(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await viewModel.setSelectedListVisible(!list.visible)) {
      _fail(messenger);
    }
  }

  Future<void> _loadCopies() async {
    final seq = ++_countSeq;
    final n = await viewModel.copyCountOf(list);
    if (!mounted || seq != _countSeq) return;
    setState(() => _copies = n);
  }

  @override
  Widget build(BuildContext context) {
    final credit = list.copiedFrom;
    final copies = _copies;
    return MenuAnchor(
      onOpen: _loadCopies,
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.edit_outlined),
          onPressed: () => _rename(context),
          child: const Text('Renomear lista'),
        ),
        CheckboxMenuButton(
          key: const Key('list-visible'),
          value: list.visible,
          onChanged: (_) => _toggleVisible(context),
          child: const Text(visibleToFollowersLabel),
        ),
        if (credit != null)
          MenuItemButton(
            key: const Key('list-credit'),
            leadingIcon: const Icon(Icons.person_outline),
            onPressed: () => context.push(Routes.person(credit.uid)),
            child: Text('Copiada de ${credit.name}'),
          ),
        if (copies != null && copies > 0)
          MenuItemButton(
            key: const Key('list-copies'),
            leadingIcon: const Icon(Icons.content_copy_outlined),
            // Informativo: só a contagem.
            onPressed: null,
            child: Text(copiesLabel(copies)),
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
          label: 'Opções da lista ${list.name}',
          hint: 'Abre Renomear, Visível para quem me segue e Excluir',
          onTap: toggle,
          excludeSemantics: true,
          child: ChoiceChip(
            key: Key('list-chip-${list.id}'),
            showCheckmark: false,
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  listCategoryIcon(list.emoji),
                  size: 16,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
                const SizedBox(width: 6),
                Text('${list.name} · ${viewModel.countOf(list)}'),
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

/// Item do menu da lista (F13).
const visibleToFollowersLabel = 'Visível para quem me segue';

/// "Copiada 1 vez", "Copiada 3 vezes".
String copiesLabel(int n) => n == 1 ? 'Copiada 1 vez' : 'Copiada $n vezes';

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
                backgroundColor: scheme.surfaceContainerLow,
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
