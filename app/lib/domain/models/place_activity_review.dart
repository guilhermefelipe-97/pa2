part of 'place_activity.dart';

class Review extends PlaceActivity {
  const Review({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.placeId,
    required this.placeName,
    required this.scores,
    required this.companion,
    required this.createdAt,
    this.comment,
    this.hasPhoto = false,
    this.silent = false,
    this.priceBand,
    this.tags = const [],
    this.couvert,
    this.serviceFee,
  });

  @override
  final String id;
  @override
  final bool silent;
  @override
  final String authorId;
  @override
  final String authorName;
  @override
  final String placeId;
  @override
  final String placeName;
  final Scores scores;
  final List<String> tags;
  @override
  final Companion? companion;

  final String? comment;

  @override
  final DateTime createdAt;

  final bool hasPhoto;

  @override
  final PriceBand? priceBand;

  @override
  final bool? couvert;

  @override
  final bool? serviceFee;

  static const int maxCommentLength = 280;

  static String? normalizeComment(String? raw) {
    final trimmed = raw?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static bool isCommentWithinLimit(String? raw) =>
      (normalizeComment(raw)?.length ?? 0) <= maxCommentLength;
}

class NewReview {
  NewReview({
    required this.authorId,
    required this.authorName,
    required this.placeId,
    required this.placeName,
    required this.scores,
    this.companion,
    String? comment,
    this.silent = false,
    this.priceBand,
    this.tags = const [],
    this.couvert,
    this.serviceFee,
  }) : comment = Review.normalizeComment(comment);

  final bool silent;
  final String authorId;
  final String authorName;
  final String placeId;
  final String placeName;
  final Scores scores;
  final List<String> tags;
  final Companion? companion;

  final String? comment;

  final PriceBand? priceBand;

  final bool? couvert;
  final bool? serviceFee;
}
