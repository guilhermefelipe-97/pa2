import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/place_repository.dart' show placeSearchLimit;
import '../../domain/models/place.dart';
import '../../domain/geo.dart';
import '../../routing/routes.dart';
import '../core/osm_credit.dart';
import '../core/save_button.dart';
import '../feed/widgets/feed_card.dart' show placeSubtitle;
import '../feed/widgets/place_photo.dart';
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
      appBar: AppBar(title: const Text('Onde Você Foi?')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: TextField(
              key: const Key('place-search'),
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Buscar restaurante, café, bar...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(16)),
                ),
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
    final capped = vm.isResultCapped;
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  vm.near == null
                      ? 'GPS indisponível • Busca por nome'
                      : 'GPS ativo • Lugares próximos na busca',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 0,
                  children: [
                    FilterChip(
                      label: Text(
                        'Todos',
                        style: TextStyle(
                          color: vm.selectedCategory == null
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                      selected: vm.selectedCategory == null,
                      onSelected: (_) => vm.selectCategory(null),
                    ),
                    for (final c in PlacePickerViewModel.filterOptions)
                      FilterChip(
                        label: Text(
                          c,
                          style: TextStyle(
                            color: vm.selectedCategory == c
                                ? theme.colorScheme.onPrimary
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                        selected: vm.selectedCategory == c,
                        onSelected: (_) => vm.selectCategory(c),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Row(
                  children: [
                    Icon(
                      vm.near == null ? Icons.search : Icons.near_me_outlined,
                      size: 16,
                      color: theme.colorScheme.secondary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        vm.isShowingSuggestions
                            ? 'Locais sugeridos'
                            : 'Resultados da busca',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    Text(
                      '${places.length} ${places.length == 1 ? 'local' : 'locais'}',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ],
          );
        }
        final p = places[i - 1];
        final subtitle = placeSubtitle(p.neighborhood, p.category);
        return Card(
          margin: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 54,
                height: 54,
                child: PlacePhoto(place: p, iconSize: 24),
              ),
            ),
            title: Text(p.name),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (subtitle.isNotEmpty)
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (vm.near != null && p.hasCoordinates)
                  Text(
                    formatDistance(
                      distanceMeters(vm.near!, (lat: p.lat!, lng: p.lng!)),
                    ),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.secondary,
                    ),
                  ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SaveButton(placeId: p.id),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () => _pick(p),
          ),
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
