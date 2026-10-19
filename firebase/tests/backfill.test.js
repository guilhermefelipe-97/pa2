// Backfill das travas do F03 contra o emulador (roda em `npm test` sob
// `firebase emulators:exec`). Projeto próprio para não colidir com os testes
// das Rules, que limpam `demo-naarea`.
const assert = require('node:assert/strict');
const path = require('node:path');
const { initializeApp, getApps, deleteApp } = require('firebase-admin/app');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');

const SCRIPT = path.join(__dirname, '..', 'seed', 'backfill-review-locks.js');

const at = (iso) => Timestamp.fromDate(new Date(iso));

describe('backfill das travas do F03 (emulador)', function () {
  let app;
  let db;
  let backfillReviewLocks;
  const quiet = () => {};

  before(function () {
    if (!process.env.FIRESTORE_EMULATOR_HOST) this.skip();
    app = initializeApp({ projectId: 'demo-naarea-backfill' }, 'backfill-test');
    db = getFirestore(app);
    ({ backfillReviewLocks } = require(SCRIPT));
  });

  after(async () => {
    if (app) await deleteApp(app);
  });

  beforeEach(async () => {
    if (!db) return;
    await db.recursiveDelete(db.collection('reviews'));
    await db.recursiveDelete(db.collection('users'));
    const add = (id, authorId, placeId, iso) =>
      db.doc(`reviews/${id}`).set({ authorId, placeId, createdAt: at(iso), food: 4 });
    await add('a-old', 'alice', 'mangai', '2026-08-01T12:00:00Z');
    await add('a-new', 'alice', 'mangai', '2026-09-20T12:00:00Z');
    await add('a-cam', 'alice', 'camaroes', '2026-09-01T12:00:00Z');
    await add('b-man', 'bob', 'mangai', '2026-09-05T12:00:00Z');
    await db.doc('reviews/torta').set({ authorId: 'x', placeId: 'y' }); // sem createdAt
  });

  const run = (opts = {}) => backfillReviewLocks({ db, log: quiet, ...opts });
  const lock = async (uid, placeId) => (await db.doc(`users/${uid}/reviewLocks/${placeId}`).get()).data();

  it('require do script não executa nada', () => {
    delete require.cache[require.resolve(SCRIPT)];
    const before = getApps().length;
    require(SCRIPT);
    assert.equal(getApps().length, before);
  });

  it('cria uma trava por (autor, local) com a avaliação mais recente', async () => {
    const r = await run();
    assert.equal(r.created.length, 3);
    assert.equal(r.skipped, 1);
    const a = await lock('alice', 'mangai');
    assert.deepEqual(Object.keys(a).sort(), ['lastAt', 'placeId', 'reviewId']);
    assert.equal(a.reviewId, 'a-new');
    assert.equal(a.placeId, 'mangai');
    assert.equal(a.lastAt.toDate().toISOString(), '2026-09-20T12:00:00.000Z');
    assert.equal((await lock('alice', 'camaroes')).reviewId, 'a-cam');
    assert.equal((await lock('bob', 'mangai')).reviewId, 'b-man');
  });

  it('idempotente: a 2ª execução não escreve nada', async () => {
    await run();
    const r = await run();
    assert.deepEqual(r.created, []);
    assert.deepEqual(r.updated, []);
    assert.equal(r.unchanged.length, 3);
  });

  it('atualiza trava velha; não rebaixa trava mais nova gravada pelo app', async () => {
    await db.doc('users/alice/reviewLocks/mangai').set({ lastAt: at('2026-08-01T12:00:00Z'), reviewId: 'a-old', placeId: 'mangai' });
    await db.doc('users/bob/reviewLocks/mangai').set({ lastAt: at('2026-10-01T12:00:00Z'), reviewId: 'b-app', placeId: 'mangai' });
    const r = await run();
    assert.deepEqual(r.updated, ['users/alice/reviewLocks/mangai']);
    assert.ok(r.unchanged.includes('users/bob/reviewLocks/mangai'));
    assert.equal((await lock('alice', 'mangai')).reviewId, 'a-new');
    assert.equal((await lock('bob', 'mangai')).reviewId, 'b-app');
  });

  it('--dry-run só relata', async () => {
    const r = await run({ dryRun: true });
    assert.equal(r.created.length, 3);
    assert.equal(await lock('alice', 'mangai'), undefined);
  });
});
