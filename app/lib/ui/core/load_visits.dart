import 'package:flutter/foundation.dart';

import '../../data/activity_batch.dart';
import '../../data/repositories/public_activity_repository.dart';
import '../../data/repositories/review_repository.dart';
import '../../data/repositories/visit_repository.dart';
import '../../domain/models/place_activity.dart';

typedef VisitsRead = ({ActivityBatch<Visit> batch, bool ok});

Future<VisitsRead> loadVisitsOrEmpty(
  String where,
  Future<ActivityBatch<Visit>> Function() read,
) async {
  try {
    return (batch: await read(), ok: true);
  } on Object catch (e) {
    debugPrint('Visitas indisponíveis ($where): $e');
    return (batch: const ActivityBatch<Visit>([]), ok: false);
  }
}

Future<({List<PlaceActivity> activities, bool visitsOk})> loadFriendActivities({
  required ReviewRepository reviews,
  required VisitRepository visits,
  required List<String> authors,
  required String where,
  bool publicOnly = false,
}) async {
  final visitsRead = loadVisitsOrEmpty(
    where,
    () => publicOnly && visits is PublicActivityRepository<Visit>
        ? (visits as PublicActivityRepository<Visit>).fetchPublicByAuthors(
            authors,
          )
        : visits.fetchVisitsByAuthors(authors),
  );
  final reviewBatch =
      await (publicOnly && reviews is PublicActivityRepository<Review>
          ? (reviews as PublicActivityRepository<Review>).fetchPublicByAuthors(
              authors,
            )
          : reviews.fetchReviewsByAuthors(authors));
  final visitBatch = await visitsRead;
  final cut = commonCutoff([reviewBatch.cutoff, visitBatch.batch.cutoff]);
  return (
    activities: <PlaceActivity>[
      ...keepFrom(reviewBatch.items, cut),
      ...keepFrom(visitBatch.batch.items, cut),
    ],
    visitsOk: visitBatch.ok,
  );
}
