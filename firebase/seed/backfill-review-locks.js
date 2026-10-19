// Backfill das travas do F03: para cada (autor, local) com avaliação, cria ou
// atualiza `users/{authorId}/reviewLocks/{placeId}` com `lastAt` = createdAt
// da avaliação mais recente e o `reviewId` dela. Assim avaliações anteriores
// ao F03 também contam para o período de 30 dias.
//
// Emulador (sem credenciais):
//   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 GCLOUD_PROJECT=demo-naarea npm run backfill:locks
//
// Produção (service account fora do git — mesmas variáveis do seed):
//   GOOGLE_APPLICATION_CREDENTIALS=/caminho/fora/do/repo/sa.json GCLOUD_PROJECT=<id> npm run backfill:locks
//
// `--dry-run` (ex.: `npm run backfill:locks -- --dry-run`) só lista o que
// mudaria. Idempotente: uma trava que já aponta para a avaliação mais recente
// (ou para uma mais nova, gravada pelo app) não é reescrita.
//
// Ordem de deploy (README do app): Rules + APK novo juntos, depois o backfill.
const { Timestamp } = require('firebase-admin/firestore');
const { firestoreFromEnv } = require('./seed');

const BATCH_LIMIT = 400;

/** Avaliação mais recente por (autor, local); docs fora do formato são ignorados. */
function latestByAuthorAndPlace(docs, log) {
  const latest = new Map();
  let skipped = 0;
  for (const d of docs) {
    const { authorId, placeId, createdAt } = d.data();
    const valid =
      typeof authorId === 'string' && authorId && !authorId.includes('/') &&
      typeof placeId === 'string' && placeId && !placeId.includes('/') &&
      createdAt instanceof Timestamp;
    if (!valid) {
      skipped++;
      log(`Ignorada (fora do formato): reviews/${d.id}`);
      continue;
    }
    const key = `${authorId}\u0000${placeId}`;
    const cur = latest.get(key);
    // Empate no createdAt: o maior id vence (determinístico entre execuções).
    if (!cur || createdAt.toMillis() > cur.createdAt.toMillis() ||
        (createdAt.toMillis() === cur.createdAt.toMillis() && d.id > cur.reviewId)) {
      latest.set(key, { authorId, placeId, createdAt, reviewId: d.id });
    }
  }
  return { latest: [...latest.values()], skipped };
}

/**
 * Cria/atualiza as travas. Sem `db`, usa o Firestore do ambiente.
 * Devolve `{ created, updated, unchanged, skipped }` (listas de caminhos nos
 * três primeiros; `skipped` = avaliações fora do formato).
 */
async function backfillReviewLocks({ db, dryRun = false, log = (m) => console.log(m) } = {}) {
  let label = 'Firestore informado';
  if (!db) ({ db, label } = firestoreFromEnv());

  const reviews = await db.collection('reviews').get();
  const { latest, skipped } = latestByAuthorAndPlace(reviews.docs, log);

  const refs = latest.map((l) => db.doc(`users/${l.authorId}/reviewLocks/${l.placeId}`));
  const existing = refs.length ? await db.getAll(...refs) : [];

  const created = [];
  const updated = [];
  const unchanged = [];
  const writes = [];
  latest.forEach((l, i) => {
    const snap = existing[i];
    const path = refs[i].path;
    if (snap.exists) {
      const cur = snap.data();
      const curAt = cur.lastAt instanceof Timestamp ? cur.lastAt.toMillis() : -Infinity;
      // Já aponta para a mais recente, ou o app gravou uma trava mais nova.
      if ((cur.reviewId === l.reviewId && curAt === l.createdAt.toMillis()) ||
          curAt > l.createdAt.toMillis()) {
        unchanged.push(path);
        return;
      }
      updated.push(path);
    } else {
      created.push(path);
    }
    writes.push({ ref: refs[i], data: { lastAt: l.createdAt, reviewId: l.reviewId, placeId: l.placeId } });
  });

  if (!dryRun) {
    for (let i = 0; i < writes.length; i += BATCH_LIMIT) {
      const batch = db.batch();
      for (const w of writes.slice(i, i + BATCH_LIMIT)) batch.set(w.ref, w.data);
      await batch.commit();
    }
  }

  log(
    `${dryRun ? '[dry-run] ' : ''}Backfill das travas em ${label}: ${reviews.size} avaliações, ` +
      `${latest.length} pares (autor, local); ${created.length} criadas, ${updated.length} atualizadas, ` +
      `${unchanged.length} sem mudança, ${skipped} ignoradas.`,
  );
  if (dryRun) for (const w of writes) log(`  ${w.ref.path} ← ${w.data.reviewId} (${w.data.lastAt.toDate().toISOString()})`);
  return { created, updated, unchanged, skipped };
}

module.exports = { backfillReviewLocks, latestByAuthorAndPlace };

if (require.main === module) {
  backfillReviewLocks({ dryRun: process.argv.includes('--dry-run') }).catch((err) => {
    console.error(err.message || err);
    process.exit(1);
  });
}
