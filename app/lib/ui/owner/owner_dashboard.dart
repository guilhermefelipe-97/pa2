import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/owner_repository.dart';
import '../../data/repositories/owner_workspace_repository.dart';
import '../../data/repositories/place_repository.dart';
import '../../domain/models/place.dart';
import '../../routing/routes.dart';
import '../core/editorial.dart';
import '../feed/widgets/place_photo.dart';
import '../place/place_gallery.dart';
import 'place_presentation_view.dart';
import '../../data/sponsorship_floor_reader.dart';
import '../../domain/models/scores.dart';
import '../../domain/sponsorship_floor.dart';
import '../core/app_clock.dart';

class OwnerView extends StatefulWidget {
  const OwnerView({super.key});
  @override
  State<OwnerView> createState() => _OwnerViewState();
}

class _OwnerRow {
  const _OwnerRow(
    this.request,
    this.place,
    this.owned,
    this.failed,
    this.summary,
  );
  final OwnershipRequest request;
  final Place? place;
  final bool owned, failed;
  final OwnerPlaceSummary? summary;
  String get name => place?.name ?? 'Estabelecimento';
  String get status => failed
      ? 'Não foi possível verificar titularidade'
      : owned
      ? 'Titularidade verificada'
      : switch (request.status) {
          'pending' => 'Pedido pendente — sem poderes até a aprovação',
          'approved' || 'revoked' => 'Titularidade revogada',
          _ => 'Pedido rejeitado',
        };
}

class _OwnerViewState extends State<OwnerView> {
  Future<List<_OwnerRow>>? read;
  String? uid;
  int generation = 0;
  Future<List<_OwnerRow>> load(String id) async {
    final owners = context.read<OwnerRepository>();
    final places = context.read<PlaceRepository>();
    final workspace = context.read<OwnerWorkspaceRepository?>();
    final requests = await owners.requestsOf(id);
    final found = await places.getPlaces(requests.map((r) => r.placeId));
    return Future.wait(
      requests.map((request) async {
        bool owned = false, failed = false;
        OwnerPlaceSummary? summary;
        try {
          owned =
              await owners
                  .ownerOf(request.placeId)
                  .timeout(ownerLookupTimeout) ==
              id;
        } on Object {
          failed = true;
        }
        if (owned && workspace != null) {
          try {
            summary = await workspace.summary(request.placeId);
          } on Object {}
        }
        return _OwnerRow(
          request,
          found[request.placeId],
          owned,
          failed,
          summary,
        );
      }),
    );
  }

