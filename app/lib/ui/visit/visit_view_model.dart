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

  PriceBand? get priceBand => _priceBand;

  bool _isCheckingLock = false;

  bool get isCheckingLock => _isCheckingLock;

  DateTime? _blockedSince;

  DateTime? get blockedSince => _blockedSince;

  bool get isBlocked => isOwnBusiness || _blockedSince != null;

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

  bool get canClose => !_isSubmitting;

  Timer? _releaseTimer;

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

  void toggleCompanion(Companion value) {
    if (_isSubmitting) return;
    _companion = _companion == value ? null : value;
    _errorMessage = null;
    notifyListeners();
  }

  void setPriceBand(PriceBand? value) {
    if (_isSubmitting || isBlocked || value == _priceBand) return;
    _priceBand = value;
    notifyListeners();
  }

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
