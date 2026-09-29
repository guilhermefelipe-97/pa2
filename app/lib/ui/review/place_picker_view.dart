import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../routing/routes.dart';
import 'place_picker_view_model.dart';

class PlacePickerView extends StatefulWidget {
  const PlacePickerView({super.key, required this.viewModel});

  final PlacePickerViewModel viewModel;

  @override
  State<PlacePickerView> createState() => _PlacePickerViewState();
}

class _PlacePickerViewState extends State<PlacePickerView> {
  @override
  void initState() {
    super.initState();
    widget.viewModel.load();
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    return Scaffold(
      appBar: AppBar(title: const Text('Onde você foi?')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Buscar local ou bairro',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: vm.setQuery,
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: vm,
              builder: (context, _) {
                if (vm.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (vm.errorMessage != null) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(vm.errorMessage!),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: vm.load, child: const Text('Tentar de novo')),
                      ],
                    ),
                  );
                }
                final places = vm.places;
                if (places.isEmpty) {
                  return const Center(child: Text('Nenhum local encontrado.'));
                }
                return ListView.builder(
                  itemCount: places.length,
                  itemBuilder: (context, i) {
                    final p = places[i];
                    return ListTile(
                      leading: const Icon(Icons.place),
                      title: Text(p.name),
                      subtitle: Text('${p.category} · ${p.neighborhood}'),
                      onTap: () async {
                        final saved =
                            await context.push<bool>(Routes.reviewFor(p.id), extra: p);
                        if (saved == true && context.mounted) context.pop(true);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
