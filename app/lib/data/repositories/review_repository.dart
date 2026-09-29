import '../../domain/models/review.dart';

abstract class ReviewRepository {
  /// Limite do operador `whereIn` do Firestore.
  static const int whereInLimit = 30;

  Future<void> createReview(NewReview review);

  /// Avaliações dos [authorIds], mais recentes primeiro.
  Future<List<Review>> fetchReviewsByAuthors(List<String> authorIds);
}
