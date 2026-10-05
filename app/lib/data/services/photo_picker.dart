import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// De onde vem a foto da avaliação.
enum PhotoSource { camera, gallery }

/// O sistema negou acesso à câmera ou às fotos.
class PhotoPermissionDeniedException implements Exception {
  const PhotoPermissionDeniedException(this.source);

  final PhotoSource source;

  @override
  String toString() => 'PhotoPermissionDeniedException(${source.name})';
}

/// O aparelho não tem câmera disponível.
class PhotoUnavailableException implements Exception {
  const PhotoUnavailableException();

  @override
  String toString() => 'PhotoUnavailableException';
}

/// Abre a câmera ou a galeria e devolve os bytes do arquivo escolhido (ainda
/// não recodificado), ou `null` se a pessoa cancelou.
abstract class PhotoPicker {
  Future<Uint8List?> pick(PhotoSource source);

  /// Android: o sistema pode encerrar o app enquanto a câmera está aberta; a
  /// foto tirada fica pendente e é recuperada aqui ao voltar para a tela.
  /// `null` quando não há nada pendente (e sempre fora do Android).
  Future<Uint8List?> retrieveLost();
}

/// `image_picker` (Android, iOS e web).
class ImagePickerPhotoPicker implements PhotoPicker {
  ImagePickerPhotoPicker({ImagePicker? picker, bool? isAndroid})
    : _picker = picker ?? ImagePicker(),
      _isAndroid =
          isAndroid ??
          (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  final ImagePicker _picker;
  final bool _isAndroid;

  /// Pré-redução feita pela plataforma (rápida, nativa) só para não decodificar
  /// uma foto de 50 MP em Dart; a recodificação final (≤ 1080 px, sem EXIF) é
  /// sempre do app.
  static const double prescaleMax = 2160;

  /// Com qualidade definida a plataforma recodifica, o que também converte
  /// HEIC (iPhone) em JPEG, formato que o app consegue ler.
  static const int prescaleQuality = 90;

  @override
  Future<Uint8List?> pick(PhotoSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source == PhotoSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        maxWidth: prescaleMax,
        maxHeight: prescaleMax,
        imageQuality: prescaleQuality,
        requestFullMetadata: false,
      );
      if (file == null) return null;
      return await file.readAsBytes();
    } on PlatformException catch (e) {
      final mapped = mapError(e, source);
      if (identical(mapped, e)) rethrow;
      throw mapped;
    }
  }

  @override
  Future<Uint8List?> retrieveLost() async {
    if (!_isAndroid) return null;
    final response = await _picker.retrieveLostData();
    if (response.isEmpty) return null;
    final error = response.exception;
    if (error != null) throw mapError(error, PhotoSource.camera);
    final file = response.file;
    return file == null ? null : await file.readAsBytes();
  }

  /// Traduz os códigos do `image_picker`; desconhecidos voltam como estão.
  @visibleForTesting
  static Object mapError(PlatformException e, PhotoSource source) {
    switch (e.code) {
      case 'camera_access_denied':
        return const PhotoPermissionDeniedException(PhotoSource.camera);
      case 'photo_access_denied':
        return const PhotoPermissionDeniedException(PhotoSource.gallery);
      case 'no_available_camera':
        return const PhotoUnavailableException();
    }
    return e;
  }
}
