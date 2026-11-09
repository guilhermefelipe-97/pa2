import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/review.dart';
import '../../domain/models/visit.dart';
import '../repositories/place_history_repository.dart';
import 'firestore_review_repository.dart';
import 'firestore_visit_repository.dart';

class FirestorePlaceHistoryRepository implements PlaceHistoryRepository {
  FirestorePlaceHistoryRepository(
    this._db, {
    this.pageSize = 200,
    this.maxPages = 50,
  });

  final FirebaseFirestore _db;
  final int pageSize;

  /// Proteção contra leitura sem fim; acima disso a janela é recusada
  /// (falha), nunca truncada em silêncio.
  final int maxPages;

  static const timeout = Duration(seconds: 15);

  @override
  Future<List<Review>> reviewsSince(String placeId, DateTime since) =>
      _read('reviews', placeId, since, FirestoreReviewRepository.fromDoc);

  @override
  Future<List<Visit>> visitsSince(String placeId, DateTime since) =>
      _read('visits', placeId, since, FirestoreVisitRepository.parse);

  Future<List<T>> _read<T>(
    String collection,
    String placeId,
    DateTime since,
    T? Function(QueryDocumentSnapshot<Map<String, dynamic>>) fromDoc,
  ) async {
    final base = _db
        .collection(collection)
        .where('placeId', isEqualTo: placeId)
        .where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(since.toUtc()),
        )
        .orderBy('createdAt', descending: true);
    final result = <T>[];
    QueryDocumentSnapshot<Map<String, dynamic>>? last;
    for (var page = 0; page < maxPages; page++) {
      final query = last == null ? base : base.startAfterDocument(last);
      final snap = await query
          .limit(pageSize)
          .get(const GetOptions(source: Source.server))
          .timeout(timeout);
      result.addAll(snap.docs.map(fromDoc).whereType<T>());
      if (snap.docs.length < pageSize) return result;
      last = snap.docs.last;
    }
    throw StateError('Histórico de $placeId maior que o limite de leitura.');
  }
}
