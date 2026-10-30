import 'models/place_activity.dart';

const foodTags = ['caseiro', 'vegetariano', 'vegano', 'low-carb', 'integral'];

bool validFoodTags(Iterable<String> tags) =>
    tags.length == tags.toSet().length && tags.every(foodTags.contains);

/// Só a última avaliação por autor conta; no empate vence o maior id.
Map<String, int> confirmedFoodTags(
  Iterable<Review> reviews, {
  String? ownerUid,
}) {
  final latest = <String, Review>{};
  for (final review in reviews) {
    if (review.authorId == ownerUid) continue;
    final old = latest[review.authorId];
    if (old == null ||
        review.createdAt.isAfter(old.createdAt) ||
        (review.createdAt == old.createdAt &&
            review.id.compareTo(old.id) > 0)) {
      latest[review.authorId] = review;
    }
  }
  final counts = <String, int>{};
  for (final review in latest.values) {
    for (final tag in review.tags.toSet().where(foodTags.contains)) {
      counts.update(tag, (n) => n + 1, ifAbsent: () => 1);
    }
  }
  return {
    for (final tag in foodTags)
      if ((counts[tag] ?? 0) >= 3) tag: counts[tag]!,
  };
}

bool matchesFoodTags(Iterable<String> selected, Map<String, int> confirmed) =>
    selected.every(confirmed.containsKey);
