import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import '../repositories/place_photo_repository.dart';

abstract class PlacePhotoPicker {
  Future<List<Uint8List>> pickMany();
}

class ImagePickerPlacePhotoPicker implements PlacePhotoPicker {
  final _picker = ImagePicker();
  @override
  Future<List<Uint8List>> pickMany() async {
    final files = await _picker.pickMultiImage(
      maxWidth: 2160,
      maxHeight: 2160,
      imageQuality: 90,
      requestFullMetadata: false,
      limit: maxPlacePhotosPerUpload,
    );
    return Future.wait(
      files.take(maxPlacePhotosPerUpload).map((f) => f.readAsBytes()),
    );
  }
}
