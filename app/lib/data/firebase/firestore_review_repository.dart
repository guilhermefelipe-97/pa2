import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/companion.dart';
import '../../domain/models/place.dart';
import '../../domain/models/review.dart';
import '../../domain/models/scores.dart';
import '../../domain/photo_compression.dart';
import '../../domain/price_band.dart';
import '../../domain/food_tags.dart';
import '../repositories/food_tag_repository.dart';
import '../repositories/candidate_reviews_repository.dart';
import 'firestore_owner_repository.dart';
import '../activity_batch.dart';
import '../repositories/public_activity_repository.dart';
import '../chunk.dart';
import '../repositories/review_repository.dart';
import 'activity_queries.dart' as queries;
import 'audit_log.dart';
import 'place_doc.dart';

class FirestoreReviewRepository
    implements
        ReviewRepository,
        CandidateReviewsRepository,
        FoodTagRepository,
        PublicActivityRepository<Review> {
  FirestoreReviewRepository(
    this._db, {
    this.perBatchLimit = defaultPerBatchLimit,
  });

  final FirebaseFirestore _db;

  static const int defaultPerBatchLimit = 100;

  final int perBatchLimit;

  static const String reviewsCollection = 'reviews';

  static const String reviewPhotosCollection = 'reviewPhotos';

  static const String reviewLocksCollection = 'reviewLocks';

  CollectionReference<Map<String, dynamic>> get _reviews =>
      _db.collection(reviewsCollection);

  DocumentReference<Map<String, dynamic>> _lockRef(
    String uid,
    String placeId,
  ) => _db
      .collection('users')
      .doc(uid)
      .collection(reviewLocksCollection)
      .doc(placeId);

  @override
  Future<DateTime?> reviewLockOf(String uid, String placeId) async {
    final snap = await _lockRef(
      uid,
      placeId,
    ).get(const GetOptions(source: Source.server));
    final lastAt = snap.data()?['lastAt'];
    return lastAt is Timestamp ? lastAt.toDate() : null;
  }

  @override
  Future<CreateReviewResult> createReview(
    NewReview review, {
    Uint8List? photo,
    Place? newPlace,
  }) async {
    if (photo != null && (photo.isEmpty || photo.length > maxPhotoBytes)) {
      throw ArgumentError.value(
        photo.length,
        'photo',
        'precisa ter de 1 a $maxPhotoBytes bytes',
      );
    }
    if (newPlace != null && newPlace.id != review.placeId) {
      throw ArgumentError.value(newPlace.id, 'newPlace', 'outro local');
    }

    final ref = _reviews.doc();
    final placeRef = newPlace != null && newPlace.discovered
        ? _db.collection(placesCollection).doc(newPlace.id)
        : null;
    var placeName = review.placeName;
    var createPlace = false;
    if (placeRef != null) {
      try {
        final existing = await placeRef.get().timeout(
          const Duration(seconds: 10),
        );
        createPlace = !existing.exists;

        placeName = _storedName(existing) ?? placeName;
      } on Object {
        createPlace = true;
      }
    }
    try {
      await _commit(
        ref,
        review,
        placeName,
        photo,
        createPlace ? newPlace : null,
      );
      return (placeCreated: createPlace);
    } on Object catch (error, stack) {
      if (await _existsOnServer(ref) == true) {
        return (placeCreated: createPlace);
      }
      if (!createPlace) Error.throwWithStackTrace(error, stack);

      final DocumentSnapshot<Map<String, dynamic>> existing;
      try {
        existing = await placeRef!
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 10));
      } on Object {
        Error.throwWithStackTrace(error, stack);
      }
      if (!existing.exists) Error.throwWithStackTrace(error, stack);
      placeName = _storedName(existing) ?? placeName;
      await _commit(ref, review, placeName, photo, null);
      return (placeCreated: false);
    }
  }

  static String? _storedName(DocumentSnapshot<Map<String, dynamic>> snap) {
    final name = snap.data()?['name'];
    return snap.exists && name is String ? name : null;
  }

  static Future<bool?> _existsOnServer(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    try {
      return (await ref
              .get(const GetOptions(source: Source.server))
              .timeout(const Duration(seconds: 10)))
          .exists;
    } on Object {
      return null;
    }
  }

  Future<void> _commit(
    DocumentReference<Map<String, dynamic>> ref,
    NewReview review,
    String placeName,
    Uint8List? photo,
    Place? createPlace,
  ) {
    final batch = _db.batch();
    if (createPlace != null) {
      batch.set(
        _db.collection(placesCollection).doc(createPlace.id),
        newPlaceData(createPlace, uid: review.authorId),
      );
    }

    batch.set(ref, {
      'silent': review.silent,
      'authorId': review.authorId,
      'authorName': review.authorName,
      'placeId': review.placeId,
      'placeName': placeName,
      'food': review.scores.food,
      'ambience': review.scores.ambience,
      'service': review.scores.service,
      'companion': review.companion?.value,
      'comment': review.comment,
      'hasPhoto': photo != null,
      'priceBand': review.priceBand?.value,
      'tags': review.tags,
      'createdAt': FieldValue.serverTimestamp(),
    });

    addAuditEntry(
      batch,
      _db,
      collection: reviewsCollection,
      docId: ref.id,
      actorUid: review.authorId,
      placeId: review.placeId,
    );
    if (photo != null) {
      batch.set(_db.collection(reviewPhotosCollection).doc(ref.id), {
        'authorId': review.authorId,
        'jpeg': Blob(photo),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    batch.set(_lockRef(review.authorId, review.placeId), {
      'lastAt': FieldValue.serverTimestamp(),
      'reviewId': ref.id,
      'placeId': review.placeId,
    });
    return batch.commit().timeout(const Duration(seconds: 15));
  }

  @override
  Future<ActivityBatch<Review>> fetchPublicByAuthors(List<String> authors) =>
      queries.fetchPublicByAuthors(
        _reviews,
        authors,
        perBatchLimit: perBatchLimit,
        fromDoc: fromDoc,
      );

  @override
  Future<ActivityBatch<Review>> fetchReviewsByAuthors(
    List<String> authorIds, {
    int? limit,
  }) => queries.fetchLatestByAuthors(
    _reviews,
    authorIds,
    perBatchLimit: perBatchLimit,
    fromDoc: fromDoc,
    limit: limit,
  );

  @override
  Future<List<Review>> fetchReviewsForPlace(
    String placeId,
    List<String> authorIds,
  ) => queries.fetchForPlace(_reviews, placeId, authorIds, fromDoc: fromDoc);

  @override
  Future<List<Review>> reviewsForCandidates(
    List<String> placeIds,
    List<String> authorIds, {
    bool Function()? cancelled,
  }) async {
    final places = placeIds.toSet().toList(),
        authors = authorIds.toSet().toList();
    if (places.isEmpty || authors.isEmpty) return [];
    final jobs = [
      for (final group in chunked(authors, whereInLimit))
        for (final ids in chunked(places, whereInLimit ~/ group.length))
          (authors: group, places: ids),
    ];
    var next = 0;
    final result = <String, Review>{};
    var failed = false;
    bool stopped() => failed || (cancelled?.call() ?? false);
    Future<void> worker() async {
      while (!stopped() && next < jobs.length) {
        final job = jobs[next++];
        final query = _reviews
            .where('placeId', whereIn: job.places)
            .where('authorId', whereIn: job.authors)
            .orderBy('createdAt', descending: true)
            .orderBy(FieldPath.documentId, descending: true);
        QueryDocumentSnapshot<Map<String, dynamic>>? cursor;
        while (!stopped()) {
          final page =
              await (cursor == null ? query : query.startAfterDocument(cursor))
                  .limit(100)
                  .get(const GetOptions(source: Source.server))
                  .timeout(const Duration(seconds: 10));
          if (stopped()) return;
          for (final doc in page.docs) {
            final review = fromDoc(doc);
            if (review != null) result[review.id] = review;
          }
          if (page.docs.length < 100) break;
          cursor = page.docs.last;
        }
      }
    }

    try {
      await Future.wait([
        for (var i = 0; i < jobs.length && i < 4; i++) worker(),
      ], eagerError: true);
    } on Object {
      failed = true;
      rethrow;
    }
    return stopped() ? [] : result.values.toList();
  }

  @override
  Future<Map<String, Map<String, int>>> confirmedFor(
    Iterable<String> placeIds,
  ) async {
    final ids = placeIds.toSet().toList();
    final result = <String, Map<String, int>>{};
    for (final batch in chunked(ids, whereInLimit)) {
      final docs = await _reviews
          .where('placeId', whereIn: batch)
          .get(const GetOptions(source: Source.server));
      final owners = FirestoreOwnerRepository(_db);
      final ownerUids = await Future.wait(batch.map(owners.ownerOf));
      for (var i = 0; i < batch.length; i++) {
        final id = batch[i];
        final owner = ownerUids[i];
        final reviews = docs.docs
            .where((d) => d.data()['placeId'] == id)
            .map(fromDoc)
            .whereType<Review>();
        result[id] = confirmedFoodTags(reviews, ownerUid: owner);
      }
    }
    return result;
  }

  static int? _axis(Map<String, dynamic> d, String key) {
    if (!d.containsKey(key)) throw FormatException('eixo "$key" ausente');
    final v = d[key];
    if (v == null) return null;
    if (v is int && Scores.isValid(v)) return v;
    throw FormatException('eixo "$key" inválido: $v');
  }

  static List<String> _readTags(Object? value) {
    if (value == null) return const [];
    if (value is! List || value.any((tag) => tag is! String)) return const [];
    final tags = List<String>.from(value);
    return validFoodTags(tags) ? tags : const [];
  }

  static Review? fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final ts = d['createdAt'];
    if (ts is! Timestamp || (d.containsKey('silent') && d['silent'] is! bool)) {
      return null;
    }
    try {
      return Review(
        silent: d['silent'] == true,
        id: doc.id,
        authorId: d['authorId'] as String,
        authorName: d['authorName'] as String,
        placeId: d['placeId'] as String,
        placeName: d['placeName'] as String,
        scores: Scores(
          food: _axis(d, 'food'),
          ambience: _axis(d, 'ambience'),
          service: _axis(d, 'service'),
        ),
        companion: Companion.fromValue(d['companion'] as String?),

        comment: Review.normalizeComment(
          d['comment'] is String ? d['comment'] as String : null,
        ),
        createdAt: ts.toDate(),

        hasPhoto: d['hasPhoto'] == true,
        priceBand: readPriceBand(d),
        tags: _readTags(d['tags']),
      );
    } on Object {
      return null;
    }
  }
}
