import '../lists/list_category.dart';
import '../core/app_shell.dart';
import '../../data/repositories/profile_media_repository.dart';
import 'profile_media_image.dart';
import 'profile_review_card.dart';
import 'package:provider/provider.dart';
import '../core/editorial.dart';
import '../lists/lists_store.dart';
import 'package:flutter/material.dart';
import '../people/taste_match_badge.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/place_activity.dart';
import '../../domain/models/place_list.dart';
import '../../routing/routes.dart';
import '../feed/widgets/author_avatar.dart';
import '../feed/widgets/visit_tile.dart' show visitMeta, visitTileLabel;
import 'profile_view_model.dart';

class ProfileView extends StatefulWidget {
  const ProfileView({super.key, required this.viewModel});

  final ProfileViewModel viewModel;

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  int selectedTab = 0;
  bool oldestFirst = false;
  bool? _wasActive;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active =
        ActiveTab.maybeOf(context) ?? ModalRoute.isCurrentOf(context) ?? true;
    if (active && _wasActive == false) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.viewModel.load();
      });
    }
    _wasActive = active;
  }

  Future<void> refresh() async {
    context.read<ProfileMediaRepository?>()?.invalidate(widget.viewModel.uid);
    await widget.viewModel.load();
  }

  Future<void> edit() async {
    await context.push(Routes.editProfile);
    if (mounted) await refresh();
  }

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
    final vm = widget.viewModel;
    final notice = vm.takeNotice();
    if (notice == null) return;
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    switch (notice) {
      case ProfileNotice.followFailed:
        messenger.showSnackBar(
          const SnackBar(content: Text(ProfileViewModel.followErrorText)),
        );
      case ProfileNotice.unfollowed:
        messenger.showSnackBar(
          SnackBar(
            content: Text('Você deixou de seguir ${vm.title}'),
            action: SnackBarAction(
              label: 'Desfazer',
              onPressed: vm.undoUnfollow,
            ),
          ),
        );
    }
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.feed);
    }
  }

  Future<void> _openPlace(PlaceActivity r) async {
    await context.push(Routes.placeDetail(r.placeId));
    if (!mounted) return;
    widget.viewModel.reloadIfStale();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;

        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            leading: GoRouterState.of(context).uri.path == '/perfil'
                ? null
                : BackButton(onPressed: _back),
            title: const Text('Perfil do usuário'),
            actions: [if (vm.isSelf) const SettingsButton()],
          ),
          body: switch (vm.state) {
            ProfileState.loading => const Center(child: EditorialLoading()),
            ProfileState.notFound => _Message(
              key: const Key('profile-not-found'),
              icon: Icons.person_off_outlined,
              text: 'Pessoa não encontrada',
              actionLabel: 'Voltar',
              onAction: _back,
            ),
            ProfileState.error => _Message(
              icon: Icons.wifi_off,
              text: ProfileViewModel.loadErrorText,
              actionLabel: 'Tentar de novo',
              onAction: vm.load,
            ),
            ProfileState.signedOut => _Message(
              key: const Key('profile-signed-out'),
              icon: Icons.login,
              text: 'Entre para ver este perfil',
              actionLabel: 'Entrar',
              onAction: () => context.go(Routes.login),
            ),
            ProfileState.ready => RefreshIndicator(
              onRefresh: refresh,
              child: _ready(context, vm),
            ),
          },
        );
      },
    );
  }

  Widget _ready(BuildContext context, ProfileViewModel vm) {
    final now = vm.now();
    final ownLists = vm.isSelf ? context.watch<ListsStore?>() : null;
    final lists = vm.isSelf ? (ownLists?.lists ?? <PlaceList>[]) : vm.lists;
    final reviews = vm.activities
        .where((a) => selectedTab == 0 ? a is Review : a is Visit)
        .toList();
    if (oldestFirst) reviews.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (selectedTab == 2) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          _Header(viewModel: vm, onEdit: edit),
          _tabs(vm),
          if (vm.isSelf && ownLists?.isLoading == true)
            const Center(child: CircularProgressIndicator())
          else if (vm.isSelf && ownLists?.hasError == true)
            TextButton(
              onPressed: ownLists!.reload,
              child: const Text(
                'Não foi possível carregar as listas. Tentar de novo',
              ),
            )
          else if (lists.isEmpty)
            Text(
              vm.isSelf
                  ? 'Suas listas aparecem aqui. Organize seus locais em Quero ir.'
                  : 'Nenhuma lista visível para você.',
            ),
          for (final list in lists)
            _ProfileListTile(
              key: ValueKey('profile-list-${list.id}'),
              list: list,
              canCopy: !vm.isSelf,
              onTap: () {
                if (vm.isSelf) {
                  ownLists?.focusList(list.id);
                  context.go(Routes.saved);
                } else {
                  context.push(Routes.personList(vm.uid, list.id), extra: list);
                }
              },
            ),
        ],
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      itemCount: 1 + (reviews.isEmpty ? 1 : reviews.length),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(viewModel: vm, onEdit: edit),
              _tabs(vm),
            ],
          );
        }
        if (reviews.isEmpty) {
          final theme = Theme.of(context);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              vm.activities.isEmpty
                  ? vm.emptyText
                  : selectedTab == 0
                  ? 'Nenhuma avaliação recente'
                  : 'Nenhuma visita recente',
              key: const Key('profile-empty'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        return switch (reviews[i - 1]) {
          final Review r => ProfileReviewCard(
            key: ValueKey('profile-review-${r.id}'),
            review: r,
            place: vm.places[r.placeId],
            isOwn: vm.isSelf,
            now: now,
            onTap: () => _openPlace(r),
          ),
          final Visit v => _ProfileVisitTile(
            key: ValueKey('profile-visit-${v.id}'),
            visit: v,
            now: now,
            onTap: () => _openPlace(v),
          ),
        };
      },
    );
  }

  Widget _tabs(ProfileViewModel vm) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final (index, label) in [
                (0, 'Avaliações'),
                (1, 'Visitas'),
                (2, 'Listas'),
              ])
                ChoiceChip(
                  key: Key('profile-tab-$index'),
                  avatar: Icon(
                    [
                      Icons.rate_review_outlined,
                      Icons.place_outlined,
                      Icons.bookmarks_outlined,
                    ][index],
                    size: 16,
                    color: selectedTab == index ? Colors.white : Colors.black87,
                  ),
                  showCheckmark: false,
                  selectedColor: Colors.black,
                  shape: const StadiumBorder(),
                  label: Text(
                    label,
                    style: TextStyle(
                      color: selectedTab == index
                          ? Colors.white
                          : Colors.black87,
                    ),
                  ),
                  selected: selectedTab == index,
                  onSelected: (_) => setState(() => selectedTab = index),
                ),
            ],
          ),
        ),
        if (selectedTab != 2)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text(
                  selectedTab == 0
                      ? (vm.reviews.length == 1
                            ? '1 experiência recente'
                            : '${vm.reviews.length} experiências recentes')
                      : '${vm.activities.whereType<Visit>().length} visitas recentes',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                PopupMenuButton<bool>(
                  tooltip: 'Ordenar experiências',
                  initialValue: oldestFirst,
                  onSelected: (value) => setState(() => oldestFirst = value),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: false, child: Text('Mais recentes')),
                    PopupMenuItem(value: true, child: Text('Mais antigas')),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.sort, size: 14),
                        const SizedBox(width: 4),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              oldestFirst ? 'Mais antigas' : 'Mais recentes',
                              style: Theme.of(context).textTheme.bodySmall,
                              maxLines: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.viewModel, required this.onEdit});
  final ProfileViewModel viewModel;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) {
    final vm = viewModel, theme = Theme.of(context);
    final lists = context.watch<ListsStore?>();
    return LayoutBuilder(
      builder: (context, box) {
        final coverHeight = (box.maxWidth / 2.4).clamp(128.0, 180.0);
        Widget follow = Semantics(
          container: true,
          button: true,
          enabled: !vm.isBusy,
          label: vm.isFollowing
              ? 'Seguindo ${vm.title}. Toque para deixar de seguir'
              : 'Seguir ${vm.title}',
          excludeSemantics: true,
          child: vm.isFollowing
              ? OutlinedButton(
                  key: const Key('profile-follow'),
                  onPressed: vm.isBusy ? null : vm.toggleFollow,
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Seguindo', maxLines: 1),
                  ),
                )
              : FilledButton(
                  key: const Key('profile-follow'),
                  onPressed: vm.isBusy ? null : vm.toggleFollow,
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Seguir', maxLines: 1),
                  ),
                ),
        );
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: coverHeight,
                    child: ProfileMediaImage(
                      uid: vm.uid,
                      kind: 'cover',
                      placeholder: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              theme.colorScheme.primary,
                              theme.colorScheme.tertiary,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 56, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(vm.displayName, style: theme.textTheme.titleLarge),
                        if (!vm.isSelf)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: TasteMatchBadge(uid: vm.uid, detailed: true),
                          ),
                        const SizedBox(height: 4),
                        if (vm.username.isNotEmpty)
                          Text(
                            '@${vm.username}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 13,
                              color: theme.colorScheme.secondary,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        else if (vm.isSelf)
                          TextButton(
                            onPressed: onEdit,
                            child: const Text('Adicionar @usuário'),
                          )
                        else
                          Text(
                            'Usuário sem @ definido',
                            style: theme.textTheme.bodySmall,
                          ),
                        if (vm.bio.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            vm.bio,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.6,
                            ),
                          ),
                        ],
                        if (vm.instagram.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          SelectableText(
                            'instagram.com/${vm.instagram}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.secondary,
                            ),
                          ),
                        ],
                        if (vm.city.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(
                                Icons.place_outlined,
                                size: 16,
                                color: theme.colorScheme.secondary,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  vm.city,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 4,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final entry in [
                                (
                                  vm.totals.reviews ?? vm.reviews.length,
                                  vm.totals.reviews == null
                                      ? 'Avaliações recentes'
                                      : 'Avaliações',
                                ),
                                (
                                  vm.totals.visits ??
                                      vm.activities.whereType<Visit>().length,
                                  vm.totals.visits == null
                                      ? 'Visitas recentes'
                                      : 'Visitas',
                                ),
                                (
                                  vm.isSelf
                                      ? (lists?.lists.length ?? 0)
                                      : vm.lists.length,
                                  'Listas',
                                ),
                                if (vm.totals.following != null)
                                  (vm.totals.following!, 'Seguindo'),
                              ])
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${entry.$1}',
                                        style: theme.textTheme.titleMedium,
                                      ),
                                      Text(
                                        entry.$2,
                                        textAlign: TextAlign.center,
                                        style: theme.textTheme.labelSmall,
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Positioned(
                left: 16,
                top: coverHeight - 40,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: ExcludeSemantics(
                    child: AuthorAvatar(
                      id: vm.uid,
                      name: vm.displayName,
                      radius: 38,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 12,
                top: coverHeight + 8,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: box.maxWidth - 124),
                  child: vm.isSelf
                      ? OutlinedButton(
                          onPressed: onEdit,
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Editar perfil', maxLines: 1),
                          ),
                        )
                      : follow,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProfileListTile extends StatelessWidget {
  const _ProfileListTile({
    super.key,
    required this.list,
    required this.onTap,
    this.canCopy = false,
  });

  final PlaceList list;
  final VoidCallback onTap;
  final bool canCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = placesCountLabel(list.placeIds.length);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.surfaceContainer,
        child: Icon(
          listCategoryIcon(list.emoji),
          color: theme.colorScheme.primary,
        ),
      ),
      title: Text(list.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(count),
          if (canCopy)
            Text(
              'Abrir para copiar lista',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.secondary,
              ),
            ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

String placesCountLabel(int n) => n == 1 ? '1 local' : '$n locais';

class _ProfileVisitTile extends StatelessWidget {
  const _ProfileVisitTile({
    super.key,
    required this.visit,
    required this.now,
    required this.onTap,
  });

  final Visit visit;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Semantics(
        button: true,
        label: 'Abrir ${visit.placeName}',
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(visit.placeName, style: theme.textTheme.titleMedium),
                Text(
                  '$visitTileLabel · ${visitMeta(visit, now)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
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
