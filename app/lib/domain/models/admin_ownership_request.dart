import 'place.dart';

class AdminOwnershipRequest {
  const AdminOwnershipRequest({
    required this.uid,
    required this.placeId,
    required this.createdAt,
    required this.applicant,
    required this.place,
    this.status = 'pending',
    this.reason,
    this.operator,
    this.decidedAt,
    this.ownerUid,
    this.available = true,
    this.location,
  });
  final String uid, placeId, applicant, place, status;
  final DateTime createdAt;
  final String? reason, operator, ownerUid;
  final DateTime? decidedAt;
  final bool available;
  final Place? location;
}

class AdminRequestPage {
  const AdminRequestPage(this.requests, this.cursor);
  final List<AdminOwnershipRequest> requests;
  final Object? cursor;
}
