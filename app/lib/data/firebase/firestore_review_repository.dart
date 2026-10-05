import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/companion.dart';
import '../../domain/models/review.dart';
import '../../domain/models/scores.dart';
import '../../domain/photo_compression.dart';
import '../chunk.dart';
import '../repositories/review_repository.dart';

class FirestoreReviewRepository implements ReviewRepository {
  FirestoreReviewRepository(
    this._db, {
    this.perBatchLimit = defaultPerBatchLimit,
  });

  final FirebaseFirestore _db;

  static const int defaultPerBatchLimit = 100;

  /// Limite por lote na consulta do feed.
  final int perBatchLimit;

  /// Coleção das fotos (bytes no Firestore; id = id da avaliação).
  static const String reviewPhotosCollection = 'reviewPhotos';

  CollectionReference<Map<String, dynamic>> get _reviews =>
      _db.collection('reviews');

  @override
  Future<void> createReview(NewReview review, {Uint8List? photo}) {
    if (photo != null && (photo.isEmpty || photo.length > maxPhotoBytes)) {
      throw ArgumentError.value(
        photo.length,
        'photo',
        'precisa ter de 1 a $maxPhotoBytes bytes',
      );
    }
    // Id gerado no cliente: a foto usa o mesmo id da avaliação.
    final ref = _reviews.doc();
    final batch = _db.batch();
    // Schema exato (11 chaves) validado pelas Rules (hasOnly/hasAll). O período
    // do dia NÃO é gravado; createdAt é sempre o timestamp do servidor.
    // `comment` já vem normalizado (aparado; null quando não há).
    batch.set(ref, {
      'authorId': review.authorId,
      'authorName': review.authorName,
      'placeId': review.placeId,
      'placeName': review.placeName,
      'food': review.scores.food,
      'ambience': review.scores.ambience,
      'service': review.scores.service,
      'companion': review.companion?.value,
      'comment': review.comment,
      'hasPhoto': photo != null,
      'createdAt': FieldValue.serverTimestamp(),
    });
    if (photo != null) {
      // As Rules só aceitam a foto no mesmo batch da review nova do mesmo id.
      batch.set(_db.collection(reviewPhotosCollection).doc(ref.id), {
        'authorId': review.authorId,
        'jpeg': Blob(photo),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    return batch.commit();
  }

  @override
  Future<List<Review>> fetchReviewsByAuthors(List<String> authorIds) async {
    final ids = authorIds.toSet().toList();
    if (ids.isEmpty) return [];
    final batches = chunked(ids, ReviewRepository.whereInLimit);
    final snaps = await Future.wait(
      batches.map(
        (batch) => _reviews
            .where('authorId', whereIn: batch)
            .orderBy('createdAt', descending: true)
            .limit(perBatchLimit)
            .get(),
      ),
    );
    final byId = <String, Review>{};
    // Um lote que bateu o limite pode ter avaliações mais antigas que não
    // vieram. Para os lotes ficarem consistentes entre si, corta o resultado
    // no mais recente dos "createdAt mais antigos" entre os lotes cheios.
    DateTime? cutoff;
    for (final snap in snaps) {
      DateTime? oldestInBatch;
      for (final doc in snap.docs) {
        final r = _fromDoc(doc);
        if (r == null) continue;
        byId[r.id] = r;
        if (oldestInBatch == null || r.createdAt.isBefore(oldestInBatch)) {
          oldestInBatch = r.createdAt;
        }
      }
      if (snap.docs.length >= perBatchLimit && oldestInBatch != null) {
        if (cutoff == null || oldestInBatch.isAfter(cutoff)) {
          cutoff = oldestInBatch;
        }
      }
    }
    return applyBatchCutoff(byId.values, cutoff);
  }

  @override
  Future<List<Review>> fetchReviewsForPlace(
    String placeId,
    List<String> authorIds,
  ) async {
    final ids = authorIds.toSet().toList();
    if (ids.isEmpty) return [];
    final snaps = await Future.wait(
      chunked(ids, ReviewRepository.whereInLimit).map(
        (batch) => _reviews
            .where('placeId', isEqualTo: placeId)
            .where('authorId', whereIn: batch)
            .orderBy('createdAt', descending: true)
            .get(),
      ),
    );
    final byId = {
      for (final snap in snaps)
        for (final r in snap.docs.map(_fromDoc).whereType<Review>()) r.id: r,
    };
    return applyBatchCutoff(byId.values, null);
  }

  /// Remove avaliações anteriores a [cutoff] (quando houver) e ordena da mais
  /// recente para a mais antiga.
  static List<Review> applyBatchCutoff(
    Iterable<Review> reviews,
    DateTime? cutoff,
  ) {
    final kept = cutoff == null
        ? reviews.toList()
        : reviews.where((r) => !r.createdAt.isBefore(cutoff)).toList();
    kept.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return kept;
  }

  Review? _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final ts = d['createdAt'];
    if (ts is! Timestamp) return null;
    try {
      return Review(
        id: doc.id,
        authorId: d['authorId'] as String,
        authorName: d['authorName'] as String,
        placeId: d['placeId'] as String,
        placeName: d['placeName'] as String,
        scores: Scores(
          food: (d['food'] as num).toInt(),
          ambience: (d['ambience'] as num).toInt(),
          service: (d['service'] as num).toInt(),
        ),
        companion: Companion.fromValue(d['companion'] as String?),
        // Normaliza na leitura: avaliações da Onda 1 não têm a chave, e vazio
        // ou só espaços vira null (a UI nunca mostra citação vazia).
        comment: Review.normalizeComment(
          d['comment'] is String ? d['comment'] as String : null,
        ),
        createdAt: ts.toDate(),
        // Reviews anteriores ao G1 não têm a chave: sem foto.
        hasPhoto: d['hasPhoto'] == true,
      );
    } on Object {
      // Documento fora do schema: ignora em vez de derrubar o feed.
      return null;
    }
  }
}
