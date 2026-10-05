// Seed de `places` contra o emulador do Firestore (roda em `npm test` sob
// `firebase emulators:exec`). Projeto próprio para não colidir com os testes
// das Rules, que limpam `demo-naarea`.
const assert = require('node:assert/strict');
const path = require('node:path');
const { initializeApp, getApps, deleteApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const SEED_PATH = path.join(__dirname, '..', 'seed', 'seed.js');

const curated = [
  { id: 'mangai-natal', name: 'Mangai', category: 'Restaurante', neighborhood: 'Tirol', city: 'Natal', photoUrl: 'https://f/m.jpg' },
  { id: 'beco-da-lama', name: 'Beco da Lama', category: 'Bar', neighborhood: 'Cidade Alta', city: 'Natal' },
];
const snapshot = {
  places: [
    { id: 'osm-w1', osmId: 'way/1', name: 'Mangai', category: 'Comida regional', cuisine: 'Comida regional', neighborhood: 'Tirol', city: 'Natal', address: 'Av. Amintas Barros, 3300', lat: -5.8, lng: -35.2, geohash: '7nyyyx9d6' },
    { id: 'osm-n2', osmId: 'node/2', name: 'Bar do Zé', category: 'Bar', neighborhood: 'Rocas', city: 'Natal', openingHours: 'Mo-Su 16:00-02:00', lat: -5.77, lng: -35.2, geohash: '7nyyyz000' },
  ],
};

describe('seed de places (emulador)', function () {
  let app;
  let db;
  let seedPlaces;
  const quiet = () => {};

  before(function () {
    if (!process.env.FIRESTORE_EMULATOR_HOST) this.skip();
    app = initializeApp({ projectId: 'demo-naarea-seed' }, 'seed-test');
    db = getFirestore(app);
    ({ seedPlaces } = require(SEED_PATH));
  });

  after(async () => {
    if (app) await deleteApp(app);
  });

  beforeEach(async () => {
    if (!db) return;
    const docs = await db.collection('places').listDocuments();
    await Promise.all(docs.map((d) => d.delete()));
  });

  const run = (opts = {}) => seedPlaces({ db, curated, snapshot, log: quiet, ...opts });
  const updatedAt = async (id) => (await db.doc(`places/${id}`).get()).get('updatedAt');

  it('require("./seed") não executa nada', () => {
    delete require.cache[require.resolve(SEED_PATH)];
    const appsBefore = getApps().length;
    const mod = require(SEED_PATH);
    assert.equal(typeof mod.seedPlaces, 'function');
    assert.equal(getApps().length, appsBefore, 'nenhum app do Firebase inicializado');
  });

  it('1ª execução grava tudo; a 2ª não escreve nada e mantém updatedAt', async () => {
    const first = await run();
    assert.deepEqual(first.written, ['beco-da-lama', 'mangai-natal', 'osm-n2']);
    const before = await updatedAt('mangai-natal');
    assert.ok(before, 'updatedAt gravado');

    const second = await run();
    assert.deepEqual(second.written, []);
    assert.equal(second.unchanged, 3);
    assert.ok((await updatedAt('mangai-natal')).isEqual(before));
    // Curado casado com o OSM: id mantido e sem doc duplicado.
    assert.equal((await db.doc('places/osm-w1').get()).exists, false);
    assert.equal((await db.doc('places/mangai-natal').get()).get('osmId'), 'way/1');
  });

  it('mudança de um campo regrava só aquele doc', async () => {
    await run();
    const becoBefore = await updatedAt('beco-da-lama');
    const zeBefore = await updatedAt('osm-n2');
    const changed = curated.map((c) => (c.id === 'mangai-natal' ? { ...c, category: 'Comida regional' } : c));
    const r = await run({ curated: changed });
    assert.deepEqual(r.written, ['mangai-natal']);
    assert.equal((await db.doc('places/mangai-natal').get()).get('category'), 'Comida regional');
    assert.ok((await updatedAt('beco-da-lama')).isEqual(becoBefore));
    assert.ok((await updatedAt('osm-n2')).isEqual(zeBefore));
  });

  it('campo removido da fonte some do documento', async () => {
    await run();
    const semFoto = curated.map((c) => {
      if (c.id !== 'mangai-natal') return c;
      const { photoUrl, ...rest } = c;
      return rest;
    });
    const r = await run({ curated: semFoto });
    assert.deepEqual(r.written, ['mangai-natal']);
    const data = (await db.doc('places/mangai-natal').get()).data();
    assert.equal('photoUrl' in data, false);
  });

  it('documento fora da fonte é mantido e listado como órfão', async () => {
    await run();
    const r = await run({ snapshot: { places: [] } });
    assert.deepEqual(r.stale, ['osm-n2']);
    assert.equal((await db.doc('places/osm-n2').get()).exists, true);
  });
});
