import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/place_repository.dart' show placeSearchLimit;
import '../../domain/models/place.dart';
import '../../routing/routes.dart';
import '../core/category_style.dart';
import '../core/osm_credit.dart';
import '../core/save_button.dart';
import '../feed/widgets/feed_card.dart' show placeSubtitle;
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

  /// Guarda contra toque duplo: só uma avaliação por vez.
  bool _opening = false;

  Future<void> _pick(Place p) async {
    if (_opening) return;
    _opening = true;
    try {
      final saved = await context.push<bool>(Routes.reviewFor(p.id), extra: p);
      if (saved == true && mounted) context.pop(true);
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    return Scaffold(
      appBar: AppBar(title: const Text('Onde você foi?')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              key: const Key('place-search'),
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Buscar local pelo nome',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: vm.setQuery,
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: vm,
              builder: (context, _) => _body(context, vm),
            ),
          ),
          const SafeArea(
            top: false,
            child: OsmCredit(padding: EdgeInsets.fromLTRB(16, 4, 16, 8)),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, PlacePickerViewModel vm) {
    final theme = Theme.of(context);
    if (vm.errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(vm.errorMessage!),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: vm.retry,
              child: const Text('Tentar de novo'),
            ),
          ],
        ),
      );
    }
    if (vm.isLoading) return const _SkeletonList();
    if (vm.showNoResults) {
      return const _EmptyMessage(
        title: 'Nenhum local com esse nome',
        hint: 'Tente só uma palavra do nome',
      );
    }

    final places = vm.places;
    if (vm.isShowingSuggestions && places.isEmpty) {
      return const _EmptyMessage(title: 'Digite o nome do local para buscar');
    }
    final categories = vm.categories;
    final capped = vm.isResultCapped;
    return ListView.builder(
      itemCount: places.length + 1 + (capped ? 1 : 0),
      itemBuilder: (context, i) {
        if (capped && i == places.length + 1) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Text(
              'Mostrando os $placeSearchLimit primeiros — digite mais do nome para refinar',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        if (i == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (categories.length > 1)
                SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      for (final c in categories)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(c),
                            selected: vm.selectedCategory == c,
                            onSelected: (_) => vm.selectCategory(c),
                          ),
                        ),
                    ],
                  ),
                ),
              if (vm.isShowingSuggestions && places.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text('Sugestões', style: theme.textTheme.labelLarge),
                ),
            ],
          );
        }
        final p = places[i - 1];
        final subtitle = placeSubtitle(p.neighborhood, p.category);
        return ListTile(
          leading: Icon(categoryIcon(p.category)),
          title: Text(p.name),
          subtitle: subtitle.isEmpty ? null : Text(subtitle),
          trailing: SaveButton(placeId: p.id),
          onTap: () => _pick(p),
        );
      },
    );
  }
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage({required this.title, this.hint});

  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (hint != null) ...[
              const SizedBox(height: 6),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Placeholder enquanto a busca responde.
class _SkeletonList extends StatelessWidget {
  const _SkeletonList();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
    );
    return Semantics(
      label: 'Buscando locais',
      child: ListView.builder(
        key: const Key('place-skeleton'),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 6,
        itemBuilder: (context, i) => ListTile(
          leading: bar(24, 24),
          title: Align(alignment: Alignment.centerLeft, child: bar(160, 14)),
          subtitle: Align(alignment: Alignment.centerLeft, child: bar(110, 12)),
        ),
      ),
    );
  }
}
