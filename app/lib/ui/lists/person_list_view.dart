import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/place.dart';
import '../../routing/routes.dart';
import '../feed/widgets/feed_card.dart' show placeSubtitle;
import '../feed/widgets/place_photo.dart';
import 'person_list_view_model.dart';

/// Lista visível de uma pessoa (F13): os locais e "Copiar lista".
class PersonListView extends StatefulWidget {
  const PersonListView({super.key, required this.viewModel});

  final PersonListViewModel viewModel;

  @override
  State<PersonListView> createState() => _PersonListViewState();
}

class _PersonListViewState extends State<PersonListView> {
  @override
  void initState() {
    super.initState();
    widget.viewModel
      ..addListener(_onChange)
      ..load();
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    final notice = widget.viewModel.takeNotice();
    if (notice == null) return;
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    // A tela pode já ter saído quando a pessoa tocar "Ver".
    final router = GoRouter.of(context);
    switch (notice) {
      case CopyDone(:final listId, :final message):
        messenger.showSnackBar(
          SnackBar(
            content: Text(message),
            action: SnackBarAction(
              label: 'Ver',
              onPressed: () {
                widget.viewModel.focusCopied(listId);
                router.go(Routes.saved);
              },
            ),
          ),
        );
      case CopyFailed():
        messenger.showSnackBar(
          const SnackBar(content: Text(PersonListViewModel.copyFailedText)),
        );
    }
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.person(widget.viewModel.ownerUid));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        final list = vm.list;
        return Scaffold(
          appBar: AppBar(
            leading: context.canPop() ? null : BackButton(onPressed: _back),
            title: Text(list?.label ?? ''),
          ),
          body: switch (vm.state) {
            PersonListState.loading => const Center(
              child: CircularProgressIndicator(),
            ),
            PersonListState.notFound => _Message(
              key: const Key('person-list-not-found'),
              icon: Icons.lock_outline,
              text: PersonListViewModel.notFoundText,
              actionLabel: 'Voltar',
              onAction: _back,
            ),
            PersonListState.error => _Message(
              icon: Icons.wifi_off,
              text: PersonListViewModel.loadErrorText,
              actionLabel: 'Tentar de novo',
              onAction: vm.load,
            ),
            PersonListState.signedOut => _Message(
              icon: Icons.login,
              text: 'Entre para ver esta lista',
              actionLabel: 'Entrar',
              onAction: () => context.go(Routes.login),
            ),
            PersonListState.ready => _ready(context, vm),
          },
        );
      },
    );
  }

  Widget _ready(BuildContext context, PersonListViewModel vm) {
    final theme = Theme.of(context);
    final places = vm.places;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              InkWell(
                onTap: () => context.push(Routes.person(vm.ownerUid)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    'Lista de ${vm.authorName}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
              Text(
                places.length == 1 ? '1 local' : '${places.length} locais',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              if (places.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Nada nesta lista ainda',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              for (final p in places)
                _PlaceRow(
                  key: ValueKey('person-list-place-${p.id}'),
                  place: p,
                  onTap: () => context.push(Routes.placeDetail(p.id), extra: p),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (vm.listsLoading)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      PersonListViewModel.listsLoadingText,
                      key: const Key('person-list-lists-loading'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (vm.listsFailed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      key: const Key('person-list-lists-failed'),
                      children: [
                        Expanded(
                          child: Text(
                            PersonListViewModel.listsFailedText,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        TextButton(
                          onPressed: vm.retryLists,
                          child: const Text('Tentar de novo'),
                        ),
                      ],
                    ),
                  ),
                if (vm.limitReached)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      PersonListViewModel.limitText,
                      key: const Key('person-list-limit'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                FilledButton.icon(
                  key: const Key('person-list-copy'),
                  onPressed: vm.canCopy ? vm.copy : null,
                  icon: vm.isCopying
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.library_add_outlined),
                  label: const Text('Copiar lista'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({super.key, required this.place, required this.onTap});

  final Place place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = placeSubtitle(place.neighborhood, place.category);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        label: 'Abrir ${place.name}',
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          child: Row(
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: PlacePhoto(place: place, iconSize: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
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
                          color: theme.colorScheme.tertiary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    super.key,
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
