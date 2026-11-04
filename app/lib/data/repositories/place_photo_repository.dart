import 'dart:typed_data';

const maxPlacePhotosPerUpload = 6;
const placeGalleryPageSize = 20;

class PlaceGalleryPhoto {
  const PlaceGalleryPhoto({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.createdAt,
    required this.jpeg,
  });
  final String id, authorId, authorName;
  final DateTime createdAt;
  final Uint8List jpeg;
}

class PlaceGalleryPage {
  const PlaceGalleryPage(this.photos, {this.cursor});
  final List<PlaceGalleryPhoto> photos;
  final String? cursor;
}

abstract class PlacePhotoRepository {
  Future<PlaceGalleryPage> list(String placeId, {String? after});
  Future<void> add(
    String placeId, {
    required String authorId,
    required String authorName,
    required List<Uint8List> photos,
  });
  Future<void> remove(String placeId, String photoId);
}
