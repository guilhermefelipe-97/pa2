import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/place_activity.dart';
import '../activity_batch.dart';
import '../chunk.dart';

/// Idas (avaliações ou visitas) de [authorIds] em [collection], mais
/// recentes primeiro: `authorId in` em lotes de [whereInLimit], cada lote com
/// as suas `min(limit, perBatchLimit)` mais recentes, juntados por
/// [mergeAuthorBatches] (corte consistente entre lotes cheios). Docs fora do
/// schema ([fromDoc] devolve `null`) são ignorados, mas o `createdAt` deles
/// conta para o corte.
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

/// Idas de [authorIds] no local [placeId], mais recentes primeiro. Filtra no
/// servidor (`placeId ==` + `authorId in`, lotes de [whereInLimit]): não lê
/// idas de terceiros e não perde as mais antigas.
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
