import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../data/repositories/place_repository.dart';
import '../../data/services/location_service.dart';
import '../../routing/routes.dart';

class PlaceLocationChip extends StatefulWidget {
  const PlaceLocationChip({super.key, this.shortLabel = false});
  final bool shortLabel;

  @override
  State<PlaceLocationChip> createState() => _PlaceLocationChipState();
}

class _PlaceLocationChipState extends State<PlaceLocationChip> {
  late final Future<String> label = _load();

  Future<String> _load() async {
    final location = context.read<LocationService?>();
    final places = context.read<PlaceRepository?>();
    if (location == null || places == null) return 'Localização';
    final position = await location.lastKnownPositionIfGranted();
    if (position == null) return 'Localização';
    try {
      final nearby = await places.nearby(position.lat, position.lng, 300);
      final named =
          nearby.places
              .where((item) => item.place.neighborhood.trim().isNotEmpty)
              .toList()
            ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
      if (named.isNotEmpty) return 'Perto de ${named.first.place.neighborhood}';
    } on Object {
      // O GPS pode funcionar quando a consulta de lugares está indisponível.
    }
    return 'GPS ativo';
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: label,
    builder: (context, snapshot) => ActionChip(
      tooltip: 'Ver onde estou no GPS',
      avatar: const Icon(Icons.near_me_outlined, size: 16),
      label: Text(
        widget.shortLabel
            ? (snapshot.data ?? 'Localização').replaceFirst('Perto de ', '')
            : snapshot.data ?? 'Localização',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onPressed: () => context.go(Routes.nearby),
    ),
  );
}
