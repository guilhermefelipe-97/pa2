import 'package:flutter/foundation.dart';
import '../../data/repositories/privacy_repository.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/owner_repository.dart';
import '../../data/repositories/place_repository.dart';
import '../../data/repositories/review_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/services/photo_picker.dart';
import '../../domain/models/companion.dart';
import '../../domain/price_band.dart';
import '../../domain/food_tags.dart';
import '../../domain/models/place.dart';
import '../../domain/models/review.dart';
import '../../domain/models/scores.dart';
import '../../domain/photo_compression.dart';
import '../../domain/review_lock.dart';
import '../core/messages.dart';
import '../core/safe_change_notifier.dart';

Future<Uint8List> compressPhotoInBackground(Uint8List bytes) =>
    compute(compressPhoto, bytes);

class ReviewViewModel extends SafeChangeNotifier {
  ReviewViewModel({
    required this.place,
    required AuthRepository authRepository,
    required UserRepository userRepository,
    required ReviewRepository reviewRepository,
    required PhotoPicker photoPicker,
    required Future<Uint8List> Function(Uint8List original) compress,
    PlaceRepository? placeRepository,
    TargetPlatform? platform,
    this.ownerRepository,
    this.privacyRepository,
    DateTime Function()? clock,
  }) : _initialUid = authRepository.currentUserId,
       _auth = authRepository,
       _clock = clock ?? DateTime.now,
       _places = placeRepository,
       _users = userRepository,
       _reviews = reviewRepository,
       _picker = photoPicker,
       _compress = compress,
       _platform = platform ?? defaultTargetPlatform;

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
  final ReviewRepository _reviews;
  final PhotoPicker _picker;
  final Future<Uint8List> Function(Uint8List original) _compress;
  final PlaceRepository? _places;
  final TargetPlatform _platform;
  final DateTime Function() _clock;

  static const String saveError = saveFailureMessage;

  static const String photoUnusableMessage = 'Não foi possível usar essa foto';
  static const String photoUnsupportedMessage = 'Formato de foto não suportado';
  static const String noCameraMessage =
      'Este aparelho não tem câmera disponível';

  static String permissionDeniedMessage(
    PhotoSource source,
    TargetPlatform platform,
  ) {
    final what = source == PhotoSource.camera ? 'à câmera' : 'às suas fotos';
    final allow = source == PhotoSource.camera ? 'a câmera' : 'fotos';
    if (kIsWeb) {
      return 'Sem acesso $what. Libere o acesso nas configurações do '
          'navegador para este site.';
    }
    return switch (platform) {
      TargetPlatform.iOS =>
        'Sem acesso $what. Para liberar, abra Ajustes › NaÁrea e permita '
            '$allow.',
      _ =>
        'Sem acesso $what. Para liberar, abra Configurações › Apps › '
            'NaÁrea › Permissões e permita $allow.',
    };
  }

  bool _isCheckingLock = false;

  bool get isCheckingLock => _isCheckingLock;

  DateTime? _blockedSince;

  DateTime? get blockedSince => _blockedSince;

  bool get isBlocked => isOwnBusiness || _blockedSince != null;

  String? get blockedMessage {
    if (isOwnBusiness) return ownerContributionMessage;
    final since = _blockedSince;
    return since == null ? null : reviewBlockedMessage(since);
  }

  Future<void> checkLock({bool showProgress = true}) async {
    final uid = _auth.currentUserId;
    if (uid == null || _isCheckingLock) return;
    _isCheckingLock = showProgress;
    if (showProgress) notifyListeners();
    try {
      await _loadPrivacy(uid);
      if (_auth.currentUserId != uid || isDisposed) return;
      await _checkOwner(uid, place.id);
      final lastAt = await _reviews
          .reviewLockOf(uid, place.id)
          .timeout(reviewLockTimeout);
      if (_auth.currentUserId != uid || isDisposed) return;
      _blockedSince = isReviewBlocked(lastAt, _clock()) ? lastAt : null;
    } on Object catch (e) {
      debugPrint('Trava de avaliação indisponível: $e');
    } finally {
      _isCheckingLock = false;
      notifyListeners();
    }
  }

  final Set<String> tags = {};
  void toggleTag(String tag) {
    if (_isSubmitting || !foodTags.contains(tag)) return;
    if (!tags.add(tag)) tags.remove(tag);
    notifyListeners();
  }

  int? _food;
  int? _ambience;
  int? _service;
  Companion? _companion;
  String _comment = '';

  int? get food => _food;
  int? get ambience => _ambience;
  int? get service => _service;
  Companion? get companion => _companion;

  PriceBand? _priceBand;

  PriceBand? get priceBand => _priceBand;

  String get comment => _comment;

