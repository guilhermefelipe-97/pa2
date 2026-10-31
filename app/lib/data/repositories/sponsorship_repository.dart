class SponsoredSlot {
  const SponsoredSlot(this.id, this.placeId, this.startsAt, this.endsAt);
  final String id, placeId;
  final DateTime startsAt, endsAt;
  bool active(DateTime now) => !now.isBefore(startsAt) && now.isBefore(endsAt);
}

abstract class SponsorshipRepository {
  Future<List<SponsoredSlot>> current(DateTime now);
}
