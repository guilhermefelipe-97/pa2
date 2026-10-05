import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../repositories/review_photo_repository.dart';
import 'firestore_review_repository.dart';

/// Fotos em `reviewPhotos/{reviewId}` (campo `jpeg`, bytes).
class FirestoreReviewPhotoRepository extends CachedReviewPhotoRepository {
  FirestoreReviewPhotoRepository(
    this._db, {
    super.authRepository,
    super.clock,
    super.maxCached,
    super.retryBackoff,
  });

  final FirebaseFirestore _db;

  @override
  Future<Uint8List?> fetch(String reviewId) async {
    final snap = await _db
        .collection(FirestoreReviewRepository.reviewPhotosCollection)
        .doc(reviewId)
        .get();
    final jpeg = snap.data()?['jpeg'];
    if (jpeg is Blob) return jpeg.bytes;
    if (jpeg is Uint8List) return jpeg;
    return null;
  }
}
