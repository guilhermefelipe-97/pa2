// Seed da coleção `places`: locais curados (`places.json`) + snapshot do
// OpenStreetMap (`osm-natal.json`, gerado por `npm run import:osm`).
//
// Emulator (sem credenciais):
//   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 GCLOUD_PROJECT=demo-naarea npm run seed
//
// Produção (service account fora do git — ver .gitignore):
//   GOOGLE_APPLICATION_CREDENTIALS=/caminho/fora/do/repo/sa.json GCLOUD_PROJECT=<id> npm run seed
//
// O cliente nunca escreve em `places` (negado pelas Rules); só o Admin SDK, que
// ignora as Rules. Idempotente e offline: IDs fixos, documentos montados de
// forma determinística a partir dos dois arquivos, e só os documentos que
// mudaram são reescritos (`updatedAt` só muda quando o conteúdo muda).
// Os curados mantêm o id (reviews apontam para eles); quando casam com um
// único local do OSM pelo nome, recebem os dados dele e o duplicado não é criado.
const fs = require('node:fs');
const path = require('node:path');
const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { buildPlaceDocs } = require('./osm/match');

const SNAPSHOT = path.join(__dirname, 'osm-natal.json');

function loadSnapshot() {
  if (!fs.existsSync(SNAPSHOT)) {
    console.warn('osm-natal.json ausente: gravando só os locais curados (rode "npm run import:osm").');
    return undefined;
  }
  return JSON.parse(fs.readFileSync(SNAPSHOT, 'utf8'));
}

/** JSON com chaves ordenadas: compara documentos ignorando a ordem dos campos. */
function canonical(value) {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (value && typeof value === 'object') {
    return `{${Object.keys(value)
      .sort()
      .map((k) => `${JSON.stringify(k)}:${canonical(value[k])}`)
      .join(',')}}`;
  }
  return JSON.stringify(value);
}

/** Firestore do ambiente (emulador ou produção com service account). */
function firestoreFromEnv() {
  const projectId = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT;
  const usingEmulator = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
  if (!projectId) {
    throw new Error('Defina GCLOUD_PROJECT com o ID do projeto Firebase.');
  }
  if (!usingEmulator && !process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    throw new Error(
      'Produção exige GOOGLE_APPLICATION_CREDENTIALS apontando para a chave da ' +
        'service account (arquivo FORA do repositório).',
    );
  }
  initializeApp(usingEmulator ? { projectId } : { projectId, credential: applicationDefault() });
  const target = usingEmulator ? `emulator ${process.env.FIRESTORE_EMULATOR_HOST}` : 'produção';
  return { db: getFirestore(), label: `"${projectId}" (${target})` };
}

/**
 * Grava `places` a partir dos curados + snapshot. Sem `db`, usa o Firestore
 * do ambiente; `curated`/`snapshot` têm como padrão os arquivos versionados.
 * Devolve os ids gravados, quantos ficaram iguais e os órfãos mantidos.
 */
async function seedPlaces({
  db,
  curated = JSON.parse(fs.readFileSync(path.join(__dirname, 'places.json'), 'utf8')),
  snapshot = loadSnapshot(),
  log = (m) => console.log(m),
} = {}) {
  let label = 'Firestore informado';
  if (!db) ({ db, label } = firestoreFromEnv());

  const { docs, matched, ambiguous } = buildPlaceDocs(curated, snapshot, log);
  const col = db.collection('places');

  // O script (não o app) lê a coleção para saber o que mudou.
  const existing = new Map();
  for (const d of (await col.get()).docs) {
    const { updatedAt, ...data } = d.data();
    existing.set(d.id, canonical(data));
  }

  const changed = docs.filter(({ id, ...data }) => existing.get(id) !== canonical(data));

  // Um batch do Firestore aceita no máximo 500 escritas.
  const MAX_BATCH_WRITES = 500;
  for (let i = 0; i < changed.length; i += MAX_BATCH_WRITES) {
    const batch = db.batch();
    for (const { id, ...data } of changed.slice(i, i + MAX_BATCH_WRITES)) {
      // set sem merge: o documento fica exatamente igual à fonte.
      batch.set(col.doc(id), { ...data, updatedAt: FieldValue.serverTimestamp() });
    }
    await batch.commit();
  }

  const ids = new Set(docs.map((d) => d.id));
  const stale = [...existing.keys()].filter((id) => !ids.has(id)).sort();

  log(
    `Seed concluído em ${label}: ${docs.length} locais (${curated.length} curados, ` +
      `${matched} casados com o OSM, ${ambiguous.length} ambíguos), ${changed.length} gravados, ` +
      `${docs.length - changed.length} sem mudança.`,
  );
  if (stale.length) {
    log(
      `${stale.length} documento(s) em "places" não estão mais na fonte e foram mantidos ` +
        `(podem ter avaliações): ${stale.slice(0, 10).join(', ')}${stale.length > 10 ? '…' : ''}`,
    );
  }
  return { written: changed.map((d) => d.id), unchanged: docs.length - changed.length, stale };
}

module.exports = { seedPlaces };

if (require.main === module) {
  seedPlaces().catch((err) => {
    console.error(err.message || err);
    process.exit(1);
  });
}
