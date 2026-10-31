import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/place_repository.dart';
import '../../data/repositories/sponsorship_repository.dart';
import '../../routing/routes.dart';
import '../core/app_clock.dart';

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

class _Slots extends StatefulWidget {
  const _Slots({super.key});
  @override
  State<_Slots> createState() => _SlotsState();
}

class _SlotsState extends State<_Slots> {
  List<SponsoredSlot>? slots;
  Map<String, String> names = {};
  bool failed = false;
  Timer? timer, refreshTimer;
  Future<void>? _read;
  DateTime now() => context.read<AppClock?>()?.now() ?? DateTime.now();
  @override
  void initState() {
    super.initState();
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
      if (mounted) refreshTimer = Timer(const Duration(seconds: 15), load);
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
