import 'models/place.dart';
import 'models/place_activity.dart';
import 'models/scores.dart';
import 'price_summary.dart';

class FeedItem {
  FeedItem({required this.place, required Iterable<PlaceActivity> activities})
    : activities = List.unmodifiable(
        [...activities]..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      ),
      assert(activities.isNotEmpty);

  final Place place;

  final List<PlaceActivity> activities;

  late final List<Review> reviews = activities.whereType<Review>().toList();

  late final List<Visit> visits = activities.whereType<Visit>().toList();

  String get placeId => place.id;
  String get placeName => place.name;

  DateTime get latestAt => activities.first.createdAt;

  int get trips => activities.length;

  List<String> get authorNames {
    final seen = <String>{};
    final names = <String>[];
    for (final a in activities) {
      if (seen.add(a.authorId)) names.add(a.authorName);
    }
    return names;
  }

  String get headline => formatVisitors(authorNames);

  Review? get latestComment {
    for (final r in reviews) {
      if (r.comment?.trim().isNotEmpty ?? false) return r;
    }
    return null;
  }

  Review? get latestPhoto {
    for (final r in reviews) {
      if (r.hasPhoto) return r;
    }
    return null;
  }

  List<Review> get photoReviews => [
    for (final r in reviews)
      if (r.hasPhoto) r,
  ];

  late final AxisAverages? averages = reviews.isEmpty
      ? null
      : AxisAverages.of(reviews.map((r) => r.scores));

  DateTime? _priceAt;
  PriceSummary? _price;

  PriceSummary? priceAt(DateTime now) {
    if (_priceAt != now) {
      _price = PriceSummary.of(activities, now: now);
      _priceAt = now;
    }
    return _price;
  }

  late final List<TrustSource> sources = _sourcesOf(activities);

  TrustSource? get recurrent {
    TrustSource? best;
    for (final s in sources) {
      if (s.trips < 2) continue;
      if (best == null || s.trips > best.trips) best = s;
    }
    return best;
  }

  static List<TrustSource> _sourcesOf(List<PlaceActivity> activities) {
    final latest = <String, PlaceActivity>{};
    final latestReview = <String, Review>{};
    final count = <String, int>{};
    for (final a in activities) {
      latest.putIfAbsent(a.authorId, () => a);
      if (a is Review) latestReview.putIfAbsent(a.authorId, () => a);
      count[a.authorId] = (count[a.authorId] ?? 0) + 1;
    }
    return [
      for (final e in latest.entries)
        TrustSource(
          latest: e.value,
          latestReview: latestReview[e.key],
          trips: count[e.key]!,
        ),
    ]..sort((a, b) {
      final byDate = b.latest.createdAt.compareTo(a.latest.createdAt);
      return byDate != 0 ? byDate : a.authorId.compareTo(b.authorId);
    });
  }
}

class TrustSource {
  TrustSource({required this.latest, Review? latestReview, required this.trips})
    : latestReview = latestReview ?? (latest is Review ? latest : null),
      assert(trips >= 1);

  final PlaceActivity latest;
  final Review? latestReview;
  final int trips;

  String get authorId => latest.authorId;
  String get authorName => latest.authorName;

  bool get onlyVisits => latestReview == null;

  bool get reviewIsOlder => latestReview != null && latest is Visit;
}

String recurrenceLabel(String name, int trips) => '$name voltou $trips vezes';

String? placeRecurrenceLabel({
  required int trips,
  required int friends,
  required int ownTrips,
  required bool anyoneReturned,
}) {
  if (!anyoneReturned || trips < 2) return null;
  final idas = '$trips idas';
  final friendsPart = friends == 1 ? '1 amigo' : '$friends amigos';
  if (ownTrips == 0) return '$idas de $friendsPart';
  if (friends == 0) return '$idas suas';
  return '$idas suas e de $friendsPart';
}

String formatVisitors(List<String> names) {
  if (names.isEmpty) return '';
  if (names.length == 1) return '${names.first} foi aqui';
  final head = names.sublist(0, names.length - 1).join(', ');
  return '$head e ${names.last} foram aqui';
}

List<FeedItem> groupActivitiesIntoFeed(
  Iterable<PlaceActivity> activities, {
  Map<String, Place> places = const {},
}) {
  final byPlace = <String, List<PlaceActivity>>{};
  for (final a in activities) {
    byPlace.putIfAbsent(a.placeId, () => []).add(a);
  }
  final items =
      byPlace.entries.map((e) {
        final place =
            places[e.key] ??
            Place(
              id: e.key,
              name: _newest(e.value).placeName,
              category: '',
              neighborhood: '',
              city: '',
              inCatalog: false,
            );
        return FeedItem(place: place, activities: e.value);
      }).toList()..sort((a, b) {
        final byDate = b.latestAt.compareTo(a.latestAt);
        return byDate != 0 ? byDate : a.placeId.compareTo(b.placeId);
      });
  return items;
}

PlaceActivity _newest(List<PlaceActivity> list) {
  PlaceActivity? best;
  for (final a in list) {
    final better =
        best == null ||
        (a is Review && best is! Review) ||
        ((a is Review) == (best is Review) &&
            a.createdAt.isAfter(best.createdAt));
    if (better) best = a;
  }
  return best!;
}

List<FeedItem> groupPublicActivitiesIntoFeed(
  Iterable<PlaceActivity> activities, {
  Map<String, Place> places = const {},
}) =>
    groupActivitiesIntoFeed(activities.where((a) => !a.silent), places: places);
