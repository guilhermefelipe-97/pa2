import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:naarea/data/services/photo_picker.dart';

class _FakeImagePicker extends ImagePicker {
  PlatformException? error;
  XFile? file;
  final List<Map<String, Object?>> calls = [];
  LostDataResponse lost = LostDataResponse.empty();

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    calls.add({
      'source': source,
      'maxWidth': maxWidth,
      'maxHeight': maxHeight,
      'imageQuality': imageQuality,
      'requestFullMetadata': requestFullMetadata,
    });
    if (error != null) throw error!;
    return file;
  }

  @override
  Future<LostDataResponse> retrieveLostData() async => lost;
}

void main() {
  late _FakeImagePicker fake;
  late ImagePickerPhotoPicker picker;

  setUp(() {
    fake = _FakeImagePicker();
    picker = ImagePickerPhotoPicker(picker: fake, isAndroid: true);
  });

  test(
    'pede pré-redução 2160 px, qualidade 90 (HEIC → JPEG) e sem metadados',
    () async {
      fake.file = XFile.fromData(Uint8List.fromList([1, 2, 3]));
      expect(await picker.pick(PhotoSource.camera), [1, 2, 3]);
      expect(fake.calls.single, {
        'source': ImageSource.camera,
        'maxWidth': 2160.0,
        'maxHeight': 2160.0,
        'imageQuality': 90,
        'requestFullMetadata': false,
      });
    },
  );

  test('cancelar devolve null', () async {
    expect(await picker.pick(PhotoSource.gallery), isNull);
    expect(fake.calls.single['source'], ImageSource.gallery);
  });

  test('camera_access_denied → permissão negada da câmera', () async {
    fake.error = PlatformException(code: 'camera_access_denied');
    await expectLater(
      picker.pick(PhotoSource.camera),
      throwsA(
        isA<PhotoPermissionDeniedException>().having(
          (e) => e.source,
          'source',
          PhotoSource.camera,
        ),
      ),
    );
  });

  test('photo_access_denied → permissão negada das fotos', () async {
    fake.error = PlatformException(code: 'photo_access_denied');
    await expectLater(
      picker.pick(PhotoSource.gallery),
      throwsA(
        isA<PhotoPermissionDeniedException>().having(
          (e) => e.source,
          'source',
          PhotoSource.gallery,
        ),
      ),
    );
  });

  test('no_available_camera → PhotoUnavailableException', () async {
    fake.error = PlatformException(code: 'no_available_camera');
    await expectLater(
      picker.pick(PhotoSource.camera),
      throwsA(isA<PhotoUnavailableException>()),
    );
  });

  test('código desconhecido é relançado como está', () async {
    final unknown = PlatformException(code: 'already_active');
    fake.error = unknown;
    await expectLater(picker.pick(PhotoSource.camera), throwsA(same(unknown)));
  });

  group('retrieveLost (Android)', () {
    test('sem nada pendente: null', () async {
      expect(await picker.retrieveLost(), isNull);
    });

    test('foto pendente: bytes', () async {
      fake.lost = LostDataResponse(
        file: XFile.fromData(Uint8List.fromList([9])),
        type: RetrieveType.image,
      );
      expect(await picker.retrieveLost(), [9]);
    });

    test('erro pendente é mapeado', () async {
      fake.lost = LostDataResponse(
        exception: PlatformException(code: 'camera_access_denied'),
        type: RetrieveType.image,
      );
      await expectLater(
        picker.retrieveLost(),
        throwsA(isA<PhotoPermissionDeniedException>()),
      );
    });

    test('fora do Android não consulta', () async {
      final ios = ImagePickerPhotoPicker(picker: fake, isAndroid: false);
      fake.lost = LostDataResponse(
        file: XFile.fromData(Uint8List.fromList([9])),
        type: RetrieveType.image,
      );
      expect(await ios.retrieveLost(), isNull);
    });
  });
}
