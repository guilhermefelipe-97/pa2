import 'package:flutter/foundation.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/review_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/services/photo_picker.dart';
import '../../domain/models/companion.dart';
import '../../domain/models/place.dart';
import '../../domain/models/review.dart';
import '../../domain/models/scores.dart';
import '../../domain/photo_compression.dart';
import '../core/messages.dart';
import '../core/safe_change_notifier.dart';

/// Recodifica fora da UI (isolate; na web roda na mesma thread).
Future<Uint8List> compressPhotoInBackground(Uint8List bytes) =>
    compute(compressPhoto, bytes);

/// Avaliação em 3 eixos (F01), cada um opcional com mínimo de 1 (F14), com
/// contexto (F02), comentário e foto opcionais (G1).
class ReviewViewModel extends SafeChangeNotifier {
  ReviewViewModel({
    required this.place,
    required AuthRepository authRepository,
    required UserRepository userRepository,
    required ReviewRepository reviewRepository,
    required PhotoPicker photoPicker,
    required Future<Uint8List> Function(Uint8List original) compress,
    TargetPlatform? platform,
  }) : _auth = authRepository,
       _users = userRepository,
       _reviews = reviewRepository,
       _picker = photoPicker,
       _compress = compress,
       _platform = platform ?? defaultTargetPlatform;

  final Place place;
  final AuthRepository _auth;
  final UserRepository _users;
  final ReviewRepository _reviews;
  final PhotoPicker _picker;
  final Future<Uint8List> Function(Uint8List original) _compress;
  final TargetPlatform _platform;

  static const String saveError = saveFailureMessage;

  static const String photoUnusableMessage = 'Não foi possível usar essa foto';
  static const String photoUnsupportedMessage = 'Formato de foto não suportado';
  static const String noCameraMessage =
      'Este aparelho não tem câmera disponível';

  /// Acesso negado pelo sistema: explica como liberar, no caminho de
  /// configurações de cada plataforma.
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

  int? _food;
  int? _ambience;
  int? _service;
  Companion? _companion;
  String _comment = '';

  int? get food => _food;
  int? get ambience => _ambience;
  int? get service => _service;
  Companion? get companion => _companion;

  /// Texto como digitado (é aparado só no envio).
  String get comment => _comment;

  /// Acima de 280 unidades UTF-16 depois do trim (mesma conta das Rules).
  bool get commentTooLong => !Review.isCommentWithinLimit(_comment);

  Uint8List? _photo;

  /// JPEG já recodificado (≤ 1080 px, ≤ 150.000 bytes, sem EXIF) que vai
  /// junto com a avaliação; `null` = sem foto.
  Uint8List? get photo => _photo;

  bool _isPicking = false;

  /// Câmera ou galeria aberta (não abre um segundo seletor).
  bool get isPicking => _isPicking;

  bool _isProcessingPhoto = false;

  /// Recodificando a foto escolhida (Enviar fica desabilitado).
  bool get isProcessingPhoto => _isProcessingPhoto;

  String? _photoMessage;

  /// Aviso sobre a foto (não deu para usar, permissão negada).
  String? get photoMessage => _photoMessage;

  bool _isSubmitting = false;
  bool get isSubmitting => _isSubmitting;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// Avaliação mínima (F14): pelo menos um eixo; os outros, companhia,
  /// comentário e foto são opcionais.
  bool get hasValidAxes =>
      Scores.isValidCombination(_food, _ambience, _service);

  bool get canSubmit =>
      !_isSubmitting &&
      !_isPicking &&
      !_isProcessingPhoto &&
      hasValidAxes &&
      !commentTooLong;

  void setFood(int value) => _set(() => _food = _clamp(value));
  void setAmbience(int value) => _set(() => _ambience = _clamp(value));
  void setService(int value) => _set(() => _service = _clamp(value));

  /// "Limpar": o eixo volta a não avaliado (nunca zero).
  void clearFood() => _set(() => _food = null);
  void clearAmbience() => _set(() => _ambience = null);
  void clearService() => _set(() => _service = null);

  /// Tocar de novo na companhia selecionada desmarca.
  void toggleCompanion(Companion value) =>
      _set(() => _companion = _companion == value ? null : value);

  void setComment(String value) => _set(() => _comment = value);

  /// Abre a câmera ou a galeria. Cancelar não muda nada (nem a foto atual).
  /// A foto escolhida é sempre recodificada; se não der, avisa e segue com a
  /// foto que já havia (ou sem foto).
  /// Ocupado com a foto ou o envio: os botões de foto ficam desabilitados.
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

  /// Android: recupera a foto tirada antes de o sistema encerrar o app.
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

  /// Recodifica [original]. Se falhar, avisa e mantém a foto que já havia
  /// (ou segue sem foto).
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

  /// Retorna `true` quando a avaliação foi gravada.
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
      final profile = await _users.getProfile(uid);
      if (profile == null) throw StateError('perfil ausente');
      await _reviews.createReview(
        NewReview(
          authorId: uid,
          authorName: profile.displayName,
          placeId: place.id,
          placeName: place.name,
          scores: Scores(food: _food, ambience: _ambience, service: _service),
          companion: _companion,
          comment: _comment, // NewReview normaliza: trim, vazio → null
        ),
        photo: _photo,
      );
      return true;
    } on Object {
      // Inclui permission-denied das Rules.
      _errorMessage = saveError;
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }
}
