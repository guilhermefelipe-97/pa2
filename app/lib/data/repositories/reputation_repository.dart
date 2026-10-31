import '../../domain/models/review.dart';

class OwnerReply {
  const OwnerReply(this.authorId, this.authorName, this.text, this.createdAt);
  final String authorId, authorName, text;
  final DateTime createdAt;
}

typedef ReviewPage = ({List<Review> reviews, String? next});

abstract class ReputationRepository {
  Future<ReviewPage> reviewsForPlace(String placeId, {String? after});
  Future<OwnerReply?> replyFor(String reviewId);
  Future<void> reply(String uid, String reviewId, String text);
}
