class PlacePresentation {
  const PlacePresentation({this.description = '', this.hours = ''});
  final String description, hours;
}

class OwnerPlaceSummary {
  const OwnerPlaceSummary({
    required this.reviews,
    required this.unanswered,
    this.rating,
  });
  final int reviews, unanswered;
  final double? rating;
}

abstract class OwnerWorkspaceRepository {
  Future<PlacePresentation> presentation(String placeId);
  Future<void> save(String placeId, String uid, PlacePresentation value);
  Future<OwnerPlaceSummary> summary(String placeId);
}
