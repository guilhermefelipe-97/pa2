import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/photon/photon_client.dart';
import '../../domain/geo.dart';
import '../../domain/models/place.dart';
import '../../domain/price_summary.dart';
import '../../routing/routes.dart';
import '../core/app_shell.dart';
import '../core/osm_credit.dart';
import '../core/save_button.dart';
import '../feed/widgets/place_photo.dart';
import '../feed/widgets/price_chip.dart';
import '../feed/widgets/trust_sources.dart' show RecurrenceLine;
import 'nearby_view_model.dart';

/// Categoria e bairro do local (o que houver).
List<String> _placeDetails(Place place) => [
  if (place.category.trim().isNotEmpty) place.category.trim(),
  if (place.neighborhood.trim().isNotEmpty) place.neighborhood.trim(),
];

/// "120 m · Restaurante · Ponta Negra".
String nearbySubtitle(NearbyItem item) => [
  formatDistance(item.distanceMeters),
  ..._placeDetails(item.place),
].join(' · ');

/// O que o leitor de tela diz de um item: "Mangai, a 120 metros,
/// Restaurante, Ponta Negra, está no Quero ir, Ana foi aqui".
String nearbySemanticsLabel(NearbyItem item, {required bool saved}) => [
  item.place.name,
  spokenDistance(item.distanceMeters),
  ..._placeDetails(item.place),
  if (saved) 'está no Quero ir',
  ?item.friendsLabel,
  ?item.recurrence,
  if (item.price != null) priceChipSemantics(item.price!),
].join(', ');

/// Linha que explica a sugestão.
String suggestionReasonLabel(NearbySuggestion s) => switch (s.reason) {
  SuggestionReason.friend => s.item.friendsLabel!,
  SuggestionReason.saved => 'Está no seu Quero ir',
  SuggestionReason.nearest => 'O mais perto de você',
};

/// Aba "Perto" (F10).
class NearbyView extends StatefulWidget {
  const NearbyView({super.key, required this.viewModel});

  final NearbyViewModel viewModel;

  static const explainTitle = 'Para mostrar o que está perto de você';
  static const explainBody =
      'O NaÁrea usa sua localização só agora, para buscar os lugares em '
      'volta. Sua localização aproximada é usada para buscar lugares no '
      'OpenStreetMap (serviço Photon) e não fica guardada.';
  static const useLocationLabel = 'Usar minha localização';
  static const retryLabel = 'Tentar de novo';
  static const openSettingsLabel = 'Abrir configurações';
  static const deniedMessage =
      'Sem acesso à sua localização, não dá para mostrar o que está perto.';
  static const deniedForeverMessage =
      'O acesso à localização está bloqueado. Libere nas configurações do '
      'aparelho para ver o que está perto.';
  static const serviceOffMessage = 'Ative a localização do aparelho';
  static const locationErrorMessage =
      'Não foi possível descobrir onde você está.';
  static const loadErrorMessage = 'Não foi possível buscar lugares por perto';
  static const outOfAreaMessage = 'O NaÁrea funciona só no Brasil por enquanto';
  static const partialMessage =
      'Mostrando só lugares já conhecidos — não foi possível buscar todos agora';
  static const cappedMessage = 'Mostrando os 50 mais próximos';

  static String emptyMessage(NearbyRadius r) => 'Nada a ${r.label}';
  static String widenLabel(NearbyRadius r) => 'Ampliar para ${r.label}';

  @override
  State<NearbyView> createState() => _NearbyViewState();
}

class _NearbyViewState extends State<NearbyView> {
  bool? _active;

