import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:naarea/data/services/location_service.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakeGeolocator extends GeolocatorPlatform
    with MockPlatformInterfaceMixin {
  LocationPermission permission = LocationPermission.denied;

  /// O que o pedido do sistema devolve.
  LocationPermission afterRequest = LocationPermission.whileInUse;
  bool serviceOn = true;
  Object? positionError;
  bool checkThrows = false;
  int requests = 0;
  int positions = 0;

  @override
  Future<LocationPermission> checkPermission() async {
    if (checkThrows) throw UnsupportedError('Permissions API');
    return permission;
  }

  @override
  Future<LocationPermission> requestPermission() async {
    requests++;
    return permission = afterRequest;
  }

  @override
  Future<bool> isLocationServiceEnabled() async => serviceOn;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    positions++;
    if (positionError != null) throw positionError!;
    return Position(
      latitude: -5.8817,
      longitude: -35.1708,
      timestamp: DateTime.utc(2026, 10, 5),
      accuracy: 10,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }
}

void main() {
  late _FakeGeolocator platform;
  const service = GeolocatorLocationService();

  setUp(() {
    platform = _FakeGeolocator();
    GeolocatorPlatform.instance = platform;
  });

  test('primeira vez: pede a permissão e devolve a posição', () async {
    expect(await service.hasPermission(), isFalse);
    final r = await service.locate();
    expect(platform.requests, 1);
    expect(r.status, LocationStatus.ok);
    expect(r.position, (lat: -5.8817, lng: -35.1708));
  });

  test('já concedida: não pede de novo', () async {
    platform.permission = LocationPermission.whileInUse;
    expect(await service.hasPermission(), isTrue);
    final r = await service.locate();
    expect(platform.requests, 0);
    expect(r.status, LocationStatus.ok);
  });

  test('negada no pedido do sistema', () async {
    platform.afterRequest = LocationPermission.denied;
    final r = await service.locate();
    expect(r.status, LocationStatus.denied);
    expect(r.position, isNull);
    expect(platform.positions, 0);
  });

  test('negada para sempre: nem mostra o pedido', () async {
    platform.permission = LocationPermission.deniedForever;
    final r = await service.locate();
    expect(r.status, LocationStatus.deniedForever);
    expect(platform.requests, 0);
  });

  test('negada para sempre no pedido', () async {
    platform.afterRequest = LocationPermission.deniedForever;
    expect((await service.locate()).status, LocationStatus.deniedForever);
  });

  test('GPS desligado', () async {
    platform.serviceOn = false;
    expect((await service.locate()).status, LocationStatus.serviceOff);
    expect(platform.positions, 0);
  });

  test('GPS desligado durante a leitura', () async {
    platform.positionError = const LocationServiceDisabledException();
    expect((await service.locate()).status, LocationStatus.serviceOff);
  });

  test('tempo esgotado ou outro erro: indisponível', () async {
    platform.positionError = Exception('timeout');
    expect((await service.locate()).status, LocationStatus.unavailable);
  });

  test('navegador sem Permissions API: hasPermission é false', () async {
    platform.checkThrows = true;
    expect(await service.hasPermission(), isFalse);
  });
}
