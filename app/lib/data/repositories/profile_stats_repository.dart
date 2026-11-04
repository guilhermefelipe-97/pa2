class ProfileTotals {
  const ProfileTotals({this.reviews, this.visits, this.following});
  final int? reviews, visits, following;
}

abstract class ProfileStatsRepository {
  Future<ProfileTotals> totals(String uid);
}
