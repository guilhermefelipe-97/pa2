import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../repositories/owner_workspace_repository.dart';

class FirestoreOwnerWorkspaceRepository implements OwnerWorkspaceRepository {
  FirestoreOwnerWorkspaceRepository(this.db);
  final FirebaseFirestore db;
  static const timeout = Duration(seconds: 15);

  @override
  Future<PlacePresentation> presentation(String placeId) async {
    final doc = await db
        .collection('placePresentations')
        .doc(placeId)
        .get(const GetOptions(source: Source.server))
        .timeout(timeout);
    final data = doc.data();
    return PlacePresentation(
      description: data?['description'] as String? ?? '',
      hours: data?['hours'] as String? ?? '',
    );
  }

  @override
  Future<void> save(String placeId, String uid, PlacePresentation value) async {
    if (value.description.length > 1000 || value.hours.length > 500) {
      throw ArgumentError('Apresentação ou horários acima do limite.');
    }
    // Rules revalidate the current owner at commit time, including revocations.
    await db
        .collection('placePresentations')
        .doc(placeId)
        .set({
          'description': value.description.trim(),
          'hours': value.hours.trim(),
          'updatedBy': uid,
          'updatedAt': FieldValue.serverTimestamp(),
        })
        .timeout(timeout);
  }

  @override
  Future<OwnerPlaceSummary> summary(String placeId) async {
    final reviews = db
        .collection('reviews')
        .where('placeId', isEqualTo: placeId);
    final counts = await Future.wait([
      reviews.count().get(),
      db
          .collection('ownerReplies')
          .where('placeId', isEqualTo: placeId)
          .count()
          .get(),
      for (final axis in ['food', 'ambience', 'service'])
        reviews
            .where(axis, isGreaterThan: 0)
            .aggregate(count(), sum(axis))
            .get(),
    ]).timeout(timeout);
    var total = 0.0;
    var samples = 0;
    for (var i = 0; i < 3; i++) {
      total += counts[i + 2].getSum(['food', 'ambience', 'service'][i]) ?? 0;
      samples += counts[i + 2].count ?? 0;
    }
    final reviewCount = counts[0].count!;
    return OwnerPlaceSummary(
      reviews: reviewCount,
      unanswered: math.max(0, reviewCount - counts[1].count!),
      rating: samples == 0 ? null : total / samples,
    );
  }
}
