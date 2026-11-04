part of 'place_activity.dart';

class Visit extends PlaceActivity {
  const Visit({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.placeId,
    required this.placeName,
    required this.createdAt,
    this.companion,
    this.silent = false,
    this.priceBand,
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
  @override
  final Companion? companion;
  @override
  final DateTime createdAt;
  @override
  final PriceBand? priceBand;
}

class NewVisit {
  const NewVisit({
    required this.authorId,
    required this.authorName,
    required this.placeId,
    required this.placeName,
    this.companion,
    this.silent = false,
    this.priceBand,
  });

  final bool silent;
  final String authorId;
  final String authorName;
  final String placeId;
  final String placeName;
  final Companion? companion;

  final PriceBand? priceBand;
}
