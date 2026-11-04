import '../../domain/models/review.dart';

/// Complete history restricted to the followed authors and candidate places.
abstract class CandidateReviewsRepository {
  Future<List<Review>> reviewsForCandidates(
    List<String> placeIds,
    List<String> authorIds, {
    bool Function()? cancelled,
  });
}
