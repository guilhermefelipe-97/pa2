import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/models/admin_ownership_request.dart';
import '../../domain/models/place.dart';
import '../repositories/admin_ownership_repository.dart';

class FirestoreAdminOwnershipRepository
    implements AdminOwnershipRepository, AdminHistoryRepository {
  FirestoreAdminOwnershipRepository(
    this.db, {
    this.decisionTimeout = const Duration(seconds: 25),
    this.reconciliationTimeout = const Duration(seconds: 10),
    this.accessSnapshots,
  });
  final Duration decisionTimeout, reconciliationTimeout;
  final Stream<DocumentSnapshot<Map<String, dynamic>>> Function(String uid)?
  accessSnapshots;
  final FirebaseFirestore db;
  final Set<String> _inFlight = {};
  static const server = GetOptions(source: Source.server);

  @override
  Stream<bool> observeAccess(String uid) =>
      (accessSnapshots?.call(uid) ??
              db.doc('admins/$uid').snapshots(includeMetadataChanges: true))
          .map(
            (s) =>
                !s.metadata.isFromCache &&
                !s.metadata.hasPendingWrites &&
                s.data()?['enabled'] == true,
          );

  Future<AdminOwnershipRequest> _parse(
    DocumentSnapshot<Map<String, dynamic>> s, {
    bool includeOwner = false,
  }) async {
    final parts = s.reference.path.split('/');
    if (parts.length != 4 || parts[0] != 'users') {
      throw StateError('Pedido inválido');
    }
    final uid = parts[1], placeId = parts[3];
    final user = await db.doc('users/$uid').get(server);
    final place = await db.doc('places/$placeId').get(server);
    if (!user.exists || !place.exists) {
      throw StateError('Perfil ou local indisponível');
    }
    final owner = includeOwner
        ? await db.doc('placeOwners/$placeId').get(server)
        : null;
    final d = s.data()!;
    return AdminOwnershipRequest(
      uid: uid,
      placeId: placeId,
      applicant: user.data()?['displayName'] as String? ?? uid,
      place: place.data()?['name'] as String? ?? placeId,
      location: Place(
        id: placeId,
        name: place.data()?['name'] as String? ?? placeId,
        category: place.data()?['category'] as String? ?? '',
        neighborhood: place.data()?['neighborhood'] as String? ?? '',
        city: place.data()?['city'] as String? ?? '',
        photoUrl: place.data()?['photoUrl'] as String?,
        photoAuthor: place.data()?['photoAuthor'] as String?,
        photoLicense: place.data()?['photoLicense'] as String?,
      ),
      createdAt: (d['createdAt'] as Timestamp).toDate(),
      status: d['status'] as String,
      reason: d['reason'] as String?,
      operator: d['operator'] as String?,
      decidedAt: (d['decidedAt'] as Timestamp?)?.toDate(),
      ownerUid: owner?.exists == true
          ? (owner?.data()?['uid'] as String? ?? 'identificador indisponível')
          : null,
    );
  }

  @override
  Future<AdminRequestPage> pending({Object? cursor}) async {
    return _page(false, cursor);
  }

  @override
  Future<AdminRequestPage> decided({Object? cursor}) => _page(true, cursor);

  Future<AdminRequestPage> _page(bool history, Object? cursor) async {
    var q = db
        .collectionGroup('ownershipRequests')
        .where(
          'status',
          whereIn: history ? ['approved', 'rejected', 'revoked'] : ['pending'],
        )
        .orderBy(history ? 'decidedAt' : 'createdAt', descending: history)
        .orderBy(FieldPath.documentId);
    if (cursor != null) q = q.startAfterDocument(cursor as DocumentSnapshot);
    final result = await q.limit(20).get(server);
    return AdminRequestPage(
      await Future.wait(
        result.docs.map((doc) async {
          try {
            return await _parse(doc).timeout(const Duration(seconds: 10));
          } on Object {
            final parts = doc.reference.path.split('/');
            return AdminOwnershipRequest(
              uid: parts.length == 4 ? parts[1] : doc.reference.path,
              placeId: doc.id,
              createdAt: DateTime.fromMillisecondsSinceEpoch(0),
              applicant: parts.length == 4 ? parts[1] : doc.reference.path,
              place: doc.id,
              available: false,
            );
          }
        }),
      ),
      result.docs.length == 20 ? result.docs.last : null,
    );
  }

  @override
  Future<AdminOwnershipRequest?> detail(String uid, String placeId) async {
    if (_inFlight.contains('$uid/$placeId')) throw const AdminUncertain();
    final s = await db.doc('users/$uid/ownershipRequests/$placeId').get(server);
    return s.exists ? _parse(s, includeOwner: true) : null;
  }

  @override
  Future<void> decide({
    required String operator,
    required String uid,
    required String placeId,
    required bool approve,
    required String reason,
  }) async {
    final key = '$uid/$placeId';
    if (!_inFlight.add(key)) throw const AdminUncertain();
    final operation = _decide(
      operator: operator,
      uid: uid,
      placeId: placeId,
      approve: approve,
      reason: reason,
    ).whenComplete(() => _inFlight.remove(key));
    try {
      await operation.timeout(decisionTimeout);
    } on TimeoutException {
      throw const AdminUncertain();
    }
  }

  Future<void> _decide({
    required String operator,
    required String uid,
    required String placeId,
    required bool approve,
    required String reason,
  }) async {
    final trimmed = reason.trim();
    if (operator == uid || trimmed.isEmpty || trimmed.length > 500) {
      throw ArgumentError('Motivo ou solicitante inválido');
    }
    final ref = db.doc('users/$uid/ownershipRequests/$placeId');
    final owner = db.doc('placeOwners/$placeId');
    try {
      await db.runTransaction((tx) async {
        final access = await tx.get(db.doc('admins/$operator'));
        final request = await tx.get(ref);
        final existingOwner = await tx.get(owner);
        final place = await tx.get(db.doc('places/$placeId'));
        if (access.data()?['enabled'] != true) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
          );
        }
        if (!request.exists ||
            request.data()?['status'] != 'pending' ||
            !place.exists ||
            (approve && existingOwner.exists)) {
          throw const AdminConflict();
        }
        final decision = {
          'operator': operator,
          'reason': trimmed,
          'decidedAt': FieldValue.serverTimestamp(),
        };
        if (approve) {
          tx.set(owner, {
            'uid': uid,
            'verifiedAt': FieldValue.serverTimestamp(),
          });
        }
        tx.update(ref, {
          ...decision,
          'status': approve ? 'approved' : 'rejected',
          approve ? 'approval' : 'rejection': decision,
        });
      }, timeout: const Duration(seconds: 15));
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') rethrow;

      try {
        final d = (await ref.get(server).timeout(reconciliationTimeout)).data();
        if (d?['status'] == (approve ? 'approved' : 'rejected') &&
            d?['operator'] == operator &&
            d?['reason'] == trimmed) {
          return;
        }
        if (d?['status'] != 'pending') throw const AdminConflict();
      } on TimeoutException {
        throw const AdminUncertain();
      } on FirebaseException {
        throw const AdminUncertain();
      }
      if (error.code == 'aborted') {
        throw const AdminConflict();
      }
      rethrow;
    }
  }
}
