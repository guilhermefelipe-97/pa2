const assert = require('node:assert/strict');
const { initializeApp, deleteApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { manageOwnership } = require('../seed/manage-ownership');

describe('decisões administrativas de titularidade (emulador)', function () {
  let app, db;
  before(function () {
    if (!process.env.FIRESTORE_EMULATOR_HOST) this.skip();
    app = initializeApp({ projectId: 'demo-naarea-ownership' }, 'ownership-test');
    db = getFirestore(app);
  });
  after(async () => { if (app) await deleteApp(app); });
  beforeEach(async () => {
    if (!db) return;
    for (const collection of ['users', 'placeOwners', 'places']) {
      await db.recursiveDelete(db.collection(collection));
    }
    await db.doc('places/local').set({ name: 'Local' });
    await db.doc('places/outro').set({ name: 'Outro' });
    for (const uid of ['alice', 'bob']) {
      await db.doc(`users/${uid}/ownershipRequests/local`).set({ status: 'pending', createdAt: FieldValue.serverTimestamp() });
    }
  });
  const decide = (action, uid = 'alice', placeId = 'local') => manageOwnership(db, {
    action, uid, placeId, operator: 'operador de teste', reason: 'Verificação externa simulada no emulador',
  });
  it('aprovação só após pedido pendente, com decisão registrada e timestamp do servidor', async () => {
    await decide('approve');
    const owner = (await db.doc('placeOwners/local').get()).data();
    assert.equal(owner.uid, 'alice');
    assert.ok(owner.verifiedAt.toDate());
    const request = (await db.doc('users/alice/ownershipRequests/local').get()).data();
    assert.equal(request.status, 'approved');
    assert.equal(request.operator, 'operador de teste');
    assert.ok(request.decidedAt.toDate());
    await assert.rejects(decide('approve', 'alice', 'outro'), /pendente/);
  });
  it('aprovações concorrentes não substituem o titular; vários locais por titular são possíveis', async () => {
    const results = await Promise.allSettled([decide('approve'), decide('approve', 'bob')]);
    assert.equal(results.filter((r) => r.status === 'fulfilled').length, 1);
    const uid = (await db.doc('placeOwners/local').get()).data().uid;
    await db.doc(`users/${uid}/ownershipRequests/outro`).set({ status: 'pending', createdAt: FieldValue.serverTimestamp() });
    await decide('approve', uid, 'outro');
    assert.equal((await db.doc('placeOwners/outro').get()).data().uid, uid);
  });
  it('rejeição não concede poderes e revogação exige o titular atual, preservando conteúdo antigo', async () => {
    await db.doc('reviews/antiga').set({ authorId: 'alice', placeId: 'local' });
    await decide('reject', 'bob');
    assert.equal((await db.doc('users/bob/ownershipRequests/local').get()).data().status, 'rejected');
    assert.equal((await db.doc('placeOwners/local').get()).exists, false);
    await decide('approve');
    const approved = (await db.doc('users/alice/ownershipRequests/local').get()).data();
    await assert.rejects(decide('revoke', 'bob'), /não corresponde/);
    await manageOwnership(db, { action: 'revoke', uid: 'alice', placeId: 'local', operator: 'outro operador', reason: 'Representação encerrada' });
    assert.equal((await db.doc('placeOwners/local').get()).exists, false);
    assert.equal((await db.doc('users/alice/ownershipRequests/local').get()).data().status, 'revoked');
    const revoked = (await db.doc('users/alice/ownershipRequests/local').get()).data();
    assert.equal(revoked.operator, approved.operator);
    assert.equal(revoked.reason, approved.reason);
    assert.ok(revoked.decidedAt.isEqual(approved.decidedAt));
    assert.deepEqual(revoked.approval, approved.approval);
    assert.equal(revoked.revocation.operator, 'outro operador');
    assert.equal(revoked.revocation.reason, 'Representação encerrada');
    assert.ok(revoked.revocation.decidedAt.toDate());
    assert.equal((await db.doc('reviews/antiga').get()).exists, true);
  });
  it('nega entrada inválida sem decisão nem motivo e local inexistente', async () => {
    await assert.rejects(manageOwnership(db, { action: 'approve', uid: 'alice', placeId: 'local' }), /Informe/);
    await assert.rejects(decide('approve', 'alice', 'missing'), /inexistente/);
  });
});
