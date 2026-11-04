import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/photo_compression.dart';
import '../repositories/place_photo_repository.dart';

class FirestorePlacePhotoRepository implements PlacePhotoRepository {
  FirestorePlacePhotoRepository(this.db);
  final FirebaseFirestore db;
  CollectionReference<Map<String, dynamic>> _photos(String id) =>
      db.collection('places').doc(id).collection('photos');

  @override
  Future<PlaceGalleryPage> list(String placeId, {String? after}) async {
    Query<Map<String, dynamic>> query = _photos(placeId)
        .orderBy('createdAt', descending: true)
        .orderBy(FieldPath.documentId, descending: true);
    if (after != null) {
      final previous = await _photos(placeId).doc(after).get();
      if (previous.exists) query = query.startAfterDocument(previous);
    }
    final result = await query.limit(placeGalleryPageSize + 1).get();
    final visible = result.docs.take(placeGalleryPageSize).toList();
    return PlaceGalleryPage(
      [
        for (final doc in visible)
          if (doc.data()['jpeg'] is Blob &&
              doc.data()['createdAt'] is Timestamp)
            PlaceGalleryPhoto(
              id: doc.id,
              authorId: doc.data()['authorId'] as String,
              authorName: doc.data()['authorName'] as String,
              createdAt: (doc.data()['createdAt'] as Timestamp).toDate(),
              jpeg: (doc.data()['jpeg'] as Blob).bytes,
            ),
      ],
      cursor: result.docs.length > placeGalleryPageSize
          ? visible.last.id
          : null,
    );
  }

  @override
  Future<void> add(
    String placeId, {
    required String authorId,
    required String authorName,
    required List<Uint8List> photos,
  }) async {
    if (photos.isEmpty ||
        photos.length > maxPlacePhotosPerUpload ||
        photos.any(
          (p) =>
              p.isEmpty ||
              p.length > maxPhotoBytes ||
              p.length < 4 ||
              p[0] != 0xff ||
              p[1] != 0xd8,
        )) {
      throw ArgumentError('Selecione de 1 a 6 fotos JPEG de até 150 KB.');
    }
    final batch = db.batch();
    for (final jpeg in photos) {
      batch.set(_photos(placeId).doc(), {
        'authorId': authorId,
        'authorName': authorName,
        'createdAt': FieldValue.serverTimestamp(),
        'jpeg': Blob(jpeg),
      });
    }
    await batch.commit();
  }

  @override
  Future<void> remove(String placeId, String photoId) =>
      _photos(placeId).doc(photoId).delete();
}
