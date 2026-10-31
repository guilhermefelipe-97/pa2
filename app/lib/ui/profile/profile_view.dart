import '../owner/reply_line.dart';
import 'package:provider/provider.dart';
import '../core/editorial.dart';
import '../lists/lists_store.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/place_activity.dart';
import '../../domain/models/place_list.dart';
import '../../domain/relative_time.dart';
import '../../routing/routes.dart';
import '../feed/widgets/author_avatar.dart';
import '../feed/widgets/axis_scores.dart';
import '../feed/widgets/visit_tile.dart' show visitMeta, visitTileLabel;
import 'profile_view_model.dart';

/// Perfil simples (`/pessoa/:uid`): nome, Seguir/Seguindo e as avaliações e
/// visitas ("Voltei aqui", F15) da pessoa, mais recentes primeiro.
class ProfileView extends StatefulWidget {
  const ProfileView({super.key, required this.viewModel});

  final ProfileViewModel viewModel;

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  int selectedTab = 0;
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

  // O local pode levar a outro perfil, onde seguir/deixar de seguir muda
  // este: recarrega ao voltar, se mudou.
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
            // Aberto por link direto: sem tela anterior, "voltar" vai ao feed.
            leading: context.canPop() ? null : BackButton(onPressed: _back),
            title: Text(vm.state == ProfileState.ready ? vm.title : ''),
            actions: [if (vm.isSelf) const SettingsButton()],
          ),
          body: switch (vm.state) {
            ProfileState.loading => const Center(
              child: CircularProgressIndicator(),
            ),
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
            ProfileState.ready => _ready(context, vm),
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
    if (selectedTab == 2) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          _Header(viewModel: vm),
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
    } // Item 0: cabeçalho; depois avaliações e visitas (ou o texto de vazio).
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      itemCount: 1 + (reviews.isEmpty ? 1 : reviews.length),
      itemBuilder: (context, i) {
        if (i == 0)
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(viewModel: vm),
              _tabs(vm),
            ],
          );
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
          final Review r => _ProfileReviewTile(
            key: ValueKey('profile-review-${r.id}'),
            review: r,
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
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (index, label) in [
                (0, 'Avaliações'),
                (1, 'Visitas'),
                (2, 'Listas'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    key: Key('profile-tab-$index'),
                    label: Text(label),
                    selected: selectedTab == index,
                    onSelected: (_) => setState(() => selectedTab = index),
                  ),
                ),
            ],
          ),
        ),
        if (selectedTab != 2)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              selectedTab == 0
                  ? '${vm.reviews.length} avaliações recentes'
                  : '${vm.activities.whereType<Visit>().length} visitas recentes',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.viewModel});

  final ProfileViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final theme = Theme.of(context);
    final name = vm.displayName;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ExcludeSemantics(
                  child: AuthorAvatar(id: vm.uid, name: name, radius: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(name, style: theme.textTheme.headlineSmall),
                ),
              ],
            ),
            if (!vm.isSelf) ...[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: vm.isFollowing
                    ? OutlinedButton(
                        key: const Key('profile-follow'),
                        onPressed: vm.isBusy ? null : vm.toggleFollow,
                        child: Text(
                          'Seguindo',
                          semanticsLabel:
                              'Seguindo $name. Toque para deixar de seguir',
                        ),
                      )
                    : FilledButton(
                        key: const Key('profile-follow'),
                        onPressed: vm.isBusy ? null : vm.toggleFollow,
                        child: Text('Seguir', semanticsLabel: 'Seguir $name'),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Uma lista visível no perfil (F13): emoji, nome e quantos locais.
class _ProfileListTile extends StatelessWidget {
  const _ProfileListTile({super.key, required this.list, required this.onTap});

  final PlaceList list;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = placesCountLabel(list.placeIds.length);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: list.emoji == null
            ? Icon(Icons.list_alt, color: theme.colorScheme.primary)
            : Text(list.emoji!, style: const TextStyle(fontSize: 20)),
      ),
      title: Text(list.name),
      subtitle: Text(count),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// "1 local", "12 locais".
String placesCountLabel(int n) => n == 1 ? '1 local' : '$n locais';

/// Uma avaliação no perfil: local, 3 eixos, comentário e contexto. O item
/// inteiro é um botão "Abrir `local`".
class _ProfileReviewTile extends StatelessWidget {
  const _ProfileReviewTile({
    super.key,
    required this.review,
    required this.now,
    required this.onTap,
  });

  final Review review;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = [
      review.dayPeriod.label,
      if (review.companion != null) review.companion!.label,
      relativeTime(review.createdAt, now),
    ].join(' · ');
    return MergeSemantics(
      child: Semantics(
        button: true,
        label: 'Abrir ${review.placeName}',
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(review.placeName, style: theme.textTheme.titleMedium),
                Text(
                  meta,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                AxisScores.scores(review.scores),
                ReplyLine(reviewId: review.id),
                if (review.comment?.trim().isNotEmpty ?? false) ...[
                  const SizedBox(height: 8),
                  Text(review.comment!, style: theme.textTheme.bodyMedium),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Uma visita no perfil (F15): local e contexto, sem notas.
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
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
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
