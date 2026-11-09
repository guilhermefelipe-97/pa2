import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dietary_store.dart';
import 'food_filter_options.dart';
import '../../domain/food_tags.dart';

Future<void> showFeedFilters(BuildContext context) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheet) => SizedBox(
      height: MediaQuery.sizeOf(sheet).height * .88,
      child: DietaryFilterPanel(
        onDone: () => Navigator.of(sheet).pop(),
        onCancel: () => Navigator.of(sheet).pop(),
      ),
    ),
  );
}

class DietaryFilterPanel extends StatefulWidget {
  const DietaryFilterPanel({
    super.key,
    required this.onDone,
    required this.onCancel,
  });
  final VoidCallback onDone, onCancel;
  @override
  State<DietaryFilterPanel> createState() => _FilterState();
}

class _FilterState extends State<DietaryFilterPanel> {
  Set<String>? selected;
  int? epoch;
  bool saving = false;
  Future<void> apply() async {
    final store = context.read<DietaryStore>();
    if (saving || selected == null || store.loading || !store.ready) return;
    final at = store.sessionEpoch;
    setState(() => saving = true);
    final ok = await store.save(Set.of(selected!));
    if (!mounted || store.sessionEpoch != at) return;
    setState(() => saving = false);
    if (ok) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DietaryStore>();
    if (epoch != store.sessionEpoch) {
      epoch = store.sessionEpoch;
      selected = null;
      saving = false;
    }
    if (store.ready) selected ??= {...store.tags};
    final theme = Theme.of(context), scheme = Theme.of(context).colorScheme;
    final blocked = saving || store.loading;
    return PopScope(
      canPop: !saving,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 8, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.tune_rounded,
                    color: scheme.secondary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Filtrar feed', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 3),
                      Text(
                        'Seu jeito de comer',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const Key('food-filter-close'),
                  tooltip: 'Fechar filtros',
                  onPressed: saving ? null : widget.onCancel,
                  icon: const Icon(Icons.close, size: 22),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              children: [
                Text(
                  'O que você quer encontrar?',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Escolha as tags dos lugares que deseja ver no feed de Amigos.',
                ),
                const SizedBox(height: 16),
                if (store.loading) const LinearProgressIndicator(),
                if (!store.ready && !store.loading)
                  Center(
                    child: TextButton(
                      onPressed: store.load,
                      child: const Text('Tentar novamente'),
                    ),
                  ),
                if (selected != null) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          selected!.isEmpty
                              ? 'Sem filtros alimentares'
                              : '${selected!.length} ${selected!.length == 1 ? 'tag selecionada' : 'tags selecionadas'}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      TextButton(
                        key: const Key('food-filter-clear'),
                        onPressed: blocked || selected!.isEmpty
                            ? null
                            : () => setState(() => selected = {}),
                        child: const Text('Limpar'),
                      ),
                    ],
                  ),
                  for (final option in foodFilterOptions) ...[
                    if (option.tag == homeFoodTags.first)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(2, 8, 0, 8),
                        child: Text(
                          'Comida caseira',
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Semantics(
                        button: true,
                        selected: selected!.contains(option.tag),
                        child: Material(
                          color: selected!.contains(option.tag)
                              ? scheme.surfaceContainerLow
                              : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: selected!.contains(option.tag)
                                  ? scheme.secondary
                                  : scheme.surfaceContainer,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            key: Key('food-filter-${option.tag}'),
                            onTap: blocked
                                ? null
                                : () => setState(() {
                                    if (!selected!.remove(option.tag)) {
                                      selected!.add(option.tag);
                                    }
                                  }),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  Icon(
                                    option.icon,
                                    size: 25,
                                    color: scheme.secondary,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          option.label,
                                          style: theme.textTheme.titleSmall,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          option.detail,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: scheme.onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    selected!.contains(option.tag)
                                        ? Icons.check_circle
                                        : Icons.circle_outlined,
                                    color: selected!.contains(option.tag)
                                        ? scheme.secondary
                                        : scheme.outlineVariant,
                                    size: 22,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Como funcionam as tags?'),
                    children: const [
                      Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: Text(
                          'Uma tag é confirmada por pelo menos 3 pessoas da comunidade. Ao selecionar mais de uma, o feed mostra locais com todas elas confirmadas. Sua escolha fica salva para as próximas visitas ao app.\n\nTags comunitárias não são certificações nutricionais.',
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(top: BorderSide(color: scheme.surfaceContainer)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (store.error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          store.error!,
                          style: TextStyle(color: scheme.error),
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: saving ? null : widget.onCancel,
                          child: const FittedBox(
                            child: Text('Cancelar', maxLines: 1),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          key: const Key('food-filter-apply'),
                          onPressed: blocked || selected == null || !store.ready
                              ? null
                              : apply,
                          child: FittedBox(
                            child: Text(
                              saving ? 'Aplicando…' : 'Aplicar filtros',
                              maxLines: 1,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
