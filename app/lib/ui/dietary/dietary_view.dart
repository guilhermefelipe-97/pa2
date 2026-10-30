import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/food_tags.dart';
import 'dietary_store.dart';

class DietaryView extends StatefulWidget {
  const DietaryView({super.key});
  @override
  State<DietaryView> createState() => _DietaryViewState();
}

class _DietaryViewState extends State<DietaryView> {
  Set<String>? selected;
  int? epoch;
  @override
  Widget build(BuildContext context) {
    final store = context.watch<DietaryStore>();
    if (epoch != store.sessionEpoch) {
      epoch = store.sessionEpoch;
      selected = null;
    }
    if (store.ready) selected ??= {...store.tags};
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil alimentar')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'No feed de amigos, mostrar apenas locais com todas as tags selecionadas confirmadas por pelo menos 3 pessoas da comunidade.',
              ),
              const Text(
                'Tags comunitárias não são certificações nutricionais.',
              ),
              if (store.loading) const LinearProgressIndicator(),
              if (store.error != null) ...[
                Text(store.error!),
                TextButton(
                  onPressed: store.load,
                  child: const Text('Tentar novamente'),
                ),
              ],
              if (selected != null) ...[
                Wrap(
                  spacing: 8,
                  children: [
                    for (final tag in foodTags)
                      FilterChip(
                        label: Text(tag),
                        selected: selected!.contains(tag),
                        onSelected: store.loading
                            ? null
                            : (on) => setState(() {
                                if (on) {
                                  selected!.add(tag);
                                } else {
                                  selected!.remove(tag);
                                }
                              }),
                      ),
                  ],
                ),
                TextButton(
                  onPressed: store.loading
                      ? null
                      : () => setState(() => selected = {}),
                  child: const Text('Limpar filtro'),
                ),
                FilledButton(
                  onPressed: store.loading
                      ? null
                      : () async {
                          final navigator = Navigator.of(context);
                          if (await store.save(selected!) && mounted) {
                            navigator.pop();
                          }
                        },
                  child: const Text('Salvar preferências'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