  bool get commentTooLong => !Review.isCommentWithinLimit(_comment);

  Uint8List? _photo;

  Uint8List? get photo => _photo;

  bool _isPicking = false;

  bool get isPicking => _isPicking;

  bool _isProcessingPhoto = false;

  bool get isProcessingPhoto => _isProcessingPhoto;

  String? _photoMessage;

  String? get photoMessage => _photoMessage;

  bool _isSubmitting = false;
  bool get isSubmitting => _isSubmitting;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool get hasValidAxes =>
      Scores.isValidCombination(_food, _ambience, _service);

  bool get canSubmit =>
      _auth.currentUserId == _initialUid &&
      !privacyUnavailable &&
      !_isCheckingLock &&
      !isBlocked &&
      !_isSubmitting &&
      !_isPicking &&
      !_isProcessingPhoto &&
      hasValidAxes &&
      !commentTooLong;

  void setFood(int value) => _set(() => _food = _clamp(value));
  void setAmbience(int value) => _set(() => _ambience = _clamp(value));
  void setService(int value) => _set(() => _service = _clamp(value));

  void clearFood() => _set(() => _food = null);
  void clearAmbience() => _set(() => _ambience = null);
  void clearService() => _set(() => _service = null);

  void toggleCompanion(Companion value) =>
      _set(() => _companion = _companion == value ? null : value);

  void setComment(String value) => _set(() => _comment = value);

  void setPriceBand(PriceBand? value) {
    if (_isSubmitting || value == _priceBand) return;
    _priceBand = value;
    notifyListeners();
  }

  bool get photoBusy => _isSubmitting || _isPicking || _isProcessingPhoto;

  Future<void> pickPhoto(PhotoSource source) async {
    if (photoBusy) return;
    _isPicking = true;
    notifyListeners();
    final Uint8List? original;
    try {
      original = await _picker.pick(source);
    } on Object catch (e, st) {
      _isPicking = false;
      _photoMessage = _pickerErrorMessage(e, st);
      notifyListeners();
      return;
    }
    _isPicking = false;
    if (original == null) {
      notifyListeners();
      return;
    }
    await _usePhoto(original);
  }

  Future<void> recoverLostPhoto() async {
    if (photoBusy) return;
    final Uint8List? original;
    try {
      original = await _picker.retrieveLost();
    } on Object catch (e, st) {
      _photoMessage = _pickerErrorMessage(e, st);
      notifyListeners();
      return;
    }
    if (original != null) await _usePhoto(original);
  }

  String _pickerErrorMessage(Object e, StackTrace st) {
    switch (e) {
      case PhotoPermissionDeniedException(:final source):
        return permissionDeniedMessage(source, _platform);
      case PhotoUnavailableException():
        return noCameraMessage;
    }
    debugPrint('Seletor de foto falhou: $e');
    debugPrintStack(stackTrace: st);
    return photoUnusableMessage;
  }

  Future<void> _usePhoto(Uint8List original) async {
    _isProcessingPhoto = true;
    _photoMessage = null;
    notifyListeners();
    try {
      final jpeg = await _compress(original);
      if (jpeg.isEmpty || jpeg.length > maxPhotoBytes) {
        throw const PhotoCompressionException(PhotoCompressionFailure.tooLarge);
      }
      _photo = jpeg;
    } on PhotoCompressionException catch (e) {
      _photoMessage = e.failure == PhotoCompressionFailure.unsupportedFormat
          ? photoUnsupportedMessage
          : photoUnusableMessage;
    } on Object catch (e, st) {
      debugPrint('Compressão da foto falhou: $e');
      debugPrintStack(stackTrace: st);
      _photoMessage = photoUnusableMessage;
    } finally {
      _isProcessingPhoto = false;
      notifyListeners();
    }
  }

  void removePhoto() {
    if (photoBusy) return;
    _photo = null;
    _photoMessage = null;
    notifyListeners();
  }

  int? _clamp(int v) => Scores.isValid(v) ? v : null;

  void _set(void Function() change) {
    change();
    _errorMessage = null;
    notifyListeners();
  }

  Future<bool> submit() async {
    if (!canSubmit) return false;
    final uid = _auth.currentUserId;
    if (uid == null) {
      _errorMessage = saveError;
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
      final result = await _reviews.createReview(
        NewReview(
          silent: silent,
          authorId: uid,
          authorName: profile.displayName,
          placeId: place.id,
          placeName: place.name,
          scores: Scores(food: _food, ambience: _ambience, service: _service),
          companion: _companion,
          comment: _comment,
          priceBand: _priceBand,
          tags: tags.toList(),
        ),
        photo: _photo,
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
      await checkLock(showProgress: false);
      if (!isBlocked) _errorMessage = saveError;
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }
}
