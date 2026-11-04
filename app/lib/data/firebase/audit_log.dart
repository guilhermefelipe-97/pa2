import 'package:cloud_firestore/cloud_firestore.dart';

const String auditLogCollection = 'auditLog';

const List<String> auditedCollections = [
  'reviews',
  'visits',
  'openReports',
  'queueReports',
  'ownerReplies',
];

String auditLogId(String collection, String docId) => '$collection-$docId';

void addAuditEntry(
  WriteBatch batch,
  FirebaseFirestore db, {
  required String collection,
  required String docId,
  required String actorUid,
  required String placeId,
}) {
  assert(auditedCollections.contains(collection), 'coleção não auditada');
  batch.set(
    db.collection(auditLogCollection).doc(auditLogId(collection, docId)),
    {
      'actorUid': actorUid,
      'action': 'create',
      'collection': collection,
      'docId': docId,
      'placeId': placeId,
      'at': FieldValue.serverTimestamp(),
    },
  );
}
