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
    // Seguir alguém num perfil (aberto de outra aba) muda os botões daqui.
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
    // Enter: busca já, sem deixar o debounce disparar uma segunda busca.
    _debounce?.cancel();
    widget.viewModel.search(value);
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pessoas'),
        actions: const [SettingsButton()],
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: EditorialHeading(
              eyebrow: 'Comunidade local',
              title: 'Descobrir Pessoas',
              description:
                  'Construa sua rede confiável. Busque pelo nome de quem você conhece.',
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: TextField(
              key: const Key('people-search'),
              decoration: const InputDecoration(
                hintText: 'Buscar pelo nome',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: _onChanged,
              onSubmitted: _onSubmitted,
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: vm,
              builder: (context, _) {
                return Column(
                  children: [
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
        ],
      ),
    );
  }

  Widget _buildList(PeopleViewModel vm) {
    if (vm.lastQuery.isEmpty) {
      return const Center(
        child: Text('Digite um nome para encontrar pessoas.'),
      );
    }
    if (!vm.isSearching && vm.results.isEmpty) {
      return const Center(child: Text('Ninguém encontrado com esse nome.'));
    }
    return ListView.builder(
      itemCount: vm.results.length,
      itemBuilder: (context, i) {
        final p = vm.results[i];
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
