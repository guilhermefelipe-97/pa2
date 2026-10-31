import 'dart:async';

import 'package:flutter/foundation.dart';
import '../../data/repositories/privacy_repository.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/owner_repository.dart';
import '../../data/repositories/place_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/repositories/visit_repository.dart';
import '../../domain/models/companion.dart';
import '../../domain/models/place.dart';
import '../../domain/models/visit.dart';
import '../../domain/price_band.dart';
import '../../domain/visit_lock.dart';
import '../core/safe_change_notifier.dart';

/// "Voltei aqui" (F15): registra uma ida ao local sem notas, com companhia
/// opcional; o período do dia vem do horário do servidor (F02). No máximo
/// uma visita a cada [visitCooldown] por local (garantido pelas Rules; aqui
/// só explica antes de enviar).
class VisitViewModel extends SafeChangeNotifier {
  VisitViewModel({
    required this.place,
    required AuthRepository authRepository,
    required UserRepository userRepository,
    required VisitRepository visitRepository,
    PlaceRepository? placeRepository,
    this.ownerRepository,
    this.privacyRepository,
    DateTime Function()? clock,
  }) : _initialUid = authRepository.currentUserId,
       _auth = authRepository,
       _users = userRepository,
       _visits = visitRepository,
       _places = placeRepository,
       _clock = clock ?? DateTime.now;

  static const String successMessage = 'Visita registrada';
  static const String errorText = 'Não foi possível registrar';

  final PrivacyRepository? privacyRepository;
  bool silent = false;
  bool _privacyLoaded = false;
  bool get privacyUnavailable => privacyRepository != null && !_privacyLoaded;
  void setSilent(bool value) {
    if (!isSubmitting) {
      silent = value;
      _privacyLoaded = true;
      notifyListeners();
    }
  }

  Future<void> _loadPrivacy(String uid) async {
    if (_privacyLoaded) return;
    final value =
        await privacyRepository
            ?.silentDefault(uid)
            .timeout(const Duration(seconds: 10)) ??
        false;
    if (_auth.currentUserId != uid || isDisposed || _privacyLoaded) return;
    silent = value;
    _privacyLoaded = true;
  }

  final Place place;
  final String? _initialUid;
  final AuthRepository _auth;
  final OwnerRepository? ownerRepository;
  bool isOwnBusiness = false;
  Future<void> _checkOwner(String uid, String id) async {
    final owner = ownerRepository == null
        ? null
        : await ownerRepository!.ownerOf(id).timeout(ownerLookupTimeout);
    if (_auth.currentUserId == uid) isOwnBusiness = owner == uid;
  }

  final UserRepository _users;
  final VisitRepository _visits;
  final PlaceRepository? _places;
  final DateTime Function() _clock;

  Companion? _companion;
  Companion? get companion => _companion;

  PriceBand? _priceBand;

  /// Gasto por pessoa (F27); opcional, nunca bloqueia o envio.
  PriceBand? get priceBand => _priceBand;

  bool _isCheckingLock = false;

  /// Consultando a trava (o Confirmar fica desabilitado).
  bool get isCheckingLock => _isCheckingLock;

  DateTime? _blockedSince;

  /// Hora da última visita, enquanto dentro do intervalo; `null` = pode.
  DateTime? get blockedSince => _blockedSince;

  bool get isBlocked => isOwnBusiness || _blockedSince != null;

  /// "Você registrou uma visita às 13h. De novo a partir das 01h."
  String? get blockedMessage {
    if (isOwnBusiness) return ownerContributionMessage;
    final since = _blockedSince;
    return since == null ? null : visitBlockedMessage(since);
  }

  bool _isSubmitting = false;
  bool get isSubmitting => _isSubmitting;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool get canSubmit =>
      _auth.currentUserId == _initialUid &&
      !privacyUnavailable &&
      !_isCheckingLock &&
      !isBlocked &&
      !_isSubmitting;

  /// O sheet pode fechar (toque fora, arrastar, voltar)? Não durante o
  /// envio.
  bool get canClose => !_isSubmitting;

  Timer? _releaseTimer;

  /// Bloqueado: na hora da liberação o Confirmar volta sozinho (o sheet pode
  /// ficar aberto até lá).
  void _setBlocked(DateTime? lastAt) {
    _releaseTimer?.cancel();
    _releaseTimer = null;
    final now = _clock();
    _blockedSince = isVisitBlocked(lastAt, now) ? lastAt : null;
    if (_blockedSince == null) return;
    _releaseTimer = Timer(visitAllowedAt(lastAt!).difference(now), () {
      _blockedSince = null;
      notifyListeners();
    });
  }

  /// Tocar de novo na companhia selecionada desmarca.
  void toggleCompanion(Companion value) {
    if (_isSubmitting) return;
    _companion = _companion == value ? null : value;
    _errorMessage = null;
    notifyListeners();
  }

  /// Faixa escolhida (F27); `null` limpa. Ignorada durante o envio e com
  /// a visita bloqueada (12 h). Não mexe na mensagem de erro.
  void setPriceBand(PriceBand? value) {
    if (_isSubmitting || isBlocked || value == _priceBand) return;
    _priceBand = value;
    notifyListeners();
  }

  /// Consulta a trava antes de liberar o Confirmar. Erro ou mais de
  /// [visitLockTimeout]: segue sem trava e as Rules decidem no envio.
  Future<void> checkLock() async {
    final uid = _auth.currentUserId;
    if (uid == null || _isCheckingLock) return;
    _isCheckingLock = true;
    notifyListeners();
    try {
      await _loadPrivacy(uid);
      if (_auth.currentUserId != uid || isDisposed) return;
      await _checkOwner(uid, place.id);
      final lastAt = await _visits
          .visitLockOf(uid, place.id)
          .timeout(visitLockTimeout);
      if (_auth.currentUserId != uid || isDisposed) return;
      _setBlocked(lastAt);
    } on Object catch (e) {
      debugPrint('Trava de visita indisponível: $e');
    } finally {
      _isCheckingLock = false;
      notifyListeners();
    }
  }

  /// `true` quando a visita foi gravada.
  Future<bool> submit() async {
    if (!canSubmit) return false;
    final uid = _auth.currentUserId;
    if (uid == null) {
      _errorMessage = errorText;
      notifyListeners();
      return false;
    }
    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _checkOwner(uid, place.id);
      if (isOwnBusiness) {
        _errorMessage = ownerContributionMessage;
        return false;
      }
      if (_auth.currentUserId != uid || isDisposed) return false;
      final profile = await _users
          .getProfile(uid)
          .timeout(const Duration(seconds: 10));
      if (profile == null) throw StateError('perfil ausente');
      if (_auth.currentUserId != uid || isDisposed) return false;
      // Local só descoberto (Photon, G2): nasce no mesmo batch da visita.
      final newPlace = place.discovered ? place : null;
      final result = await _visits.createVisit(
        NewVisit(
          silent: silent,
          authorId: uid,
          authorName: profile.displayName,
          placeId: place.id,
          placeName: place.name,
          companion: _companion,
          priceBand: _priceBand,
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
      return _auth.currentUserId == uid && !isDisposed;
    } on Object {
      // Inclui permission-denied das Rules (ex.: visita registrada em outro
      // aparelho há menos de 12 h): reconsulta e explica, se for o caso.
      _isSubmitting = false;
      await checkLock();
      if (!isBlocked) _errorMessage = errorText;
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _releaseTimer?.cancel();
    super.dispose();
  }
}
