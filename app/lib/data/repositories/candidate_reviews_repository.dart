import '../../domain/models/review.dart';

abstract class CandidateReviewsRepository {
  Future<List<Review>> reviewsForCandidates(
    List<String> placeIds,
    List<String> authorIds, {
    bool Function()? cancelled,
  });
}
