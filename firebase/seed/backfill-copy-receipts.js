// Simula por padrão. --apply acrescenta provas sem apagar recibos ou alterar datas/créditos.
const { FieldPath, Timestamp } = require('firebase-admin/firestore');
const { firestoreFromEnv } = require('./seed');

async function backfillCopyReceipts({ db, apply = false, log = console.log } = {}) {
  if (!db) ({ db } = firestoreFromEnv());
  const result = { verified: 0, unverified: 0, unchanged: 0 };
  let cursor;
  while (true) {
    let query = db.collectionGroup('copies').orderBy(FieldPath.documentId()).limit(200);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    for (const receipt of page.docs) {
      const match = /^users\/([^/]+)\/lists\/([^/]+)\/copies\/([^/]+)$/.exec(receipt.ref.path);
      if (!match || typeof receipt.data().copiedListId === 'string') { result.unchanged++; continue; }
      const [, owner, source, copier] = match;
      if (owner === copier || Object.keys(receipt.data()).length !== 1 || !(receipt.data().createdAt instanceof Timestamp)) {
        result.unverified++; continue;
      }
      const copies = await db.collection(`users/${copier}/lists`)
        .where('copiedFromUid', '==', owner).where('copiedFromListId', '==', source).get();
      const target = copies.docs.find(d => d.data().createdAt instanceof Timestamp && /^[^/]{1,128}$/.test(d.id));
      if (!target) { result.unverified++; log(`Sem prova: ${receipt.ref.path}`); continue; }
      let verified = true;
      if (apply) {
        verified = await db.runTransaction(async tx => {
          const current = await tx.get(receipt.ref), actual = await tx.get(target.ref);
          const data = current.data(), copy = actual.data();
          if (!data || Object.keys(data).length !== 1 || !(data.createdAt instanceof Timestamp)
              || !copy || copy.copiedFromUid !== owner || copy.copiedFromListId !== source
              || !(copy.createdAt instanceof Timestamp)) return false;
          tx.update(receipt.ref, { copiedListId: target.id });
          return true;
        });
      }
      if (verified) { result.verified++; log(`${apply ? 'Verificado' : 'Verificável'}: ${receipt.ref.path}`); }
      else result.unchanged++;
    }
    if (page.size < 200) break;
    cursor = page.docs[page.docs.length - 1];
  }
  return result;
}
module.exports = { backfillCopyReceipts };
if (require.main === module) {
  const args = process.argv.slice(2);
  if (args.some(a => a !== '--apply' && a !== '--dry-run') || (args.includes('--apply') && args.includes('--dry-run'))) {
    console.error('Use --dry-run (padrão) ou --apply.'); process.exitCode = 1;
  } else {
    backfillCopyReceipts({ apply: args.includes('--apply') }).then(r => console.log(r)).catch(e => { console.error(e); process.exitCode = 1; });
  }
}
