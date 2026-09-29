// Seed da coleção `places` com locais de Natal/RN.
//
// Emulator (sem credenciais):
//   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 GCLOUD_PROJECT=demo-naarea npm run seed
//
// Produção (service account fora do git — ver .gitignore):
//   GOOGLE_APPLICATION_CREDENTIALS=/caminho/fora/do/repo/sa.json GCLOUD_PROJECT=<id> npm run seed
//
// O cliente nunca escreve em `places` (negado pelas Rules); só o Admin SDK, que
// ignora as Rules. O script é idempotente: IDs fixos + set() com merge.
const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const places = require('./places.json');

async function main() {
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
  const db = getFirestore();

  // Um batch do Firestore aceita no máximo 500 escritas.
  const MAX_BATCH_WRITES = 500;
  for (let i = 0; i < places.length; i += MAX_BATCH_WRITES) {
    const batch = db.batch();
    for (const p of places.slice(i, i + MAX_BATCH_WRITES)) {
      const { id, ...data } = p;
      batch.set(
        db.collection('places').doc(id),
        { ...data, updatedAt: FieldValue.serverTimestamp() },
        { merge: true },
      );
    }
    await batch.commit();
  }

  console.log(
    `Seed concluído: ${places.length} locais em "${projectId}"` +
      (usingEmulator ? ` (emulator ${process.env.FIRESTORE_EMULATOR_HOST})` : ' (produção)'),
  );
}

main().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
