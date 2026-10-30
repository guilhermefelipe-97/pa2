import '../../domain/models/admin_ownership_request.dart';

abstract class AdminOwnershipRepository {
  Stream<bool> observeAccess(String uid);
  Future<AdminRequestPage> pending({Object? cursor});
  Future<AdminOwnershipRequest?> detail(String uid, String placeId);
  Future<void> decide({
    required String operator,
    required String uid,
    required String placeId,
    required bool approve,
    required String reason,
  });
}

class AdminConflict implements Exception {
  const AdminConflict();
}

class AdminUncertain implements Exception {
  const AdminUncertain();
}
