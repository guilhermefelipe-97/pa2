import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/place_repository.dart';
import '../../data/repositories/sponsorship_repository.dart';
import '../../routing/routes.dart';
import '../../domain/models/place.dart';
import '../../domain/geo.dart';
import '../core/app_clock.dart';
import '../core/app_shell.dart';
import '../core/save_button.dart';
import '../feed/widgets/place_photo.dart';
import '../saved/saved_places_store.dart';

class SponsoredView extends StatelessWidget {
  const SponsoredView({super.key});
  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthRepository>().currentUserId;
    return Scaffold(
      appBar: AppBar(title: const Text('Patrocinado')),
      body: uid == null ? const SizedBox.shrink() : _Slots(key: ValueKey(uid)),
    );
  }
}

/// Destaques separados da descoberta orgânica, sem reservar espaço vazio.
class SponsoredSection extends StatelessWidget {
  const SponsoredSection({super.key, this.position});
  final LatLng? position;

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthRepository?>()?.currentUserId;
    final repository = context.watch<SponsorshipRepository?>();
    if (uid == null || repository == null) return const SizedBox.shrink();
    return _Slots(key: ValueKey(uid), embedded: true, position: position);
  }
}

class _Slots extends StatefulWidget {
  const _Slots({super.key, this.embedded = false, this.position});
  final bool embedded;
  final LatLng? position;
  @override
  State<_Slots> createState() => _SlotsState();
}

class _SlotsState extends State<_Slots> {
  List<SponsoredSlot>? slots;
  Map<String, Place> places = {};
  bool failed = false;
  Timer? timer, refreshTimer;
  Future<void>? _read;
  bool _active = false;
  DateTime now() => context.read<AppClock?>()?.now() ?? DateTime.now();
  @override
  void initState() {
    super.initState();
    if (!widget.embedded) _resume();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.embedded) return;
    final active = ActiveTab.maybeOf(context) ?? true;
    if (active == _active) return;
    if (active) {
      _resume();
    } else {
      _active = false;
      timer?.cancel();
      refreshTimer?.cancel();
    }
  }

  void _resume() {
    _active = true;
    load();
    timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> load() {
    if (_read != null) return _read!;
    refreshTimer?.cancel();
    final run = _load();
    _read = run;
    return run.whenComplete(() {
      _read = null;
      if (mounted && _active) {
        refreshTimer = Timer(const Duration(seconds: 15), load);
      }
    });
  }

  Future<void> _load() async {
    final repository = context.read<SponsorshipRepository>();
    final placesRepository = context.read<PlaceRepository>();
    final at = now();
    try {
      final data = await (() async {
        final result = await repository.current(at);
        final places = await placesRepository.getPlaces(
          result.map((s) => s.placeId),
        );
        return (slots: result, places: places);
      })().timeout(const Duration(seconds: 20));
      if (mounted) {
        setState(() {
          slots = data.slots;
          places = data.places;
          failed = false;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          slots = null;
          failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = slots?.where((s) => s.active(now())).toList();
    if (widget.embedded) {
      if (active == null || active.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Destaque da semana',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Patrocinado',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  Tooltip(
                    message:
                        'Os destaques não seguem o raio escolhido nem o filtro Aberto agora.',
                    child: const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.info_outline, size: 16),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            for (final slot in active.take(3))
              SponsoredCard(
                key: ValueKey('sponsored-slot-${slot.id}'),
                slot: slot,
                name: places[slot.placeId]?.name ?? 'Estabelecimento',
                place: places[slot.placeId],
                position: widget.position,
                showDisclosure: false,
              ),
            if (active.length > 3)
              TextButton(
                onPressed: () => context.push('/patrocinado'),
                child: const Text('Ver todos os destaques'),
              ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Patrocinado · espaço separado dos amigos'),
        if (failed)
          TextButton(
            onPressed: load,
            child: const Text('Não foi possível carregar. Tentar novamente'),
          ),
        if (slots == null && !failed)
          const Center(child: CircularProgressIndicator()),
        if (active?.isEmpty == true) const Text('Nenhum destaque disponível.'),
        for (final slot in active ?? <SponsoredSlot>[])
          SponsoredCard(
            key: ValueKey('sponsored-slot-${slot.id}'),
            slot: slot,
            name: places[slot.placeId]?.name ?? 'Estabelecimento',
            place: places[slot.placeId],
          ),
      ],
    );
  }
}

class SponsoredCard extends StatelessWidget {
  const SponsoredCard({
    super.key,
    required this.slot,
    required this.name,
    this.place,
    this.position,
    this.showDisclosure = true,
  });
  final SponsoredSlot slot;
  final String name;
  final Place? place;
  final LatLng? position;
  final bool showDisclosure;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = place;
    final here = position;
    final distance = p != null && p.hasCoordinates && here != null
        ? formatDistance(distanceMeters(here, (lat: p.lat!, lng: p.lng!)))
        : null;
    void open() => context.push(Routes.placeDetail(slot.placeId), extra: p);
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: open,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height:
                              MediaQuery.sizeOf(context).width.clamp(0, 360) *
                              1 /
                              2,
                          child: PlacePhoto(
                            place:
                                p ??
                                Place(
                                  id: slot.placeId,
                                  name: name,
                                  category: '',
                                  neighborhood: '',
                                  city: '',
                                ),
                          ),
                        ),
                        if (distance != null)
                          Positioned(
                            top: 10,
                            left: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Text(
                                '↗ $distance',
                                style: theme.textTheme.labelMedium,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(name, style: theme.textTheme.titleMedium),
                  if (p != null)
                    Text(
                      [
                        p.category,
                        p.neighborhood,
                      ].where((v) => v.trim().isNotEmpty).join(' • '),
                      style: theme.textTheme.bodySmall,
                    ),
                  if (showDisclosure)
                    Text('Patrocinado', style: theme.textTheme.labelSmall),
                ],
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 4,
              children: [
                if (p != null &&
                    p.inCatalog &&
                    context.watch<SavedPlacesStore?>() != null)
                  SaveButton(
                    placeId: slot.placeId,
                    showLabel: true,
                    prominent: true,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
