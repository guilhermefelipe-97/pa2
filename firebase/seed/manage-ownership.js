const { FieldValue } = require('firebase-admin/firestore');
const { firestoreFromEnv } = require('./seed');


async function manageOwnership(db, { action, uid, placeId, operator, reason }) {
  if (!['approve', 'reject', 'revoke'].includes(action) ||
      !uid || !placeId || !operator?.trim() || !reason?.trim() ||
      [uid, placeId].some((v) => v.includes('/'))) {
    throw new Error('Informe ação approve/reject/revoke, uid, placeId, operador e motivo.');
  }
  const requestRef = db.doc(`users/${uid}/ownershipRequests/${placeId}`);
  const ownerRef = db.doc(`placeOwners/${placeId}`);
  return db.runTransaction(async (tx) => {
    const [request, owner, place] = await Promise.all([
      tx.get(requestRef), tx.get(ownerRef), tx.get(db.doc(`places/${placeId}`)),
    ]);
    if (!place.exists) throw new Error('Local inexistente.');
    const decision = { operator: operator.trim(), reason: reason.trim(), decidedAt: FieldValue.serverTimestamp() };
    if (action === 'revoke') {
      if (!owner.exists || owner.data().uid !== uid) throw new Error('Titular informado não corresponde ao atual.');
      tx.delete(ownerRef);
      if (request.exists) tx.update(requestRef, { revocation: decision, status: 'revoked' });
      return;
    }
    if (!request.exists || request.data().status !== 'pending') throw new Error('Pedido pendente inexistente.');
    if (action === 'approve') {
      if (owner.exists && owner.data().uid !== uid) throw new Error('Outro titular já está verificado. Revogue explicitamente primeiro.');
      tx.set(ownerRef, { uid, verifiedAt: FieldValue.serverTimestamp() });
    }
    tx.update(requestRef, { ...decision, [action === 'approve' ? 'approval' : 'rejection']: decision, status: action === 'approve' ? 'approved' : 'rejected' });
  });
}

module.exports = { manageOwnership };
if (require.main === module) {
  const [action, uid, placeId, operator, ...reason] = process.argv.slice(2);
  const { db, label } = firestoreFromEnv();
  manageOwnership(db, { action, uid, placeId, operator, reason: reason.join(' ') })
    .then(() => console.log(`Decisão ${action} registrada em ${label}.`))
    .catch((e) => { console.error(e.message); process.exitCode = 1; });
}
