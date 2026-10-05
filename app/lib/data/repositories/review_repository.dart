import 'dart:typed_data';

import '../../domain/models/review.dart';

abstract class ReviewRepository {
  /// Limite do operador `whereIn` do Firestore.
  static const int whereInLimit = 30;

  /// Grava a avaliação. Com [photo] (JPEG já recodificado, ≤ 150.000 bytes),
  /// grava `reviews/{id}` com `hasPhoto: true` e `reviewPhotos/{id}` num único
  /// batch: ou as duas, ou nenhuma.
  Future<void> createReview(NewReview review, {Uint8List? photo});

  /// Avaliações dos [authorIds], mais recentes primeiro.
  Future<List<Review>> fetchReviewsByAuthors(List<String> authorIds);

  /// Avaliações de [authorIds] no local, mais recentes primeiro. Filtra no
  /// servidor (`placeId ==` + `authorId in`, lotes de [whereInLimit]): não
  /// lê avaliações de terceiros e não perde as de amigos mais antigas.
  Future<List<Review>> fetchReviewsForPlace(
    String placeId,
    List<String> authorIds,
  );
}
