import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/open_report_repository.dart';
import '../../data/repositories/place_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/services/location_service.dart';
import '../../domain/models/place.dart';
import '../../domain/open_status.dart';
import '../core/safe_change_notifier.dart';

/// Onde o aparelho está em relação ao local (só em memória).
enum OpenProximity {
  /// Ainda não se sabe (lendo a permissão ou a posição).
  checking,

  /// Permissão ainda não concedida: convite "Está aí agora?" que explica e
  /// só então pede a permissão (nunca ao abrir o detalhe).
  needsPermission,

  /// A até [openReportRadiusMeters] do local: botões Sim/Não.
  near,

  /// Longe do local: sem relato (o status continua visível).
  far,

  /// Permissão negada ou GPS desligado: "Ative a localização para
  /// confirmar".
  locationOff,

  /// Não foi possível obter a posição (sem sinal, tempo esgotado).
  unavailable,

  /// Local sem coordenadas ou sem sessão: não há como relatar.
  none,
}

/// "Está aberto agora?" (F20) num local: o status a partir dos relatos das
/// últimas 3 h e o relato em 1 toque de quem está a até 150 m.
///
/// A posição do aparelho fica só em memória: serve para decidir se o botão
/// aparece e nunca é gravada nem enviada.
class OpenNowViewModel extends SafeChangeNotifier {
  OpenNowViewModel({
    required this.placeId,
    required OpenReportRepository openReportRepository,
    required AuthRepository authRepository,
    required UserRepository userRepository,
    LocationService? locationService,
    PlaceRepository? placeRepository,
    DateTime Function()? clock,
  }) : _reports = openReportRepository,
       _auth = authRepository,
       _users = userRepository,
       _location = locationService,
       _places = placeRepository,
       _clock = clock ?? DateTime.now;

  static const String question = 'Está aberto agora?';
  static const String askLocationLabel =
      'Está aí agora? Confirme se está aberto';
  static const String explainTitle = 'Confirmar se está aberto';
  static const String explainBody =
      'Para confirmar, o NaÁrea confere se você está a até 150 m daqui. '
      'Sua localização é usada só agora e não fica guardada.';
  static const String useLocationLabel = 'Usar minha localização';
  static const String notNowLabel = 'Agora não';
  static const String locationOffMessage = 'Ative a localização para confirmar';
  static const String unavailableMessage =
      'Não foi possível ver onde você está';
  static const String errorText = 'Não foi possível enviar';

  final String placeId;
  final OpenReportRepository _reports;
  final AuthRepository _auth;
  final UserRepository _users;
  final LocationService? _location;
  final PlaceRepository? _places;
  final DateTime Function() _clock;

  DateTime now() => _clock();

  String? get currentUserId => _auth.currentUserId;

  Place? _place;
  bool _started = false;

  List<OpenReport>? _loaded;

  /// Relato enviado daqui (aparece já, sem esperar a releitura).
  OpenReport? _own;

  /// Status atual; `null` sem relato recente ou com a leitura falhando
  /// (nunca derruba a tela).
  OpenStatus? get status {
    final loaded = _loaded;
    var own = _own;
    if (loaded == null && own == null) return null;
    // A releitura já trouxe o relato feito daqui (1 por autor a cada 30
    // min): não conta duas vezes.
    if (own != null &&
        (loaded ?? const []).any(
          (r) =>
              r.authorId == own!.authorId &&
              !r.createdAt.isBefore(own.createdAt.subtract(openReportCooldown)),
        )) {
      own = null;
    }
    return openStatusOf([...?loaded, ?own], now());
  }

  String? get statusLabel {
    final s = status;
    return s == null
        ? null
        : openStatusLabel(s, now(), currentUserId: currentUserId);
  }

  String? get statusSemantics {
    final s = status;
    return s == null
        ? null
        : openStatusSemantics(s, now(), currentUserId: currentUserId);
  }

  OpenProximity _proximity = OpenProximity.checking;
  OpenProximity get proximity => _proximity;

  DateTime? _lockLastAt;
  Timer? _unlockTimer;

  /// "Você informou às 20h10. De novo a partir das 20h40." enquanto dentro
  /// dos 30 min; `null` = pode relatar.
  String? get blockedLabel {
    final lastAt = _lockLastAt;
    return isOpenReportBlocked(lastAt, now())
        ? openReportBlockedMessage(lastAt!)
        : null;
  }

  bool _isSubmitting = false;
  bool get isSubmitting => _isSubmitting;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// Sim/Não habilitados.
  bool get canReport =>
      _proximity == OpenProximity.near &&
      blockedLabel == null &&
      !_isSubmitting &&
      _auth.currentUserId != null;

  /// O detalhe mostra o local [place] (pode chegar depois, com
  /// coordenadas). A 1ª chamada carrega relatos, trava e proximidade.
  void attach(Place place) {
    if (place.id != placeId) return;
    final hadCoordinates = _place?.hasCoordinates ?? false;
    _place = place;
    if (!_started) {
      _started = true;
      unawaited(load());
    } else if (!hadCoordinates && place.hasCoordinates) {
      unawaited(_checkProximity(request: false));
    }
  }

  int _seq = 0;

