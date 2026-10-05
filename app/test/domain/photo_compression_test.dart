import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:naarea/domain/photo_compression.dart';

/// Foto sintética "de câmera": gradiente com ruído leve (comprime como foto
/// real) e EXIF com GPS, câmera e orientação.
Uint8List cameraLikeJpeg({
  int width = 2400,
  int height = 1800,
  int? orientation,
  int noise = 24,
}) {
  final rnd = Random(42);
  final image = img.Image(width: width, height: height);
  for (final p in image) {
    final n = noise == 0 ? 0 : rnd.nextInt(noise);
    p
      ..r = (p.x * 255 ~/ width + n).clamp(0, 255)
      ..g = (p.y * 255 ~/ height + n).clamp(0, 255)
      ..b = (128 + n).clamp(0, 255);
  }
  image.exif.imageIfd['Make'] = img.IfdValueAscii('CameraFake');
  image.exif.imageIfd['Model'] = img.IfdValueAscii('Modelo X');
  if (orientation != null) image.exif.imageIfd.orientation = orientation;
  image.exif.gpsIfd['GPSLatitudeRef'] = img.IfdValueAscii('S');
  image.exif.gpsIfd['GPSLatitude'] = img.IfdValueRational(5, 1);
  image.exif.gpsIfd['GPSLongitudeRef'] = img.IfdValueAscii('W');
  return img.encodeJpg(image, quality: 98);
}

bool containsAscii(Uint8List bytes, String needle) {
  final n = needle.codeUnits;
  outer:
  for (var i = 0; i <= bytes.length - n.length; i++) {
    for (var j = 0; j < n.length; j++) {
      if (bytes[i + j] != n[j]) continue outer;
    }
    return true;
  }
  return false;
}

void main() {
  test('foto sintética de entrada é grande e tem EXIF com GPS', () {
    final original = cameraLikeJpeg();
    expect(original.length, greaterThan(maxPhotoBytes));
    expect(containsAscii(original, 'Exif'), isTrue);
    expect(img.decodeJpg(original)!.exif.gpsIfd.isEmpty, isFalse);
  });

  test('2400×1800 com EXIF: ≤1080 px, ≤150.000 bytes, JPEG sem EXIF', () {
    final out = compressPhoto(cameraLikeJpeg());
    expect(out.length, lessThanOrEqualTo(maxPhotoBytes));
    // JPEG (SOI) e sem segmento APP1/Exif nem resto de metadados.
    expect(out.sublist(0, 2), [0xFF, 0xD8]);
    expect(containsAscii(out, 'Exif'), isFalse);
    expect(containsAscii(out, 'CameraFake'), isFalse);
    final decoded = img.decodeJpg(out)!;
    expect(decoded.width, 1080);
    expect(decoded.height, 810);
    expect(decoded.exif.isEmpty, isTrue);
  });

  test('retrato (1500×2000): o lado maior vira 1080', () {
    final out = compressPhoto(cameraLikeJpeg(width: 1500, height: 2000));
    final decoded = img.decodeJpg(out)!;
    expect(decoded.height, 1080);
    expect(decoded.width, 810);
  });

  test(
    'orientação do EXIF é aplicada aos pixels antes de descartar o EXIF',
    () {
      // Orientação 6 = girar 90°: 1600×1200 "deitada" vira retrato.
      final out = compressPhoto(
        cameraLikeJpeg(width: 1600, height: 1200, orientation: 6),
      );
      final decoded = img.decodeJpg(out)!;
      expect(decoded.width, 810);
      expect(decoded.height, 1080);
      expect(decoded.exif.isEmpty, isTrue);
    },
  );

  test('foto pequena não é ampliada, mas é recodificada sem EXIF', () {
    final original = cameraLikeJpeg(width: 400, height: 300);
    final out = compressPhoto(original);
    final decoded = img.decodeJpg(out)!;
    expect(decoded.width, 400);
    expect(decoded.height, 300);
    expect(containsAscii(out, 'Exif'), isFalse);
  });

  test('PNG transparente: alpha composto sobre fundo branco', () {
    final transparent = img.Image(width: 40, height: 30, numChannels: 4)
      ..clear(img.ColorRgba8(0, 0, 0, 0));
    // Metade direita opaca e vermelha.
    for (final p in transparent) {
      if (p.x >= 20) {
        p
          ..r = 255
          ..g = 0
          ..b = 0
          ..a = 255;
      }
    }
    final out = compressPhoto(img.encodePng(transparent));
    final decoded = img.decodeJpg(out)!;
    final left = decoded.getPixel(5, 15);
    expect(left.r, greaterThan(240));
    expect(left.g, greaterThan(240));
    expect(left.b, greaterThan(240));
    final right = decoded.getPixel(35, 15);
    expect(right.r, greaterThan(200));
    expect(right.g, lessThan(60));
  });

  test('PNG também é aceito (vira JPEG)', () {
    final png = img.encodePng(img.Image(width: 50, height: 40));
    final out = compressPhoto(png);
    expect(out.sublist(0, 2), [0xFF, 0xD8]);
  });

  test('ruído puro que não cabe nem na qualidade 40: erro', () {
    final rnd = Random(1);
    final image = img.Image(width: 1080, height: 1080);
    for (final p in image) {
      p
        ..r = rnd.nextInt(256)
        ..g = rnd.nextInt(256)
        ..b = rnd.nextInt(256);
    }
    expect(
      () => compressPhoto(img.encodeJpg(image, quality: 100)),
      throwsA(
        isA<PhotoCompressionException>().having(
          (e) => e.failure,
          'failure',
          PhotoCompressionFailure.tooLarge,
        ),
      ),
    );
  });

  test('bytes que não são imagem: formato não suportado', () {
    final unsupported = throwsA(
      isA<PhotoCompressionException>().having(
        (e) => e.failure,
        'failure',
        PhotoCompressionFailure.unsupportedFormat,
      ),
    );
    expect(
      () => compressPhoto(Uint8List.fromList(List.filled(100, 7))),
      unsupported,
    );
    expect(() => compressPhoto(Uint8List(0)), unsupported);
  });
}
