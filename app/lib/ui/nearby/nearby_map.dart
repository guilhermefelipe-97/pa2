import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as maps;

import '../../domain/geo.dart';
import '../../domain/models/place.dart';
import '../core/osm_credit.dart';
import 'nearby_view_model.dart';

class NearbyMap extends StatefulWidget {
  const NearbyMap({
    super.key,
    required this.position,
    required this.items,
    required this.radius,
    required this.onOpen,
    required this.onShowList,
  });
  final LatLng position;
  final List<NearbyItem> items;
  final double radius;
  final ValueChanged<Place> onOpen;
  final VoidCallback onShowList;
  @override
  State<NearbyMap> createState() => _NearbyMapState();
}

class _NearbyMapState extends State<NearbyMap> {
  final _controller = MapController();
  bool _failed = false;
  maps.LatLng get _center =>
      maps.LatLng(widget.position.lat, widget.position.lng);
  double get _zoom => widget.radius <= 300
      ? 16
      : widget.radius <= 1000
      ? 14.5
      : widget.radius <= 3000
      ? 13
      : widget.radius <= 5000
      ? 12
      : 11;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                key: const Key('nearby-map'),
                mapController: _controller,
                options: MapOptions(
                  initialCenter: _center,
                  initialZoom: _zoom,
                  minZoom: 3,
                  maxZoom: 19,
                  backgroundColor: scheme.surfaceContainerLow,
                ),
                children: [
                  TileLayer(
                    urlTemplate: const String.fromEnvironment(
                      'MAP_TILE_URL',
                      defaultValue:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    ),
                    userAgentPackageName:
                        'NaArea/1.3 (https://github.com/guilhermefelipe-97/pa2)',
                    maxNativeZoom: 19,
                    errorTileCallback: (_, _, _) {
                      if (_failed) return;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && !_failed) setState(() => _failed = true);
                      });
                    },
                  ),
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: _center,
                        radius: widget.radius,
                        useRadiusInMeter: true,
                        color: scheme.primary.withValues(alpha: .08),
                        borderColor: scheme.primary.withValues(alpha: .4),
                        borderStrokeWidth: 1,
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _center,
                        width: 24,
                        height: 24,
                        child: Tooltip(
                          message: 'Sua localização',
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: scheme.primary,
                              border: Border.all(color: Colors.white, width: 3),
                            ),
                          ),
                        ),
                      ),
                      for (final item in widget.items)
                        if (item.place.hasCoordinates)
                          Marker(
                            point: maps.LatLng(
                              item.place.lat!,
                              item.place.lng!,
                            ),
                            width: 48,
                            height: 48,
                            child: IconButton.filled(
                              key: ValueKey('map-place-${item.place.id}'),
                              tooltip:
                                  '${item.place.name} • ${formatDistance(item.distanceMeters)}',
                              onPressed: () => widget.onOpen(item.place),
                              icon: const Icon(Icons.location_on_outlined),
                            ),
                          ),
                    ],
                  ),
                ],
              ),
              if (_failed)
                Positioned(
                  top: 8,
                  left: 8,
                  right: 8,
                  child: Material(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text('Não foi possível carregar o mapa.'),
                          TextButton(
                            onPressed: widget.onShowList,
                            child: const Text('Ver lista'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Positioned(
                bottom: 12,
                right: 12,
                child: Column(
                  children: [
                    IconButton.filledTonal(
                      tooltip: 'Aproximar mapa',
                      onPressed: () => _controller.move(
                        _controller.camera.center,
                        (_controller.camera.zoom + 1).clamp(3, 19),
                      ),
                      icon: const Icon(Icons.add),
                    ),
                    const SizedBox(height: 4),
                    IconButton.filledTonal(
                      tooltip: 'Afastar mapa',
                      onPressed: () => _controller.move(
                        _controller.camera.center,
                        (_controller.camera.zoom - 1).clamp(3, 19),
                      ),
                      icon: const Icon(Icons.remove),
                    ),
                    const SizedBox(height: 4),
                    IconButton.filled(
                      tooltip: 'Centralizar na minha localização',
                      onPressed: () => _controller.move(_center, _zoom),
                      icon: const Icon(Icons.my_location),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        ColoredBox(
          color: scheme.surface,
          child: const SizedBox(
            width: double.infinity,
            child: Padding(padding: EdgeInsets.all(8), child: OsmCredit()),
          ),
        ),
      ],
    );
  }
}
