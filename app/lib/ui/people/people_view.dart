import 'package:go_router/go_router.dart';
import '../../routing/routes.dart';
import '../feed/widgets/author_avatar.dart';
import '../core/editorial.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_shell.dart';
import 'people_view_model.dart';

class PeopleView extends StatefulWidget {
  const PeopleView({super.key, required this.viewModel});

  final PeopleViewModel viewModel;

  @override
  State<PeopleView> createState() => _PeopleViewState();
}

class _PeopleViewState extends State<PeopleView> {
  bool _followingTab = false;
  Timer? _debounce;
  bool? _active;

  @override
  void initState() {
    super.initState();
    widget.viewModel.init();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final active = ActiveTab.maybeOf(context);
    if (active == true && _active == false) widget.viewModel.reloadIfStale();
    _active = active;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      widget.viewModel.search(value);
    });
  }

  void _onSubmitted(String value) {
    _debounce?.cancel();
    widget.viewModel.search(value);
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    return Scaffold(
      appBar: AppBar(title: const Text('NaÁrea')),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverToBoxAdapter(
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: EditorialHeading(
                    eyebrow: 'Comunidade local',
                    title: 'Descobrir Pessoas',
                    description:
                        'Encontre criadores, amigos e amantes da boa gastronomia na sua região.',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: TextField(
                    key: const Key('people-search'),
                    decoration: const InputDecoration(
                      hintText: 'Buscar pelo nome',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(28)),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: _onChanged,
                    onSubmitted: _onSubmitted,
                  ),
                ),
              ],
            ),
          ),
        ],
        body: ListenableBuilder(
          listenable: vm,
          builder: (context, _) {
            return Column(
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Buscar pessoas'),
                        selected: !_followingTab,
                        onSelected: (_) =>
                            setState(() => _followingTab = false),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: Text('Seguindo ${vm.followingCount}'),
                        selected: _followingTab,
                        onSelected: !vm.isReady
                            ? null
                            : (_) {
                                setState(() => _followingTab = true);
                                vm.loadFollowingProfiles();
                              },
                      ),
                    ],
                  ),
                ),
                if (vm.isSearching) const LinearProgressIndicator(),
                if (vm.initState == PeopleInitState.error)
                  MaterialBanner(
                    content: const Text(PeopleViewModel.initErrorMessage),
                    actions: [
                      TextButton(
                        onPressed: vm.init,
                        child: const Text('Tentar de novo'),
                      ),
                    ],
                  ),
                if (vm.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    child: Text(
                      vm.errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                Expanded(child: _buildList(vm)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildList(PeopleViewModel vm) {
    if (_followingTab && vm.loadingFollowing) return const EditorialLoading();
    if (!_followingTab && vm.lastQuery.isEmpty) {
      return const Center(
        child: Text('Digite um nome para encontrar pessoas.'),
      );
    }
    final results = _followingTab
        ? vm.followingProfiles
              .where(
                (p) => p.displayName.toLowerCase().contains(
                  vm.lastQuery.toLowerCase(),
                ),
              )
              .toList()
        : vm.results;
    if (!vm.isSearching && results.isEmpty) {
      if (_followingTab && vm.lastQuery.isEmpty) {
        return const Center(child: Text('Você ainda não segue ninguém.'));
      }
      return const Center(child: Text('Ninguém encontrado com esse nome.'));
    }
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, i) {
        final p = results[i];
        final following = vm.isFollowing(p.uid);
        final enabled = vm.canToggle(p.uid);
        return Card(
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AuthorAvatar(id: p.uid, name: p.displayName, radius: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        p.displayName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    following
                        ? OutlinedButton(
                            onPressed: enabled
                                ? () => vm.toggleFollow(p.uid)
                                : null,
                            child: const Text('Seguindo'),
                          )
                        : FilledButton(
                            onPressed: enabled
                                ? () => vm.toggleFollow(p.uid)
                                : null,
                            child: const Text('Seguir'),
                          ),
                    TextButton(
                      onPressed: () => context.push(Routes.person(p.uid)),
                      child: const Text('Ver perfil'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