  NearbyViewModel get _vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _vm.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Seguir alguém em outra tela muda o "foi aqui": recarrega ao voltar.
    final active = ActiveTab.maybeOf(context);
    if (active == true && _active == false) _vm.reloadIfStale();
    _active = active;
  }

  void _open(Place place) {
    context.push(Routes.placeDetail(place.id), extra: place);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Perto',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            Text(
              'Onde comer agora, perto de você',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: _vm,
        builder: (context, _) => _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final vm = _vm;
    switch (vm.phase) {
      case NearbyPhase.checking:
        return const Center(child: CircularProgressIndicator());
      case NearbyPhase.explain:
        return _Message(
          key: const Key('nearby-explain'),
          icon: Icons.near_me,
          title: NearbyView.explainTitle,
          text: NearbyView.explainBody,
          actionLabel: NearbyView.useLocationLabel,
          onAction: vm.useMyLocation,
        );
      case NearbyPhase.denied:
        return _Message(
          icon: Icons.location_disabled,
          title: NearbyView.deniedMessage,
          actionLabel: NearbyView.retryLabel,
          onAction: vm.useMyLocation,
        );
      case NearbyPhase.deniedForever:
        return _Message(
          icon: Icons.location_disabled,
          title: NearbyView.deniedForeverMessage,
          actionLabel: NearbyView.openSettingsLabel,
          onAction: vm.openAppSettings,
          secondaryLabel: NearbyView.retryLabel,
          onSecondary: vm.useMyLocation,
        );
      case NearbyPhase.serviceOff:
        return _Message(
          icon: Icons.location_off,
          title: NearbyView.serviceOffMessage,
          actionLabel: NearbyView.retryLabel,
          onAction: vm.useMyLocation,
        );
      case NearbyPhase.locationError:
        return _Message(
          icon: Icons.location_searching,
          title: NearbyView.locationErrorMessage,
          actionLabel: NearbyView.retryLabel,
          onAction: vm.useMyLocation,
        );
      case NearbyPhase.locating:
      case NearbyPhase.loading:
      case NearbyPhase.ready:
      case NearbyPhase.loadError:
        return Column(
          children: [
            RadiusChips(viewModel: vm),
            Expanded(
              child: RefreshIndicator(
                onRefresh: vm.refresh,
                child: _results(context),
              ),
            ),
          ],
        );
    }
  }

  Widget _results(BuildContext context) {
    final vm = _vm;
    if (vm.phase == NearbyPhase.locating || vm.phase == NearbyPhase.loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    }
    if (vm.phase == NearbyPhase.loadError) {
      return _Message(
        icon: Icons.wifi_off,
        title: vm.rateLimited
            ? PhotonRateLimitedException.userMessage
            : NearbyView.loadErrorMessage,
        actionLabel: NearbyView.retryLabel,
        onAction: vm.retry,
      );
    }
    final items = vm.items;
    if (items.isEmpty && vm.partial) {
      // Sem a descoberta ao vivo e sem nada conhecido por perto: não dá para
      // dizer "nada a 300 m".
      return _Message(
        key: const Key('nearby-partial-empty'),
        icon: Icons.cloud_off,
        title: NearbyView.partialMessage,
        actionLabel: NearbyView.retryLabel,
        onAction: vm.retry,
      );
    }
    if (items.isEmpty) {
      if (vm.outOfArea) {
        return const _Message(
          icon: Icons.travel_explore,
          title: NearbyView.outOfAreaMessage,
        );
      }
      final wider = vm.radius.wider;
      return _Message(
        key: const Key('nearby-empty'),
        icon: Icons.search_off,
        title: NearbyView.emptyMessage(vm.radius),
        actionLabel: wider == null ? null : NearbyView.widenLabel(wider),
        onAction: wider == null ? null : () => vm.selectRadius(wider),
      );
    }
    final suggestion = vm.suggestion;
    final header = <Widget>[
      if (vm.partial) PartialNotice(onRetry: vm.retry),
      if (suggestion != null)
        SuggestionCard(
          suggestion: suggestion,
          onOpen: () => _open(suggestion.item.place),
        ),
    ];
    final footer = <Widget>[
      if (vm.capped)
        Padding(
          key: const Key('nearby-capped'),
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Text(
            NearbyView.cappedMessage,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      // Dados do OpenStreetMap na tela (Photon ou seed): crédito ODbL no fim.
      if (items.any((i) => i.place.hasOsmData))
        const OsmCredit(padding: EdgeInsets.only(top: 4)),
    ];
    return ListView.builder(
      key: const Key('nearby-list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: header.length + items.length + footer.length,
      itemBuilder: (context, i) {
        if (i < header.length) return header[i];
        if (i >= header.length + items.length) {
          return footer[i - header.length - items.length];
        }
        final item = items[i - header.length];
        return NearbyTile(
          key: ValueKey('nearby-${item.place.id}'),
          item: item,
          saved: vm.isSaved(item.place.id),
          onTap: () => _open(item.place),
        );
      },
    );
  }
}

/// Chips 300 m · 1 km · 3 km.
class RadiusChips extends StatelessWidget {
  const RadiusChips({super.key, required this.viewModel});

  final NearbyViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            for (final r in NearbyRadius.values) ...[
              if (r.index > 0) const SizedBox(width: 8),
              Semantics(
                label: 'Raio de ${r.label}',
                excludeSemantics: true,
                selected: viewModel.radius == r,
                button: true,
                onTap: () => viewModel.selectRadius(r),
                child: ChoiceChip(
                  key: Key('radius-${r.meters.round()}'),
                  label: Text(r.label),
                  selected: viewModel.radius == r,
                  onSelected: (_) => viewModel.selectRadius(r),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Card "Sugestão": decide pela pessoa, com "Ver lugar" a 1 toque.
class SuggestionCard extends StatelessWidget {
  const SuggestionCard({
    super.key,
    required this.suggestion,
    required this.onOpen,
  });

  final NearbySuggestion suggestion;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final item = suggestion.item;
    final place = item.place;
    final reason = suggestionReasonLabel(suggestion);
    return Card(
      key: const Key('nearby-suggestion'),
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 16),
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 72,
                height: 72,
                child: ExcludeSemantics(
                  child: PlacePhoto(place: place, iconSize: 28),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: MergeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sugestão',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.primary,
                      ),
                    ),
                    Text(
                      place.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    Semantics(
                      label: [
                        spokenDistance(item.distanceMeters),
                        ..._placeDetails(place),
                      ].join(', '),
                      excludeSemantics: true,
                      child: Text(
                        nearbySubtitle(item),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      reason,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('nearby-suggestion-open'),
              onPressed: onOpen,
              child: Semantics(
                label: 'Ver lugar: ${place.name}',
                excludeSemantics: true,
                child: const Text('Ver lugar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Item da lista: foto, nome, distância · categoria, "Ana foi aqui" e o
/// marcador "Quero ir".
class NearbyTile extends StatelessWidget {
  const NearbyTile({
    super.key,
    required this.item,
    required this.saved,
    this.onTap,
  });

  final NearbyItem item;
  final bool saved;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final place = item.place;
    final friends = item.friendsLabel;
    final recurrence = item.recurrence;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: nearbySemanticsLabel(item, saved: saved),
              hint: 'Abre o lugar',
              excludeSemantics: true,
              child: InkWell(
                onTap: onTap,
                child: Row(
                  children: [
                    SizedBox(
                      width: 80,
                      height: 80,
                      child: Hero(
                        tag: 'place-photo-${place.id}',
                        child: PlacePhoto(place: place, iconSize: 28),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              place.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium,
                            ),
                            Text(
                              nearbySubtitle(item),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.tertiary,
                              ),
                            ),
                            if (friends != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.people,
                                      size: 16,
                                      color: scheme.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        friends,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: scheme.primary,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            // F15: recorrência de um amigo ali.
                            if (recurrence != null)
                              Padding(
                                key: const Key('nearby-recurrence'),
                                padding: const EdgeInsets.only(top: 2),
                                child: RecurrenceLine(label: recurrence),
                              ),
                            // F27: preço relatado pelos amigos.
                            if (item.price != null)
                              Padding(
                                key: const Key('nearby-price'),
                                padding: const EdgeInsets.only(top: 2),
                                child: PriceChip(
                                  summary: item.price!,
                                  dense: true,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SaveButton(placeId: place.id),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    super.key,
    required this.icon,
    required this.title,
    this.text,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String? text;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: (constraints.maxHeight - 64).clamp(0, double.infinity),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 44,
                backgroundColor: scheme.primaryContainer,
                child: Icon(icon, size: 44, color: scheme.primary),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              if (text != null) ...[
                const SizedBox(height: 8),
                Text(
                  text!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 16),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
              if (secondaryLabel != null && onSecondary != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onSecondary,
                  child: Text(secondaryLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Aviso discreto: a descoberta ao vivo falhou e a lista tem só os lugares
/// já conhecidos (gravados).
class PartialNotice extends StatelessWidget {
  const PartialNotice({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: const Key('nearby-partial'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            Icons.cloud_off,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              NearbyView.partialMessage,
              style: theme.textTheme.bodySmall,
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text(NearbyView.retryLabel),
          ),
        ],
      ),
    );
  }
}
