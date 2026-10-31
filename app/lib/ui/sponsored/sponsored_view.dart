import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/place_repository.dart';
import '../../data/repositories/sponsorship_repository.dart';
import '../../routing/routes.dart';
import '../core/app_clock.dart';
import '../core/app_shell.dart';

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
  const SponsoredSection({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthRepository?>()?.currentUserId;
    final repository = context.watch<SponsorshipRepository?>();
    if (uid == null || repository == null) return const SizedBox.shrink();
    return _Slots(key: ValueKey(uid), embedded: true);
  }
}

class _Slots extends StatefulWidget {
  const _Slots({super.key, this.embedded = false});
  final bool embedded;
  @override
  State<_Slots> createState() => _SlotsState();
}

class _SlotsState extends State<_Slots> {
  List<SponsoredSlot>? slots;
  Map<String, String> names = {};
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
        return (
          slots: result,
          names: {for (final p in places.values) p.id: p.name},
        );
      })().timeout(const Duration(seconds: 20));
      if (mounted) {
        setState(() {
          slots = data.slots;
          names = data.names;
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
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Patrocinado',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Text(
              'Os destaques não seguem o raio escolhido nem o filtro Aberto agora.',
            ),
            for (final slot in active.take(3))
              SponsoredCard(
                slot: slot,
                name: names[slot.placeId] ?? 'Estabelecimento',
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
            slot: slot,
            name: names[slot.placeId] ?? 'Estabelecimento',
          ),
      ],
    );
  }
}

class SponsoredCard extends StatelessWidget {
  const SponsoredCard({super.key, required this.slot, required this.name});
  final SponsoredSlot slot;
  final String name;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      title: Text(name),
      subtitle: const Text('Patrocinado'),
      onTap: () => context.push(Routes.placeDetail(slot.placeId)),
    ),
  );
}
