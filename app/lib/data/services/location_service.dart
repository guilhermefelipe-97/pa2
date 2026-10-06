import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../../domain/geo.dart';

/// Resultado de pedir a posição atual.
enum LocationStatus {
  /// Posição obtida.
  ok,

  /// A pessoa negou (dá para pedir de novo).
  denied,

  /// Negado para sempre: só nas configurações do aparelho.
  deniedForever,

  /// Serviço de localização (GPS) desligado no aparelho.
  serviceOff,

  /// Outro erro (tempo esgotado, sem sinal, navegador sem suporte...).
  unavailable,
}

/// [position] só existe com [LocationStatus.ok].
typedef LocationResult = ({LocationStatus status, LatLng? position});

/// Posição do aparelho para o "Perto" (F10). A posição vive só em memória:
/// nada aqui grava ou envia coordenadas.
abstract class LocationService {
  /// A permissão já foi concedida (não mostra nenhum pedido do sistema).
  Future<bool> hasPermission();

  /// Pede a permissão se preciso (pedido do sistema) e devolve a posição
  /// atual, ou o motivo de não ter conseguido.
  Future<LocationResult> locate();

  /// Abre as configurações do app (permissão negada para sempre).
  Future<bool> openAppSettings();

  /// Abre as configurações de localização do aparelho (GPS desligado).
  Future<bool> openLocationSettings();
}

/// [LocationService] sobre o `geolocator` (Android, iOS e web).
class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService({
    this.timeLimit = const Duration(seconds: 15),
  });

  /// Quanto esperar por uma posição antes de desistir.
  final Duration timeLimit;

  static bool _granted(LocationPermission p) =>
      p == LocationPermission.whileInUse || p == LocationPermission.always;

  @override
  Future<bool> hasPermission() async {
    try {
      return _granted(await Geolocator.checkPermission());
    } on Object {
      // Ex.: navegador sem a Permissions API: trata como não concedida (a
      // tela explica antes de pedir).
      return false;
    }
  }

  @override
  Future<LocationResult> locate() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (!_granted(permission) &&
          permission != LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return (status: LocationStatus.deniedForever, position: null);
      }
      if (!_granted(permission)) {
        return (status: LocationStatus.denied, position: null);
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        return (status: LocationStatus.serviceOff, position: null);
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeLimit,
        ),
      );
      return (
        status: LocationStatus.ok,
        position: (lat: p.latitude, lng: p.longitude),
      );
    } on LocationServiceDisabledException {
      return (status: LocationStatus.serviceOff, position: null);
    } on PermissionDeniedException {
      return (status: LocationStatus.denied, position: null);
    } on Object {
      return (status: LocationStatus.unavailable, position: null);
    }
  }

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
}
