import 'package:cloud_firestore/cloud_firestore.dart';

/// Log de auditoria (F04): `auditLog/{coleção}-{docId}`, uma entrada por
/// avaliação, visita ou relato criado pelo app. As Rules exigem a entrada no
/// MESMO batch que cria o doc auditado (e negam ler, alterar ou apagar).
const String auditLogCollection = 'auditLog';

/// Coleções auditadas. MESMA lista de `validAudit` em
/// `firebase/firestore.rules`.
const List<String> auditedCollections = ['reviews', 'visits', 'openReports'];

/// Id determinístico da entrada: `{coleção}-{docId}`. O retry de um batch
/// que não foi gravado reusa o mesmo id do doc, então a entrada também
/// continua a mesma (nunca duplica).
String auditLogId(String collection, String docId) => '$collection-$docId';

/// Adiciona ao [batch] a entrada de auditoria da criação de
/// `{collection}/{docId}` por [actorUid] no local [placeId]. Schema exato
/// validado pelas Rules; `at` é sempre a hora do servidor.
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
