import 'dart:async';

import 'package:flutter/material.dart';

import 'people_view_model.dart';

class PeopleView extends StatefulWidget {
  const PeopleView({super.key, required this.viewModel});

  final PeopleViewModel viewModel;

  @override
  State<PeopleView> createState() => _PeopleViewState();
}

class _PeopleViewState extends State<PeopleView> {
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    widget.viewModel.init();
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
      appBar: AppBar(title: const Text('Pessoas')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
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
                        padding: const EdgeInsets.all(12),
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
        return ListTile(
          leading: CircleAvatar(
            child: Text(p.displayName.characters.first.toUpperCase()),
          ),
          title: Text(p.displayName),
          trailing: following
              ? OutlinedButton(
                  onPressed: enabled ? () => vm.toggleFollow(p.uid) : null,
                  child: const Text('Seguindo'),
                )
              : FilledButton(
                  onPressed: enabled ? () => vm.toggleFollow(p.uid) : null,
                  child: const Text('Seguir'),
                ),
        );
      },
    );
  }
}
