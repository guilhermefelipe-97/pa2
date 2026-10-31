import '../../domain/models/review.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../repositories/reputation_repository.dart';
import 'audit_log.dart';
import 'firestore_review_repository.dart';

class FirestoreReputationRepository implements ReputationRepository {
  FirestoreReputationRepository(this.db);
  final FirebaseFirestore db;
  static const timeout = Duration(seconds: 15);
  @override
  Future<ReviewPage> reviewsForPlace(String placeId, {String? after}) async {
    var query = db
        .collection('reviews')
        .where('placeId', isEqualTo: placeId)
        .orderBy('createdAt', descending: true);
    if (after != null) {
      final cursor = await db
          .collection('reviews')
          .doc(after)
          .get(const GetOptions(source: Source.server))
          .timeout(timeout);
      query = query.startAfterDocument(cursor);
    }
    final page = await query
        .limit(20)
        .get(const GetOptions(source: Source.server))
        .timeout(timeout);
    return (
      reviews: page.docs
          .map(FirestoreReviewRepository.fromDoc)
          .whereType<Review>()
          .toList(),
      next: page.docs.length == 20 ? page.docs.last.id : null,
    );
  }

  @override
  Future<OwnerReply?> replyFor(String reviewId) async {
    final d =
        (await db
                .collection('ownerReplies')
                .doc(reviewId)
                .get(const GetOptions(source: Source.server))
                .timeout(timeout))
            .data();
    if (d == null) return null;
    return OwnerReply(
      d['authorId'] as String,
      d['authorName'] as String,
      d['text'] as String,
      (d['createdAt'] as Timestamp).toDate(),
    );
  }

  @override
  Future<void> reply(String uid, String reviewId, String text) async {
    text = text.trim();
    if (text.isEmpty || text.length > 1000) {
      throw ArgumentError('Resposta de 1–1000 caracteres');
    }
    // ID determinístico: reconcilia antes de repetir a tentativa.
    final existing = await replyFor(reviewId);
    if (existing != null) {
      if (existing.authorId == uid && existing.text == text) return;
      throw StateError('Avaliação já respondida');
    }
    final profile = await db
        .collection('users')
        .doc(uid)
        .get(const GetOptions(source: Source.server))
        .timeout(timeout);
    final review = await db
        .collection('reviews')
        .doc(reviewId)
        .get(const GetOptions(source: Source.server))
        .timeout(timeout);
    final placeId = review.data()!['placeId'] as String;
    final batch = db.batch();
    batch.set(db.collection('ownerReplies').doc(reviewId), {
      'authorId': uid,
      'authorName': profile.data()!['displayName'],
      'placeId': placeId,
      'reviewId': reviewId,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
    addAuditEntry(
      batch,
      db,
      collection: 'ownerReplies',
      docId: reviewId,
      actorUid: uid,
      placeId: placeId,
    );
    try {
      await batch.commit().timeout(timeout);
    } on Object {
      final written = await replyFor(reviewId);
      if (written?.authorId != uid || written?.text != text) rethrow;
    }
  }
}
