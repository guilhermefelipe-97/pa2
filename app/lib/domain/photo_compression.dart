import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Lado maior máximo da foto enviada (px).
const int maxPhotoDimension = 1080;

/// Mesmo limite das Security Rules (`jpeg.size() <= 150000`).
const int maxPhotoBytes = 150000;

/// Qualidades JPEG tentadas, da melhor para a pior.
const List<int> photoQualitySteps = [85, 75, 65, 55, 45, 40];

/// Por que a foto não pôde ser usada.
enum PhotoCompressionFailure {
  /// Não é uma imagem que o app consegue ler (ou está corrompida).
  unsupportedFormat,

  /// Nem na pior qualidade coube em [maxPhotoBytes].
  tooLarge,
}

class PhotoCompressionException implements Exception {
  const PhotoCompressionException(this.failure);

  final PhotoCompressionFailure failure;

  @override
  String toString() => 'PhotoCompressionException(${failure.name})';
}

/// Recodifica a foto para envio: aplica a orientação do EXIF, reduz para no
/// máximo [maxPhotoDimension] px no lado maior, compõe transparência sobre
/// fundo branco e gera um JPEG **sem EXIF** (sem GPS, sem modelo da câmera),
/// baixando a qualidade 85 → 40 até caber em [maxPhotoBytes]. Nunca devolve o
/// arquivo original.
///
/// Função pura e síncrona (pesada): rodar com `compute` fora da UI.
Uint8List compressPhoto(Uint8List original) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(original);
  } on Object {
    decoded = null;
  }
  if (decoded == null) {
    throw const PhotoCompressionException(
      PhotoCompressionFailure.unsupportedFormat,
    );
  }
  // Foto de celular "deitada" com orientação no EXIF: gira os pixels antes de
  // jogar o EXIF fora.
  var image = img.bakeOrientation(decoded);
  final longest = image.width > image.height ? image.width : image.height;
  if (longest > maxPhotoDimension) {
    image = image.width >= image.height
        ? img.copyResize(
            image,
            width: maxPhotoDimension,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            image,
            height: maxPhotoDimension,
            interpolation: img.Interpolation.average,
          );
  }
  // JPEG não tem alpha: sem isto, o transparente vira preto.
  final paletteAlpha = image.hasPalette && image.palette!.numChannels == 4;
  if (image.hasAlpha || paletteAlpha) {
    final background = img.Image(width: image.width, height: image.height)
      ..clear(img.ColorRgb8(255, 255, 255));
    image = img.compositeImage(background, image);
  }
  // O encoder grava o EXIF que estiver na imagem: zera antes.
  image.exif = img.ExifData();
  for (final quality in photoQualitySteps) {
    final jpeg = img.encodeJpg(image, quality: quality);
    if (jpeg.length <= maxPhotoBytes) return jpeg;
  }
  throw const PhotoCompressionException(PhotoCompressionFailure.tooLarge);
}