  /// Relatos, trava e proximidade em paralelo; nenhuma falha derruba a
  /// tela.
  Future<void> load() async {
    final seq = ++_seq;
    await Future.wait([
      _loadReports(seq),
      _loadLock(),
      _checkProximity(request: false),
    ]);
  }

  Future<void> _loadReports(int seq) async {
    if (_auth.currentUserId == null) return;
    try {
      final list = await _reports.fetchForPlace(
        placeId,
        since: openReportsSince(now()),
      );
      if (seq != _seq) return;
      _loaded = list;
    } on Object catch (e) {
      debugPrint('Relatos de aberto indisponíveis: $e');
      if (seq != _seq) return;
      // Status some (mas o relato feito daqui continua).
      _loaded = null;
    }
    notifyListeners();
  }

  int _lockSeq = 0;

  /// Erro ou mais de [openReportLockTimeout]: sem trava (as Rules decidem).
  Future<void> _loadLock() async {
    final uid = _auth.currentUserId;
    if (uid == null) return;
    final seq = ++_lockSeq;
    DateTime? lastAt;
    try {
      lastAt = await _reports
          .openReportLockOf(uid, placeId)
          .timeout(openReportLockTimeout);
    } on Object catch (e) {
      debugPrint('Trava de relato indisponível: $e');
      lastAt = null;
    }
    if (seq != _lockSeq) return;
    final own = _own?.createdAt;
    _setLock(
      own != null && (lastAt == null || own.isAfter(lastAt)) ? own : lastAt,
    );
    notifyListeners();
  }

  void _setLock(DateTime? lastAt) {
    _lockLastAt = lastAt;
    _unlockTimer?.cancel();
    _unlockTimer = null;
    if (lastAt == null || !isOpenReportBlocked(lastAt, now())) return;
    _unlockTimer = Timer(
      openReportAllowedAt(lastAt).difference(now()),
      notifyListeners,
    );
  }

  int _locSeq = 0;

  /// Sem [request], nunca mostra pedido do sistema: sem permissão, fica no
  /// convite [OpenProximity.needsPermission].
  Future<void> _checkProximity({required bool request}) async {
    final place = _place;
    final location = _location;
    if (place == null) return;
    if (!place.hasCoordinates ||
        location == null ||
        _auth.currentUserId == null) {
      _proximity = OpenProximity.none;
      notifyListeners();
      return;
    }
    final seq = ++_locSeq;
    if (!request) {
      bool granted;
      try {
        granted = await location.hasPermission();
      } on Object {
        granted = false;
      }
      if (seq != _locSeq) return;
      if (!granted) {
        _proximity = OpenProximity.needsPermission;
        notifyListeners();
        return;
      }
    }
    _proximity = OpenProximity.checking;
    notifyListeners();
    LocationResult result;
    try {
      result = await location.locate();
    } on Object {
      result = (status: LocationStatus.unavailable, position: null);
    }
    if (seq != _locSeq) return;
    final position = result.position;
    _proximity = switch (result.status) {
      LocationStatus.ok when position != null =>
        isNearForOpenReport(position, (lat: place.lat!, lng: place.lng!))
            ? OpenProximity.near
            : OpenProximity.far,
      LocationStatus.denied ||
      LocationStatus.deniedForever ||
      LocationStatus.serviceOff => OpenProximity.locationOff,
      _ => OpenProximity.unavailable,
    };
    notifyListeners();
  }

  /// Depois da explicação, no toque: pede a permissão (se preciso) e vê se
  /// o aparelho está perto.
  Future<void> useMyLocation() => _checkProximity(request: true);

  /// Relata "Sim" ([open] `true`) ou "Não". `true` quando foi gravado.
  Future<bool> submit({required bool open}) async {
    final place = _place;
    final uid = _auth.currentUserId;
    if (!canReport || place == null || uid == null) return false;
    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final profile = await _users.getProfile(uid);
      if (profile == null) throw StateError('perfil ausente');
      // Local só descoberto (Photon, G2): nasce no mesmo batch do relato.
      final newPlace = place.discovered ? place : null;
      final result = await _reports.createReport(
        NewOpenReport(
          authorId: uid,
          authorName: profile.displayName,
          placeId: placeId,
          open: open,
        ),
        newPlace: newPlace,
      );
      if (newPlace != null) {
        if (result.placeCreated) {
          _places?.markPersisted(newPlace);
        } else {
          _places?.invalidate(newPlace.id);
        }
      }
      final at = now();
      _own = OpenReport(
        id: 'local-${at.microsecondsSinceEpoch}',
        authorId: uid,
        authorName: profile.displayName,
        placeId: placeId,
        open: open,
        createdAt: at,
      );
      _lockSeq++;
      _setLock(at);
      return true;
    } on Object catch (e) {
      debugPrint('Relato de aberto não enviado: $e');
      // Ex.: relato feito em outro aparelho há menos de 30 min: reconsulta
      // a trava e explica, se for o caso.
      _isSubmitting = false;
      await _loadLock();
      if (blockedLabel == null) _errorMessage = errorText;
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _unlockTimer?.cancel();
    _seq++;
    _lockSeq++;
    _locSeq++;
    super.dispose();
  }
}