  void refresh() => setState(() {
    generation++;
    read = uid == null ? Future.value([]) : load(uid!);
  });
  Future<void> edit(_OwnerRow row) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PlacePresentationView(placeId: row.request.placeId),
      ),
    );
    if (mounted) refresh();
  }

  Future<void> follow(_OwnerRow row) => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (sheet) => SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Acompanhar solicitação',
            style: Theme.of(sheet).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          Text(row.name, style: Theme.of(sheet).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(row.status),
          if (row.request.reason != null) ...[
            const SizedBox(height: 12),
            Text(
              '${row.request.status == 'revoked' ? 'Motivo da aprovação original' : 'Motivo'}: ${row.request.reason}',
            ),
          ],
          if (row.request.status == 'revoked' &&
              row.request.revocationReason != null) ...[
            const SizedBox(height: 12),
            Text('Motivo da revogação: ${row.request.revocationReason}'),
          ],
          const SizedBox(height: 16),
          const Text(
            'A decisão da administração aparece aqui. Atualize o painel para consultar o status mais recente.',
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                Navigator.of(sheet).pop();
                refresh();
              },
              child: const Text('Atualizar status'),
            ),
          ),
        ],
      ),
    ),
  );
  void promotion(List<_OwnerRow> active) => showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Divulgação'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'A contratação de divulgação está indisponível no momento.',
            ),
            const SizedBox(height: 12),
            Text(
              'Regra do Destaque: ele só aparece com pelo menos '
              '${SponsorshipFloor.minReviews} avaliações nos últimos 90 dias '
              'e média de ${formatAverage(SponsorshipFloor.floor)} ou mais. '
              'Abaixo disso é suspenso automaticamente e volta sozinho quando '
              'as avaliações melhorarem.',
            ),
            if (context.read<SponsorshipFloorReader?>() != null)
              for (final row in active)
                _FloorLine(
                  key: ValueKey('floor-${row.request.placeId}'),
                  name: row.name,
                  placeId: row.request.placeId,
                ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthRepository>();
    if (uid != auth.currentUserId || read == null) {
      uid = auth.currentUserId;
      generation++;
      read = uid == null ? Future.value([]) : load(uid!);
    }
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('Meus estabelecimentos', maxLines: 1),
        ),
        titleTextStyle: theme.textTheme.titleMedium,
        actions: [
          IconButton(
            tooltip: 'Atualizar titularidade',
            onPressed: refresh,
            icon: const Icon(Icons.refresh, size: 20),
          ),
        ],
      ),
      body: FutureBuilder<List<_OwnerRow>>(
        key: ValueKey('$uid-$generation'),
        future: read,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: TextButton(
                onPressed: refresh,
                child: const Text('Tentar novamente'),
              ),
            );
          }
          if (!snapshot.hasData) return const EditorialLoading();
          final rows = snapshot.data!;
          final active = rows.where((r) => r.owned).toList();
          final complete = active.every((r) => r.summary != null);
          final pending = active.fold(
            0,
            (sum, r) => sum + (r.summary?.unanswered ?? 0),
          );
          return RefreshIndicator(
            onRefresh: () async {
              refresh();
              await read;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                if (active.isNotEmpty)
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.rate_review_outlined,
                            color: theme.colorScheme.secondary,
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  complete
                                      ? (pending == 0
                                            ? 'Respostas em dia'
                                            : '$pending ${pending == 1 ? 'avaliação pendente' : 'avaliações pendentes'}')
                                      : 'Avaliações da comunidade',
                                  style: theme.textTheme.titleSmall,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  complete
                                      ? (pending == 0
                                            ? 'Todas as avaliações receberam resposta.'
                                            : 'Aguardando uma resposta do estabelecimento.')
                                      : 'Abra Responder para consultar as avaliações. As contagens estão indisponíveis.',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Locais vinculados',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    Text(
                      '${rows.length} ${rows.length == 1 ? 'local' : 'locais'}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (rows.isEmpty) ...[
                  const SizedBox(height: 20),
                  const Icon(Icons.storefront_outlined, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Seu estabelecimento começa aqui',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Encontre seu local e solicite a titularidade na ficha. Após a aprovação, você poderá editar a apresentação e responder avaliações.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                ],
                for (final row in rows)
                  row.owned ? activeCard(row) : requestCard(row),
                OutlinedButton.icon(
                  onPressed: () => context.go(Routes.nearby),
                  icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(14),
                  ),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Cadastrar ou reivindicar novo local',
                      maxLines: 1,
                    ),
                  ),
                ),
                if (active.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Card(
                    color: theme.colorScheme.surfaceContainerLow,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Destacar no bairro',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Divulgação patrocinada. A contratação ainda está indisponível.',
                          ),
                          TextButton.icon(
                            onPressed: () => promotion(active),
                            icon: const Icon(Icons.campaign_outlined, size: 18),
                            label: const Text('Divulgação'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget activeCard(_OwnerRow row) {
    final theme = Theme.of(context);
    final place =
        row.place ??
        Place(
          id: row.request.placeId,
          name: row.name,
          category: '',
          neighborhood: '',
          city: '',
          inCatalog: false,
        );
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => context.push(Routes.placeDetail(place.id)),
            child: SizedBox(
              height: MediaQuery.textScalerOf(context).scale(128),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  IgnorePointer(
                    child: PlaceGallery(
                      place: place,
                      reviews: const [],
                      currentUserId: uid,
                      coverOnly: true,
                    ),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x18000000), Color(0xCC000000)],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: InkWell(
                        onTap: () => follow(row),
                        child: Tooltip(
                          message: 'Acompanhar solicitação',
                          child: Text(
                            '● Ativo',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onTertiaryContainer,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 14,
                    right: 74,
                    bottom: 14,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          place.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          [
                            place.neighborhood,
                            place.category,
                          ].where((s) => s.isNotEmpty).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (row.summary?.rating != null)
                    Positioned(
                      bottom: 40,
                      right: 12,
                      child: Tooltip(
                        message: 'Média de todas as notas da comunidade',
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '★ ${row.summary!.rating!.toStringAsFixed(1)}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: FilledButton.icon(
                    onPressed: () async {
                      await context.push(
                        '/meus-estabelecimentos/${Uri.encodeComponent(place.id)}/avaliacoes',
                      );
                      if (mounted) refresh();
                    },
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.reply_outlined, size: 16),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        row.summary == null
                            ? 'Responder'
                            : 'Responder (${row.summary!.unanswered})',
                        maxLines: 1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  key: ValueKey('timeline-${place.id}'),
                  tooltip: 'Painel do local',
                  onPressed: () => context.push(
                    Routes.ownerTimeline(place.id),
                    extra: place.name,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.surfaceContainer,
                    foregroundColor: theme.colorScheme.onSurface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                  icon: const Icon(Icons.insights_outlined, size: 18),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: FilledButton.tonalIcon(
                    onPressed: row.place == null ? null : () => edit(row),
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.surfaceContainer,
                      foregroundColor: theme.colorScheme.onSurface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Editar', maxLines: 1),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget requestCard(_OwnerRow row) {
    final theme = Theme.of(context);
    final compact =
        MediaQuery.sizeOf(context).width >= 370 &&
        MediaQuery.textScalerOf(context).scale(1) <= 1.3 &&
        !row.failed;
    final followButton = IconButton.filledTonal(
      tooltip: 'Acompanhar pedido',
      onPressed: () => follow(row),
      style: IconButton.styleFrom(
        backgroundColor: theme.colorScheme.surfaceContainer,
        foregroundColor: theme.colorScheme.onSurface,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      icon: const Icon(Icons.chevron_right, size: 22),
    );
    final status = Text(
      row.request.status == 'pending' && !row.failed
          ? 'Em análise'
          : row.status,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.secondary,
      ),
    );
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: row.place?.photoUrl == null
                      ? const Icon(Icons.storefront_outlined)
                      : PlacePhoto(place: row.place!),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      if (row.place?.neighborhood.isNotEmpty == true)
                        Text(
                          row.place!.neighborhood,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      if (compact) status,
                    ],
                  ),
                ),
                if (compact) ...[const SizedBox(width: 8), followButton],
              ],
            ),
            if (!compact) ...[
              const SizedBox(height: 12),
              status,
              const SizedBox(height: 6),
              Align(alignment: Alignment.centerRight, child: followButton),
            ],
          ],
        ),
      ),
    );
  }
}

class _FloorLine extends StatefulWidget {
  const _FloorLine({super.key, required this.name, required this.placeId});
  final String name, placeId;
  @override
  State<_FloorLine> createState() => _FloorLineState();
}

class _FloorLineState extends State<_FloorLine> {
  late final Future<FloorCheck> read;
  @override
  void initState() {
    super.initState();
    final now = context.read<AppClock?>()?.now() ?? DateTime.now();
    read = context.read<SponsorshipFloorReader>().check(widget.placeId, now);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: FutureBuilder<FloorCheck>(
      future: read,
      builder: (context, snap) {
        final text = snap.hasError
            ? 'Não foi possível consultar as avaliações agora.'
            : snap.hasData
            ? SponsorshipFloor.describe(snap.data!)
            : 'Consultando avaliações…';
        return Text('${widget.name}: $text');
      },
    ),
  );
}
