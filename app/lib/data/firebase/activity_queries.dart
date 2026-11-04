import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/place_activity.dart';
import '../activity_batch.dart';
import '../chunk.dart';

Future<ActivityBatch<T>> fetchPublicByAuthors<T extends PlaceActivity>(
  CollectionReference<Map<String, dynamic>> collection,
  List<String> authors, {
  required int perBatchLimit,
  required T? Function(QueryDocumentSnapshot<Map<String, dynamic>>) fromDoc,
}) async {
  final batches = <RawBatch<T>>[];
  for (final ids in chunked(authors.toSet().toList(), whereInLimit)) {
    final query = collection
        .where('authorId', whereIn: ids)
        .orderBy('createdAt', descending: true);
    QueryDocumentSnapshot<Map<String, dynamic>>? cursor;
    final public = <T>[];
    var exhausted = false;
    DateTime? boundary;
    while (!exhausted) {
      final page =
          await (cursor == null ? query : query.startAfterDocument(cursor))
              .limit(100)
              .get(const GetOptions(source: Source.server))
              .timeout(const Duration(seconds: 15));
      for (final doc in page.docs) {
        final item = fromDoc(doc);
        if (item != null && !item.silent) {
          if (boundary != null && item.createdAt.isBefore(boundary)) {
            exhausted = true;
            break;
          }
          public.add(item);
          if (public.length == perBatchLimit) boundary = item.createdAt;
        }
        final timestamp = doc.data()['createdAt'];
        if (boundary != null &&
            timestamp is Timestamp &&
            timestamp.toDate().isBefore(boundary)) {
          exhausted = true;
          break;
        }
      }
      exhausted = exhausted || page.docs.length < 100;
      if (page.docs.isNotEmpty) cursor = page.docs.last;
    }
    batches.add((
      items: public,
      createdAts: public.map((a) => a.createdAt).toList(),
      docCount: public.length,
    ));
  }
  return mergeAuthorBatches(batches, batchLimit: perBatchLimit);
}

Future<ActivityBatch<T>> fetchLatestByAuthors<T extends PlaceActivity>(
  CollectionReference<Map<String, dynamic>> collection,
  List<String> authorIds, {
  required int perBatchLimit,
  required T? Function(QueryDocumentSnapshot<Map<String, dynamic>> doc) fromDoc,
  int? limit,
}) async {
  assert(limit == null || limit > 0);
  final ids = authorIds.toSet().toList();
  if (ids.isEmpty) return ActivityBatch<T>(const []);
  final batchLimit = limit == null || limit > perBatchLimit
      ? perBatchLimit
      : limit;
  final snaps = await Future.wait(
    chunked(ids, whereInLimit).map(
      (batch) => collection
          .where('authorId', whereIn: batch)
          .orderBy('createdAt', descending: true)
          .limit(batchLimit)
          .get(),
    ),
  );
  return mergeAuthorBatches(
    [
      for (final snap in snaps)
        (
          items: snap.docs.map(fromDoc).whereType<T>().toList(),
          createdAts: [
            for (final doc in snap.docs)
              if (doc.data()['createdAt'] case final Timestamp ts) ts.toDate(),
          ],
          docCount: snap.docs.length,
        ),
    ],
    batchLimit: batchLimit,
    limit: limit,
  );
}

Future<List<T>> fetchForPlace<T extends PlaceActivity>(
  CollectionReference<Map<String, dynamic>> collection,
  String placeId,
  List<String> authorIds, {
  required T? Function(QueryDocumentSnapshot<Map<String, dynamic>> doc) fromDoc,
}) async {
  final ids = authorIds.toSet().toList();
  if (ids.isEmpty) return [];
  final snaps = await Future.wait(
    chunked(ids, whereInLimit).map(
      (batch) => collection
          .where('placeId', isEqualTo: placeId)
          .where('authorId', whereIn: batch)
          .orderBy('createdAt', descending: true)
          .get(),
    ),
  );
  final byId = {
    for (final snap in snaps)
      for (final item in snap.docs.map(fromDoc).whereType<T>()) item.id: item,
  };
  return keepFrom(byId.values, null);
}
