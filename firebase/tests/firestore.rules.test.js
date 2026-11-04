
const fs = require('node:fs');
const path = require('node:path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  deleteDoc,
  addDoc,
  collection,
  serverTimestamp,
  Timestamp,
  query,
  where,
  orderBy,
  limit,
  getDocs,
  collectionGroup,
  documentId,
  startAfter,
  arrayUnion,
  arrayRemove,
  writeBatch,
  Bytes,
  getCountFromServer,
  getAggregateFromServer,
  count: aggregateCount,
  sum: aggregateSum,
} = require('firebase/firestore');

const PROJECT_ID = 'demo-naarea';
let env;

function emulatorHost() {
  const raw = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
  const idx = raw.lastIndexOf(':');
  return { host: raw.slice(0, idx), port: Number(raw.slice(idx + 1)) };
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      ...emulatorHost(),
      rules: fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8'),
    },
  });
});

after(async () => {
  if (env) await env.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users/alice'), { displayName: 'Alice', displayNameLower: 'alice' });
    await setDoc(doc(db, 'users/bob'), { displayName: 'Bob', displayNameLower: 'bob' });
    await setDoc(doc(db, 'places/camaroes'), {
      name: 'Camarões Potiguar',
      category: 'Restaurante',
      neighborhood: 'Ponta Negra',
      city: 'Natal',
    });
    await setDoc(doc(db, 'reviews/existing'), {
      authorId: 'alice',
      authorName: 'Alice',
      placeId: 'camaroes',
      placeName: 'Camarões Potiguar',
      food: 4,
      ambience: 4,
      service: 4,
      companion: null,
      comment: null,
      hasPhoto: false,
      createdAt: Timestamp.now(),
    });
  });
});

const alice = () => env.authenticatedContext('alice').firestore();

describe('apresentação pública do estabelecimento', () => {
  const value = (extra = {}) => ({description: 'Cozinha local.', hours: 'Terça a domingo, 12h–22h.', updatedBy: 'alice', updatedAt: serverTimestamp(), ...extra});
  const grant = async (uid = 'alice') => env.withSecurityRulesDisabled(async ctx => {
    await setDoc(doc(ctx.firestore(), 'placeOwners/camaroes'), {uid, verifiedAt: Timestamp.now()});
  });
  it('titular atual cria e atualiza; usuário autenticado lê', async () => {
    await grant(); const ref = doc(alice(), 'placePresentations/camaroes');
    await assertSucceeds(setDoc(ref, value()));
    await assertSucceeds(setDoc(ref, value({description: '', hours: ''})));
    await assertSucceeds(getDoc(doc(env.authenticatedContext('bob').firestore(), 'placePresentations/camaroes')));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'placePresentations/camaroes')));
  });
  it('pedido pendente e revogação não permitem editar', async () => {
    await env.withSecurityRulesDisabled(async ctx => setDoc(doc(ctx.firestore(), 'users/alice/ownershipRequests/camaroes'), {status: 'pending'}));
    const ref = doc(alice(), 'placePresentations/camaroes');
    await assertFails(setDoc(ref, value()));
    await grant(); await assertSucceeds(setDoc(ref, value()));
    await grant('bob'); await assertFails(setDoc(ref, value({description: 'Não autorizado'})));
  });
  it('rejeita excesso, identidade forjada, timestamp falso, campos extras e exclusão', async () => {
    await grant(); const ref = doc(alice(), 'placePresentations/camaroes');
    for (const extra of [{description: 'x'.repeat(1001)}, {hours: 'x'.repeat(501)}, {description: 5}, {hours: null},
      {updatedBy: 'bob'}, {updatedAt: Timestamp.fromMillis(0)}, {name: 'Outro nome'}, {promoted: true}]) {
      await assertFails(setDoc(ref, value(extra)));
    }
    await assertSucceeds(setDoc(ref, value({description: 'x'.repeat(1000), hours: 'x'.repeat(500)})));
    await assertFails(deleteDoc(ref));
    await assertFails(setDoc(doc(alice(), 'placePresentations/inexistente'), value()));
  });
  it('agregações consideram mais de 20 avaliações, eixos parciais e respostas de titular anterior', async () => {
    await env.withSecurityRulesDisabled(async ctx => {
      const db = ctx.firestore(); const batch = writeBatch(db);
      batch.delete(doc(db, 'reviews/existing'));
      for (let i = 0; i < 27; i++) batch.set(doc(db, `reviews/painel-${i}`), {
        placeId: 'camaroes', food: 5, ambience: i < 3 ? 3 : null, service: null,
      });
      for (let i = 0; i < 4; i++) batch.set(doc(db, `ownerReplies/painel-${i}`), {placeId: 'camaroes', authorId: 'titular-anterior'});
      await batch.commit();
    });
    const db = alice();
    const reviews = query(collection(db, 'reviews'), where('placeId', '==', 'camaroes'));
    const total = (await assertSucceeds(getCountFromServer(reviews))).data().count;
    const replies = (await assertSucceeds(getCountFromServer(query(collection(db, 'ownerReplies'), where('placeId', '==', 'camaroes'))))).data().count;
    if (total - replies !== 23) throw new Error('Pendências incorretas');
    let notes = 0, samples = 0;
    for (const axis of ['food', 'ambience', 'service']) {
      const result = (await assertSucceeds(getAggregateFromServer(query(reviews, where(axis, '>', 0)), {samples: aggregateCount(), total: aggregateSum(axis)}))).data();
      notes += result.total; samples += result.samples;
    }
    if (notes !== 144 || samples !== 30 || notes / samples !== 4.8) throw new Error('Média incorreta');
  });
});

describe('edição do perfil e @usuário',()=>{
  const claim=async(db,uid,handle,extra={})=>{
    const batch=writeBatch(db);
    batch.set(doc(db,`usernames/${handle}`),{uid});
    batch.update(doc(db,`users/${uid}`),{username:handle,bio:'Cafés e viagens.',city:'Natal',...extra});
    return batch.commit();
  };
  it('reserva @ e salva bio sem expor email ou senha no perfil público',async()=>{
    await assertSucceeds(claim(alice(),'alice','alice.cafes'));
    await assertFails(updateDoc(doc(alice(),'users/alice'),{email:'privado@exemplo.com'}));
    await assertFails(updateDoc(doc(alice(),'users/alice'),{password:'segredo'}));
    await assertSucceeds(getDoc(doc(bob(),'users/alice')));
    await assertFails(updateDoc(doc(bob(),'users/alice'),{bio:'Alterado por outro usuário'}));
  });
  it('não rouba @ ocupado nem grava perfil sem reserva correspondente',async()=>{
    await assertSucceeds(claim(alice(),'alice','alice.cafes'));
    await assertFails(claim(bob(),'bob','alice.cafes'));
    await assertFails(updateDoc(doc(bob(),'users/bob'),{username:'sem.reserva'}));
    await assertFails(setDoc(doc(bob(),'usernames/orfao'),{uid:'bob'}));
  });
  it('troca @ liberando o anterior no mesmo lote e permite editar bio depois',async()=>{
    const db=alice();
    await assertSucceeds(claim(db,'alice','alice.cafes'));
    await assertFails(claim(db,'alice','alice.viagens'));
    const batch=writeBatch(db);
    batch.set(doc(db,'usernames/alice.viagens'),{uid:'alice'});
    batch.update(doc(db,'users/alice'),{username:'alice.viagens'});
    batch.delete(doc(db,'usernames/alice.cafes'));
    await assertSucceeds(batch.commit());
    await assertSucceeds(updateDoc(doc(db,'users/alice'),{bio:'Nova bio.'}));
    await assertFails(deleteDoc(doc(db,'usernames/alice.viagens')));
  });
  it('Instagram opcional só aceita usuário válido e edição pelo dono', async () => {
    const ref = doc(alice(), 'users/alice');
    await assertSucceeds(updateDoc(ref, {instagram: 'alice.cafes_97'}));
    for (const instagram of ['https://instagram.com/alice', '@alice', 'x'.repeat(31), 123, null]) {
      await assertFails(updateDoc(ref, {instagram}));
    }
    await assertFails(updateDoc(doc(bob(), 'users/alice'), {instagram: 'bob'}));
    await assertSucceeds(updateDoc(ref, {instagram: ''}));
  });
  it('valida formato, bio, cidade e nomes',async()=>{
    for(const handle of ['ab','AlicE','com espaço','x'.repeat(25)])await assertFails(claim(alice(),'alice',handle));
    await assertFails(updateDoc(doc(alice(),'users/alice'),{bio:'x'.repeat(241)}));
    await assertFails(updateDoc(doc(alice(),'users/alice'),{city:'x'.repeat(81)}));
    await assertFails(updateDoc(doc(alice(),'users/alice'),{username:33}));
  });
  it('foto e capa públicas, alteráveis somente pelo dono e sem campos arbitrários',async()=>{
    const jpeg=Bytes.fromUint8Array(new Uint8Array([255,216,255,217]));
    const db=alice();
    await assertSucceeds(setDoc(doc(db,'users/alice/media/avatar'),{jpeg}));
    await assertSucceeds(setDoc(doc(db,'users/alice/media/cover'),{jpeg}));
    await assertSucceeds(getDoc(doc(bob(),'users/alice/media/avatar')));
    await assertFails(setDoc(doc(bob(),'users/alice/media/cover'),{jpeg}));
    await assertFails(setDoc(doc(db,'users/alice/media/privado'),{jpeg}));
    await assertFails(setDoc(doc(db,'users/alice/media/cover'),{jpeg,extra:true}));
    await assertFails(setDoc(doc(db,'users/alice/media/cover'),{jpeg:Bytes.fromUint8Array(new Uint8Array(150001))}));
    await assertSucceeds(deleteDoc(doc(db,'users/alice/media/cover')));
  });
});

describe('galeria de capa do estabelecimento', () => {
  const photo = (overrides = {}) => ({
    authorId: 'alice', authorName: 'Alice', createdAt: serverTimestamp(),
    jpeg: Bytes.fromUint8Array(new Uint8Array([255,216,255,217])), ...overrides,
  });
  it('salva várias fotos e permite ler a galeria autenticada', async () => {
    const db = alice();
    const batch = writeBatch(db);
    batch.set(doc(db,'places/camaroes/photos/a'),photo());
    batch.set(doc(db,'places/camaroes/photos/b'),photo());
    await assertSucceeds(batch.commit());
    const other = env.authenticatedContext('bob').firestore();
    await assertSucceeds(getDocs(query(collection(other,'places/camaroes/photos'),orderBy('createdAt','desc'),limit(20))));
  });
  it('nega autoria e nome forjados, campos extras, data adulterada e lugar inexistente', async () => {
    const db=alice();
    for (const change of [{authorId:'bob'},{authorName:'Outro'}, {extra:true}, {createdAt:Timestamp.fromMillis(1)}]) {
      await assertFails(setDoc(doc(db,'places/camaroes/photos/bad'),photo(change)));
    }
    await assertFails(setDoc(doc(db,'places/inexistente/photos/a'),photo()));
  });
  it('nega foto vazia, tamanho acima de 150000 bytes e leitura anônima', async () => {
    const db=alice();
    for (const length of [0,150001]) {
      await assertFails(setDoc(doc(db,'places/camaroes/photos/bad'),photo({jpeg:Bytes.fromUint8Array(new Uint8Array(length))})));
    }
    await assertFails(getDocs(collection(env.unauthenticatedContext().firestore(),'places/camaroes/photos')));
  });
  it('somente a autora remove a foto e nenhuma conta a altera', async () => {
    const db=alice();
    await assertSucceeds(setDoc(doc(db,'places/camaroes/photos/a'),photo()));
    await assertFails(updateDoc(doc(db,'places/camaroes/photos/a'),{authorName:'Alice 2'}));
    const other=env.authenticatedContext('bob').firestore();
    await assertFails(deleteDoc(doc(other,'places/camaroes/photos/a')));
    await assertSucceeds(deleteDoc(doc(db,'places/camaroes/photos/a')));
  });
  it('um lote com foto inválida não grava parcialmente a galeria', async () => {
    const db=alice();
    const batch=writeBatch(db);
    batch.set(doc(db,'places/camaroes/photos/a'),photo());
    batch.set(doc(db,'places/camaroes/photos/b'),photo({authorId:'bob'}));
    await assertFails(batch.commit());
    const snap=await getDoc(doc(db,'places/camaroes/photos/a'));
    require('node:assert/strict').equal(snap.exists(),false);
  });
});
const bob = () => env.authenticatedContext('bob').firestore();
const anon = () => env.unauthenticatedContext().firestore();

function validReview(overrides = {}) {
  return {
    authorId: 'alice',
    authorName: 'Alice',
    placeId: 'camaroes',
    placeName: 'Camarões Potiguar',
    food: 5,
    ambience: 4,
    service: 3,
    companion: 'amigos',
    comment: null,
    hasPhoto: false,
    createdAt: serverTimestamp(),
    ...overrides,
  };
}


function jpegBytes(n) {
  const arr = new Uint8Array(n);
  if (n > 0) arr[0] = 0xff;
  if (n > 1) arr[1] = 0xd8;
  if (n > 2) arr[2] = 0xff;
  return Bytes.fromUint8Array(arr);
}

function validPhoto(overrides = {}) {
  return {
    authorId: 'alice',
    jpeg: jpegBytes(1000),
    createdAt: serverTimestamp(),
    ...overrides,
  };
}



function validLock(reviewId, overrides = {}) {
  return {
    lastAt: serverTimestamp(),
    reviewId,
    placeId: 'camaroes',
    ...overrides,
  };
}

const lockPath = (uid, placeId) => 'users/' + uid + '/reviewLocks/' + placeId;


const auditPath = (collectionName, docId) => 'auditLog/' + collectionName + '-' + docId;


function validAudit(collectionName, docId, overrides = {}) {
  return {
    actorUid: 'alice',
    action: 'create',
    collection: collectionName,
    docId,
    placeId: 'camaroes',
    at: serverTimestamp(),
    ...overrides,
  };
}



function setAudit(db, batch, collectionName, docId, data, overrides = {}) {
  batch.set(
    doc(db, auditPath(collectionName, docId)),
    validAudit(collectionName, docId, {
      actorUid: typeof data.authorId === 'string' ? data.authorId : 'alice',
      placeId: typeof data.placeId === 'string' ? data.placeId : 'camaroes',
      ...overrides,
    }),
  );
}

let reviewSeq = 0;






function addReview(db, data, { id, lock = {}, lockAt, audit = {} } = {}) {
  const reviewId = id || 'r' + (++reviewSeq);
  const batch = writeBatch(db);
  batch.set(doc(db, 'reviews/' + reviewId), data);
  if (lock !== false) {
    const placeId = typeof data.placeId === 'string' ? data.placeId : 'camaroes';
    batch.set(
      doc(db, lockAt || lockPath(data.authorId, placeId)),
      validLock(reviewId, { placeId, ...lock }),
    );
  }
  if (audit !== false) setAudit(db, batch, 'reviews', reviewId, data, audit);
  return batch.commit();
}


async function unlockAll() {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const snap = await getDocs(collectionGroup(ctx.firestore(), 'reviewLocks'));
    await Promise.all(snap.docs.map((d) => deleteDoc(d.ref)));
  });
}



async function freshReview(db, data, opts) {
  await unlockAll();
  return addReview(db, data, opts);
}


async function seedLock(uid, placeId, daysAgo, reviewId = 'existing') {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), lockPath(uid, placeId)), {
      lastAt: Timestamp.fromMillis(Date.now() - daysAgo * 24 * 60 * 60 * 1000),
      reviewId,
      placeId,
    });
  });
}



async function reviewWithPhotoBatch(db, { id = 'nova', review = {}, photo = {}, withReview = true, withPhoto = true, withLock = true, withAudit = true } = {}) {
  await unlockAll();
  const batch = writeBatch(db);
  const data = validReview({ hasPhoto: true, ...review });
  if (withReview) batch.set(doc(db, 'reviews/' + id), data);
  if (withPhoto) batch.set(doc(db, 'reviewPhotos/' + id), validPhoto(photo));
  if (withLock) batch.set(doc(db, lockPath(data.authorId, data.placeId)), validLock(id, { placeId: data.placeId }));
  if (withAudit) setAudit(db, batch, 'reviews', id, data);
  return batch.commit();
}

describe('users/{uid}', () => {
  it('dono cria o próprio perfil com nome', async () => {
    const db = env.authenticatedContext('carol').firestore();
    await assertSucceeds(setDoc(doc(db, 'users/carol'), { displayName: 'Carol', displayNameLower: 'carol' }));
  });

  it('não cria perfil de outro uid', async () => {
    await assertFails(setDoc(doc(alice(), 'users/carol'), { displayName: 'Carol', displayNameLower: 'carol' }));
  });

  it('não aceita nome vazio ou só espaços', async () => {
    const db = env.authenticatedContext('carol').firestore();
    await assertFails(setDoc(doc(db, 'users/carol'), { displayName: '', displayNameLower: '' }));
    await assertFails(setDoc(doc(db, 'users/carol'), { displayName: '   ', displayNameLower: '   ' }));
  });

  it('não aceita nome com espaços nas pontas nem displayNameLower divergente', async () => {
    const db = env.authenticatedContext('carol').firestore();
    await assertFails(setDoc(doc(db, 'users/carol'), { displayName: ' Carol', displayNameLower: ' carol' }));
    await assertFails(setDoc(doc(db, 'users/carol'), { displayName: 'Carol', displayNameLower: 'outra' }));
  });

  it('não aceita campos extras nem displayName ausente', async () => {
    const db = env.authenticatedContext('carol').firestore();
    await assertFails(setDoc(doc(db, 'users/carol'), { displayName: 'Carol', displayNameLower: 'carol', admin: true }));
    await assertFails(setDoc(doc(db, 'users/carol'), { displayNameLower: 'carol' }));
  });

  it('anônimo não lê; logado lê perfis (busca de pessoas)', async () => {
    await assertFails(getDoc(doc(anon(), 'users/alice')));
    await assertSucceeds(getDoc(doc(bob(), 'users/alice')));
  });

  it('dono renomeia o perfil; nomes históricos permanecem ligados ao mesmo uid', async () => {
    await assertSucceeds(updateDoc(doc(alice(), 'users/alice'), { displayName: 'Alice S', displayNameLower: 'alice s' }));
    require('node:assert/strict').equal((await getDoc(doc(alice(),'reviews/existing'))).data().authorName,'Alice');
    await assertFails(updateDoc(doc(alice(), 'users/alice'), { displayNameLower: 'outra' }));
    await assertFails(updateDoc(doc(alice(), 'users/alice'), { displayName: ' ', displayNameLower: ' ' }));
  });

  it('nome acima de 60 caracteres é negado', async () => {
    const db = env.authenticatedContext('carol').firestore();
    const long = 'a'.repeat(61);
    await assertFails(setDoc(doc(db, 'users/carol'), { displayName: long, displayNameLower: long }));
    const max = 'a'.repeat(60);
    await assertSucceeds(setDoc(doc(db, 'users/carol'), { displayName: max, displayNameLower: max }));
  });

  it('outro usuário não altera meu perfil; ninguém exclui', async () => {
    await assertFails(updateDoc(doc(bob(), 'users/alice'), { displayName: 'Hack', displayNameLower: 'hack' }));
    await assertFails(deleteDoc(doc(alice(), 'users/alice')));
  });
});

describe('users/{uid}/following/{target}', () => {
  it('dono segue alguém', async () => {
    await assertSucceeds(setDoc(doc(alice(), 'users/alice/following/bob'), { createdAt: serverTimestamp() }));
  });

  it('outro usuário não escreve no meu following', async () => {
    await assertFails(setDoc(doc(bob(), 'users/alice/following/bob'), { createdAt: serverTimestamp() }));
  });

  it('não segue usuário inexistente', async () => {
    await assertFails(setDoc(doc(alice(), 'users/alice/following/fantasma'), { createdAt: serverTimestamp() }));
  });

  it('não segue a si mesmo', async () => {
    await assertFails(setDoc(doc(alice(), 'users/alice/following/alice'), { createdAt: serverTimestamp() }));
  });

  it('não aceita createdAt do cliente nem campos extras', async () => {
    await assertFails(setDoc(doc(alice(), 'users/alice/following/bob'), { createdAt: Timestamp.fromMillis(0) }));
    await assertFails(setDoc(doc(alice(), 'users/alice/following/bob'), { createdAt: serverTimestamp(), x: 1 }));
  });

  it('só o dono lê e deixa de seguir', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/alice/following/bob'), { createdAt: Timestamp.now() });
    });
    await assertSucceeds(getDoc(doc(alice(), 'users/alice/following/bob')));
    await assertFails(getDoc(doc(bob(), 'users/alice/following/bob')));
    await assertFails(deleteDoc(doc(bob(), 'users/alice/following/bob')));
    await assertSucceeds(deleteDoc(doc(alice(), 'users/alice/following/bob')));
  });
});

describe('users/{uid}/saved/{placeId} (Quero ir)', () => {
  it('dono salva local existente com createdAt do servidor', async () => {
    await assertSucceeds(setDoc(doc(alice(), 'users/alice/saved/camaroes'), { createdAt: serverTimestamp() }));
  });

  it('outro usuário não salva no meu Quero ir', async () => {
    await assertFails(setDoc(doc(bob(), 'users/alice/saved/camaroes'), { createdAt: serverTimestamp() }));
  });

  it('anônimo não salva', async () => {
    await assertFails(setDoc(doc(anon(), 'users/alice/saved/camaroes'), { createdAt: serverTimestamp() }));
  });

  it('não salva local inexistente', async () => {
    await assertFails(setDoc(doc(alice(), 'users/alice/saved/fantasma'), { createdAt: serverTimestamp() }));
  });

  it('só aceita createdAt (sem campos extras, sem nota privada)', async () => {
    await assertFails(setDoc(doc(alice(), 'users/alice/saved/camaroes'), { createdAt: serverTimestamp(), note: 'sábado' }));
    await assertFails(setDoc(doc(alice(), 'users/alice/saved/camaroes'), { createdAt: serverTimestamp(), list: 'x' }));
    await assertFails(setDoc(doc(alice(), 'users/alice/saved/camaroes'), {}));
  });

  it('createdAt precisa ser do servidor', async () => {
    await assertFails(setDoc(doc(alice(), 'users/alice/saved/camaroes'), { createdAt: Timestamp.fromMillis(0) }));
    await assertFails(setDoc(doc(alice(), 'users/alice/saved/camaroes'), { createdAt: Timestamp.now() }));
  });

  it('update é negado (nem o dono reescreve)', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/alice/saved/camaroes'), { createdAt: Timestamp.now() });
    });
    await assertFails(updateDoc(doc(alice(), 'users/alice/saved/camaroes'), { createdAt: serverTimestamp() }));
    await assertFails(setDoc(doc(alice(), 'users/alice/saved/camaroes'), { createdAt: serverTimestamp() }));
  });

  it('só o dono lê, lista e remove (privado por padrão)', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/alice/saved/camaroes'), { createdAt: Timestamp.now() });
    });
    await assertSucceeds(getDoc(doc(alice(), 'users/alice/saved/camaroes')));
    const mine = await assertSucceeds(getDocs(query(collection(alice(), 'users/alice/saved'), orderBy('createdAt', 'desc'))));
    if (mine.size !== 1) throw new Error('esperava 1 salvo, veio ' + mine.size);
    await assertFails(getDoc(doc(bob(), 'users/alice/saved/camaroes')));
    await assertFails(getDocs(collection(bob(), 'users/alice/saved')));
    await assertFails(getDoc(doc(anon(), 'users/alice/saved/camaroes')));
    await assertFails(deleteDoc(doc(bob(), 'users/alice/saved/camaroes')));
    await assertSucceeds(deleteDoc(doc(alice(), 'users/alice/saved/camaroes')));
  });
});

describe('users/{uid}/lists/{listId} (listas nomeadas)', () => {
  const LIST = 'users/alice/lists/sabado';

  function newList(overrides = {}) {
    return {
      name: 'Sábado com as meninas',
      emoji: '🎉',
      placeIds: ['camaroes'],
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
      ...overrides,
    };
  }

  async function seedList(data = {}) {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), LIST), {
        name: 'Sábado com as meninas',
        emoji: '🎉',
        placeIds: ['camaroes'],
        createdAt: Timestamp.fromMillis(1000),
        updatedAt: Timestamp.fromMillis(1000),
        ...data,
      });
    });
  }

  it('dono cria com nome, emoji, placeIds e datas do servidor', async () => {
    await assertSucceeds(setDoc(doc(alice(), LIST), newList()));
  });

  it('emoji é opcional (null) e placeIds pode começar vazio', async () => {
    await assertSucceeds(setDoc(doc(alice(), LIST), newList({ emoji: null, placeIds: [] })));
  });

  it('outro usuário e anônimo não criam na minha conta', async () => {
    await assertFails(setDoc(doc(bob(), LIST), newList()));
    await assertFails(setDoc(doc(anon(), LIST), newList()));
  });

  it('chaves exatas: nem extra, nem faltando', async () => {
    await assertFails(setDoc(doc(alice(), LIST), newList({ public: true })));
    await assertFails(setDoc(doc(alice(), LIST), newList({ note: 'x' })));
    const { emoji, ...noEmoji } = newList();
    await assertFails(setDoc(doc(alice(), LIST), noEmoji));
    const { updatedAt, ...noUpdated } = newList();
    await assertFails(setDoc(doc(alice(), LIST), noUpdated));
  });

  it('nome: string de 1 a 40 caracteres, aparado', async () => {
    await assertFails(setDoc(doc(alice(), LIST), newList({ name: '' })));
    await assertFails(setDoc(doc(alice(), LIST), newList({ name: 'a'.repeat(41) })));
    await assertFails(setDoc(doc(alice(), LIST), newList({ name: ' Sábado' })));
    await assertFails(setDoc(doc(alice(), LIST), newList({ name: 'Sábado ' })));
    await assertFails(setDoc(doc(alice(), LIST), newList({ name: 42 })));
    await assertSucceeds(setDoc(doc(alice(), LIST), newList({ name: 'a'.repeat(40) })));
  });

  it('emoji: null ou um dos 12 fixos do app', async () => {
    await assertFails(setDoc(doc(alice(), LIST), newList({ emoji: '' })));
    await assertFails(setDoc(doc(alice(), LIST), newList({ emoji: 'abc' })));
    await assertFails(setDoc(doc(alice(), LIST), newList({ emoji: '😀' })));
    await assertFails(setDoc(doc(alice(), LIST), newList({ emoji: 'x'.repeat(9) })));
    await assertFails(setDoc(doc(alice(), LIST), newList({ emoji: 7 })));
    for (const e of ['🎉', '🍕', '🍔', '🍣', '🍻', '☕', '🍰', '🌮', '🌊', '💑', '👯', '⭐']) {
      await assertSucceeds(setDoc(doc(alice(), 'users/alice/lists/e' + e.codePointAt(0)), newList({ emoji: e })));
    }
  });

  it('nome sem espaços internos repetidos (normalizado pelo app)', async () => {
    await assertFails(setDoc(doc(alice(), LIST), newList({ name: 'Sábado  com as meninas' })));
    await assertFails(setDoc(doc(alice(), LIST), newList({ name: 'Sábado\t\tcom' })));
    await assertSucceeds(setDoc(doc(alice(), LIST), newList({ name: 'Sábado com as meninas' })));
  });

  it('placeIds: lista de até 200', async () => {
    await assertFails(setDoc(doc(alice(), LIST), newList({ placeIds: 'camaroes' })));
    await assertFails(setDoc(doc(alice(), LIST), newList({ placeIds: { a: 1 } })));
    await assertFails(setDoc(doc(alice(), LIST), newList({ placeIds: null })));
    const many = Array.from({ length: 201 }, (_, i) => 'p' + i);
    await assertFails(setDoc(doc(alice(), LIST), newList({ placeIds: many })));
    await assertSucceeds(setDoc(doc(alice(), LIST), newList({ placeIds: many.slice(0, 200) })));
  });

  it('datas do servidor na criação', async () => {
    await assertFails(setDoc(doc(alice(), LIST), newList({ createdAt: Timestamp.fromMillis(0) })));
    await assertFails(setDoc(doc(alice(), LIST), newList({ updatedAt: Timestamp.fromMillis(0) })));
  });

  it('dono renomeia e mexe nos membros com updatedAt do servidor', async () => {
    await seedList();
    await assertSucceeds(updateDoc(doc(alice(), LIST), { name: 'Sábado', emoji: null, updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(alice(), LIST), { placeIds: arrayUnion('outro'), updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(alice(), LIST), { placeIds: arrayRemove('camaroes'), updatedAt: serverTimestamp() }));
  });

  it('update sem updatedAt do servidor é negado', async () => {
    await seedList();
    await assertFails(updateDoc(doc(alice(), LIST), { name: 'Sábado' }));
    await assertFails(updateDoc(doc(alice(), LIST), { name: 'Sábado', updatedAt: Timestamp.fromMillis(5000) }));
  });

  it('createdAt é imutável', async () => {
    await seedList();
    await assertFails(updateDoc(doc(alice(), LIST), { createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(alice(), LIST), { createdAt: Timestamp.fromMillis(2000), updatedAt: serverTimestamp() }));
  });

  it('update valida nome, chaves e tamanho dos membros', async () => {
    await seedList();
    await assertFails(updateDoc(doc(alice(), LIST), { name: '', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(alice(), LIST), { name: 'a'.repeat(41), updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(alice(), LIST), { extra: 1, updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(alice(), LIST), { placeIds: 'x', updatedAt: serverTimestamp() }));
    await seedList({ placeIds: Array.from({ length: 200 }, (_, i) => 'p' + i) });
    await assertFails(updateDoc(doc(alice(), LIST), { placeIds: arrayUnion('p200'), updatedAt: serverTimestamp() }));
  });

  it('terceiro não lê, não lista, não altera nem exclui', async () => {
    await seedList();
    await assertFails(getDoc(doc(bob(), LIST)));
    await assertFails(getDocs(collection(bob(), 'users/alice/lists')));
    await assertFails(getDoc(doc(anon(), LIST)));
    await assertFails(updateDoc(doc(bob(), LIST), { name: 'Hack', updatedAt: serverTimestamp() }));
    await assertFails(deleteDoc(doc(bob(), LIST)));
  });

  it('dono lê, lista e exclui', async () => {
    await seedList();
    await assertSucceeds(getDoc(doc(alice(), LIST)));
    const mine = await assertSucceeds(getDocs(collection(alice(), 'users/alice/lists')));
    if (mine.size !== 1) throw new Error('esperava 1 lista, veio ' + mine.size);
    await assertSucceeds(deleteDoc(doc(alice(), LIST)));
  });

  it('remover do Quero ir e das listas num único batch', async () => {
    await seedList();
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/alice/saved/camaroes'), { createdAt: Timestamp.now() });
    });
    const db = alice();
    const batch = writeBatch(db);
    batch.delete(doc(db, 'users/alice/saved/camaroes'));
    batch.update(doc(db, LIST), { placeIds: arrayRemove('camaroes'), updatedAt: serverTimestamp() });
    await assertSucceeds(batch.commit());
  });



  async function follow(follower, target) {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/' + follower + '/following/' + target), { createdAt: Timestamp.now() });
    });
  }

  const credit = (overrides = {}) => ({
    copiedFromUid: 'bob',
    copiedFromName: 'Bob',
    copiedFromListId: 'sabado-do-bob',
    ...overrides,
  });


  async function seedSource({ visible = true, id = 'sabado-do-bob', owner = 'bob' } = {}) {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/' + owner + '/lists/' + id), {
        name: 'Sábado',
        emoji: null,
        placeIds: ['camaroes'],
        createdAt: Timestamp.fromMillis(1000),
        updatedAt: Timestamp.fromMillis(1000),
        visible,
      });
    });
  }


  async function canCopy() {
    await seedSource();
    await follow('alice', 'bob');
  }

  it('visible é opcional e, quando presente, booleano', async () => {
    await assertSucceeds(setDoc(doc(alice(), LIST), newList({ visible: true })));
    await assertSucceeds(setDoc(doc(alice(), 'users/alice/lists/b'), newList({ visible: false })));
    for (const visible of ['true', 1, null, ['x']]) {
      await assertFails(setDoc(doc(alice(), 'users/alice/lists/c'), newList({ visible })));
    }
  });

  it('dono torna a lista visível e privada de novo (lista antiga, sem os opcionais)', async () => {
    await seedList();
    await assertSucceeds(updateDoc(doc(alice(), LIST), { visible: true, updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(alice(), LIST), { visible: false, updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(alice(), LIST), { visible: 'sim', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(bob(), LIST), { visible: true, updatedAt: serverTimestamp() }));
  });

  it('cópia: cria com o trio de crédito e o nome da autora', async () => {
    await canCopy();
    await assertSucceeds(setDoc(doc(alice(), LIST), newList(credit())));
    await assertSucceeds(setDoc(doc(alice(), 'users/alice/lists/b'), newList({ ...credit(), visible: true })));
  });

  it('cópia: trio incompleto, nome divergente, autora inexistente ou tipos errados são negados', async () => {
    await canCopy();
    await assertFails(setDoc(doc(alice(), LIST), newList({ copiedFromUid: 'bob' })));
    await assertFails(setDoc(doc(alice(), LIST), newList({ copiedFromUid: 'bob', copiedFromName: 'Bob' })));
    await assertFails(setDoc(doc(alice(), LIST), newList({ copiedFromName: 'Bob', copiedFromListId: 'x' })));
    await assertFails(setDoc(doc(alice(), LIST), newList(credit({ copiedFromName: 'Outra Pessoa' }))));
    await assertFails(setDoc(doc(alice(), LIST), newList(credit({ copiedFromName: 'bob' }))));
    await assertFails(setDoc(doc(alice(), LIST), newList(credit({ copiedFromUid: 'fantasma', copiedFromName: 'Fantasma' }))));
    await assertFails(setDoc(doc(alice(), LIST), newList(credit({ copiedFromListId: 7 }))));
    await assertFails(setDoc(doc(alice(), LIST), newList(credit({ copiedFromUid: null }))));
  });

  it('forja: crédito de lista inventada, não visível, de quem não sigo ou a mim mesma', async () => {

    await follow('alice', 'bob');
    await assertFails(setDoc(doc(alice(), LIST), newList(credit({ copiedFromListId: 'inventada' }))));

    await seedSource({ visible: false });
    await assertFails(setDoc(doc(alice(), LIST), newList(credit())));
    await seedSource({ id: 'sem-chave', visible: null });
    await assertFails(setDoc(doc(alice(), LIST), newList(credit({ copiedFromListId: 'sem-chave' }))));

    await seedSource();
    await env.withSecurityRulesDisabled(async (ctx) => {
      await deleteDoc(doc(ctx.firestore(), 'users/alice/following/bob'));
    });
    await assertFails(setDoc(doc(alice(), LIST), newList(credit())));

    await seedSource({ owner: 'alice', id: 'minha' });
    await follow('alice', 'alice');
    await assertFails(setDoc(doc(alice(), LIST), newList(credit({
      copiedFromUid: 'alice',
      copiedFromName: 'Alice',
      copiedFromListId: 'minha',
    }))));

    await follow('alice', 'bob');
    await assertSucceeds(setDoc(doc(alice(), LIST), newList(credit())));
  });

  it('crédito é imutável: não muda, não sai e não entra depois do create', async () => {
    await seedList(credit());
    await assertSucceeds(updateDoc(doc(alice(), LIST), { name: 'Sábado', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(alice(), LIST), { copiedFromName: 'Alice', copiedFromUid: 'alice', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(alice(), LIST), { copiedFromListId: 'outra', updatedAt: serverTimestamp() }));
    const { copiedFromUid, copiedFromName, copiedFromListId, ...semCredito } = { ...credit(), name: 'Sábado', emoji: null, placeIds: [] };
    await assertFails(setDoc(doc(alice(), LIST), { ...semCredito, createdAt: Timestamp.fromMillis(1000), updatedAt: serverTimestamp() }));
    await seedList();
    await assertFails(updateDoc(doc(alice(), LIST), { ...credit(), updatedAt: serverTimestamp() }));
  });

  it('seguidor lê a lista visível (doc e consulta com visible == true)', async () => {
    await seedList({ visible: true });
    await follow('bob', 'alice');
    await assertSucceeds(getDoc(doc(bob(), LIST)));
    const snap = await assertSucceeds(getDocs(query(collection(bob(), 'users/alice/lists'), where('visible', '==', true))));
    if (snap.size !== 1) throw new Error('esperava 1 lista visível, veio ' + snap.size);
  });

  it('seguidor não lê lista privada (sem visible ou visible false) nem consulta sem o filtro', async () => {
    await follow('bob', 'alice');
    await seedList();
    await assertFails(getDoc(doc(bob(), LIST)));
    await seedList({ visible: false });
    await assertFails(getDoc(doc(bob(), LIST)));
    await assertFails(getDocs(collection(bob(), 'users/alice/lists')));
  });

  it('quem não segue não lê nem a lista visível', async () => {
    await seedList({ visible: true });
    await assertFails(getDoc(doc(bob(), LIST)));
    await assertFails(getDocs(query(collection(bob(), 'users/alice/lists'), where('visible', '==', true))));
    await assertFails(getDoc(doc(anon(), LIST)));
  });

  it('seguidor lê, mas não altera nem exclui a lista visível', async () => {
    await seedList({ visible: true });
    await follow('bob', 'alice');
    await assertFails(updateDoc(doc(bob(), LIST), { name: 'Hack', updatedAt: serverTimestamp() }));
    await assertFails(deleteDoc(doc(bob(), LIST)));
  });
});

describe('users/{uid}/lists/{listId}/copies/{copierUid} (F13: contador de cópias)', () => {
  const LIST = 'users/alice/lists/sabado';
  const copyPath = (copier) => LIST + '/copies/' + copier;

  async function seedList(data = {}) {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), LIST), {
        name: 'Sábado',
        emoji: null,
        placeIds: ['camaroes'],
        createdAt: Timestamp.fromMillis(1000),
        updatedAt: Timestamp.fromMillis(1000),
        visible: true,
        ...data,
      });
    });
  }

  async function follow(follower, target) {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/' + follower + '/following/' + target), { createdAt: Timestamp.now() });
    });
  }

  async function seedCopy(copier) {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), copyPath(copier)), { createdAt: Timestamp.now() });
    });
  }

  async function actualCopy(copier = 'bob', id = 'copy', overrides = {}) {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `users/${copier}/lists/${id}`), {
        name: 'Cópia', emoji: null, placeIds: ['camaroes'],
        createdAt: Timestamp.fromMillis(2000), updatedAt: Timestamp.fromMillis(2000),
        copiedFromUid: 'alice', copiedFromName: 'Alice', copiedFromListId: 'sabado',
        ...overrides,
      });
    });
  }
  function receipt(overrides = {}) {
    return { createdAt: serverTimestamp(), copiedListId: 'copy', ...overrides };
  }

  it('seguidor registra a própria cópia de lista visível', async () => {
    await seedList();
    await actualCopy();
    await follow('bob', 'alice');
    await assertSucceeds(setDoc(doc(bob(), copyPath('bob')), receipt()));
  });

  it('uma por pessoa e imutável: 2º registro, update e delete de quem copiou negados', async () => {
    await seedList();
    await actualCopy();
    await follow('bob', 'alice');
    await assertSucceeds(setDoc(doc(bob(), copyPath('bob')), receipt()));
    await assertFails(setDoc(doc(bob(), copyPath('bob')), receipt()));
    await assertFails(updateDoc(doc(bob(), copyPath('bob')), receipt()));
    await assertFails(updateDoc(doc(alice(), copyPath('bob')), receipt()));
    await assertFails(deleteDoc(doc(bob(), copyPath('bob'))));
    await assertFails(deleteDoc(doc(anon(), copyPath('bob'))));
  });

  it('a dona apaga a lista e o contador num único batch; terceiro não apaga', async () => {
    await seedList();
    await seedCopy('bob');
    await seedCopy('carol');
    const carol = env.authenticatedContext('carol').firestore();
    await assertFails(deleteDoc(doc(carol, copyPath('carol'))));
    const db = alice();
    const batch = writeBatch(db);
    batch.delete(doc(db, copyPath('bob')));
    batch.delete(doc(db, copyPath('carol')));
    batch.delete(doc(db, LIST));
    await assertSucceeds(batch.commit());
    let left = -1;
    await env.withSecurityRulesDisabled(async (ctx) => {
      left = (await getDocs(collection(ctx.firestore(), LIST + '/copies'))).size;
    });
    if (left !== 0) throw new Error('sobraram ' + left + ' cópias');
  });

  it('quem não segue a dona, lista privada ou inexistente: negado', async () => {
    await seedList();
    await actualCopy();
    await assertFails(setDoc(doc(bob(), copyPath('bob')), receipt()));
    await follow('bob', 'alice');
    await seedList({ visible: false });
    await assertFails(setDoc(doc(bob(), copyPath('bob')), receipt()));
    await env.withSecurityRulesDisabled(async (ctx) => {
      await deleteDoc(doc(ctx.firestore(), LIST));
    });
    await assertFails(setDoc(doc(bob(), copyPath('bob')), receipt()));
  });

  it('forja: cópia em nome de outra pessoa, da própria dona, createdAt do cliente ou chave extra', async () => {
    await seedList();
    await actualCopy();
    await follow('bob', 'alice');
    const carol = env.authenticatedContext('carol').firestore();
    await assertFails(setDoc(doc(carol, copyPath('bob')), receipt()));
    await assertFails(setDoc(doc(alice(), copyPath('alice')), receipt()));
    await assertFails(setDoc(doc(bob(), copyPath('bob')), receipt({ createdAt: Timestamp.fromMillis(1) })));
    await assertFails(setDoc(doc(bob(), copyPath('bob')), receipt({ n: 1 })));
    await assertFails(setDoc(doc(bob(), copyPath('bob')), {}));
    await assertFails(setDoc(doc(anon(), copyPath('bob')), receipt()));
  });

  it('a dona lê e conta todas as cópias; quem copiou lê só a própria', async () => {
    await seedList();
    await seedCopy('bob');
    await seedCopy('carol');
    const count = await assertSucceeds(getCountFromServer(collection(alice(), LIST + '/copies')));
    if (count.data().count !== 2) throw new Error('esperava 2 cópias, veio ' + count.data().count);
    await assertSucceeds(getDoc(doc(bob(), copyPath('bob'))));
    await assertFails(getDoc(doc(bob(), copyPath('carol'))));
    await assertFails(getDocs(collection(bob(), LIST + '/copies')));
    await assertFails(getCountFromServer(collection(bob(), LIST + '/copies')));
    await assertFails(getDoc(doc(anon(), copyPath('bob'))));
  });
  it('não conta só o recibo, lista inexistente, crédito errado ou lista sem crédito', async () => {
    await seedList();
    await follow('bob', 'alice');
    await assertFails(setDoc(doc(bob(), copyPath('bob')), receipt()));
    await actualCopy('carol');
    await assertFails(setDoc(doc(bob(), copyPath('bob')), receipt()));
    await actualCopy('bob', 'copy', { copiedFromListId: 'outra' });
    await assertFails(setDoc(doc(bob(), copyPath('bob')), receipt()));
    await actualCopy('bob', 'copy', { copiedFromUid: 'carol' });
    await assertFails(setDoc(doc(bob(), copyPath('bob')), receipt()));
    await actualCopy('bob', 'copy', { copiedFromUid: null, copiedFromListId: null });
    await assertFails(setDoc(doc(bob(), copyPath('bob')), receipt()));
    await assertFails(setDoc(doc(bob(), copyPath('bob')), receipt({ copiedListId: 'x/y' })));
    await assertFails(setDoc(doc(bob(), copyPath('bob')), { createdAt: serverTimestamp() }));
  });

  it('recibo pode nascer junto da cópia real no batch', async () => {
    await seedList();
    await follow('bob', 'alice');
    const db = bob(), batch = writeBatch(db);
    batch.set(doc(db, 'users/bob/lists/copy'), {
      name: 'Sábado', emoji: null, placeIds: ['camaroes'],
      createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
      copiedFromUid: 'alice', copiedFromName: 'Alice', copiedFromListId: 'sabado',
    });
    batch.set(doc(db, copyPath('bob')), receipt());
    await assertSucceeds(batch.commit());
  });

  it('legado só conta após comprovar cópia; mantém data e não pode trocar prova', async () => {
    await seedList();
    await follow('bob', 'alice');
    await seedCopy('bob');
    const ref = doc(bob(), copyPath('bob'));
    const at = (await getDoc(ref)).data().createdAt;
    const verified = () => getCountFromServer(query(collection(alice(), LIST + '/copies'), where('copiedListId', '>', '')));
    if ((await verified()).data().count !== 0) throw new Error('Legado sem prova contado');
    await assertFails(updateDoc(ref, { copiedListId: 'copy' }));
    await actualCopy();
    await assertFails(updateDoc(ref, { copiedListId: 'copy', createdAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(ref, { copiedListId: 'copy' }));
    const after = (await getDoc(ref)).data();
    if (!after.createdAt.isEqual(at)) throw new Error('Data alterada');
    if ((await verified()).data().count !== 1) throw new Error('Cópia válida não contada');
    await actualCopy('bob', 'other');
    await assertFails(updateDoc(ref, { copiedListId: 'other' }));
  });

});

describe('migração dos recibos de cópia', () => {
  it('simula por padrão, preserva datas, deixa sem prova intacto e é idempotente', async () => {
    const { initializeApp, deleteApp } = require('firebase-admin/app');
    const { getFirestore, Timestamp: AdminTimestamp } = require('firebase-admin/firestore');
    const { backfillCopyReceipts } = require('../seed/backfill-copy-receipts');
    const app = initializeApp({ projectId: PROJECT_ID }, 'copy-migration-test');
    try {
      const db = getFirestore(app), at = AdminTimestamp.fromMillis(1234);
      const valid = db.doc('users/alice/lists/sabado/copies/bob');
      const invalid = db.doc('users/alice/lists/sabado/copies/carol');
      await valid.set({ createdAt: at });
      await invalid.set({ createdAt: at });
      await db.doc('users/bob/lists/real').set({ copiedFromUid: 'alice', copiedFromListId: 'sabado', createdAt: at });
      const options = { db, log: () => {} };
      const dry = await backfillCopyReceipts(options);
      if (dry.verified !== 1 || dry.unverified !== 1 || (await valid.get()).data().copiedListId) throw new Error('Simulação alterou dados');
      await backfillCopyReceipts({ ...options, apply: true });
      const data = (await valid.get()).data();
      if (data.copiedListId !== 'real' || !data.createdAt.isEqual(at)) throw new Error('Prova ou data incorreta');
      if (Object.keys((await invalid.get()).data()).length !== 1) throw new Error('Legado sem prova alterado');
      const again = await backfillCopyReceipts({ ...options, apply: true });
      if (again.verified !== 0 || again.unchanged !== 1) throw new Error('Não idempotente');
    } finally { await deleteApp(app); }
  });
});

describe('places', () => {
  it('logado lê; anônimo não', async () => {
    await assertSucceeds(getDoc(doc(alice(), 'places/camaroes')));
    await assertFails(getDoc(doc(anon(), 'places/camaroes')));
  });

  it('cliente nunca edita nem apaga local existente', async () => {
    await assertFails(setDoc(doc(alice(), 'places/novo'), { name: 'X' }));
    await assertFails(updateDoc(doc(alice(), 'places/camaroes'), { name: 'X' }));
    await assertFails(deleteDoc(doc(alice(), 'places/camaroes')));
  });
});


function newPlace(overrides = {}) {
  return {
    name: 'Bar do Zé',
    category: 'Bar',
    neighborhood: 'Sé',
    city: 'São Paulo',
    address: 'Praça da Sé, 1',
    lat: -23.5503,
    lng: -46.6339,
    geohash: '6gyf4bf1x',
    osmId: 'node/123',
    source: 'osm',
    createdBy: 'alice',
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

describe('places: criação pelo app (G2)', () => {
  it('logado cria local OSM válido (node, way, relation)', async () => {
    await assertSucceeds(setDoc(doc(alice(), 'places/osm-n123'), newPlace()));
    await assertSucceeds(setDoc(doc(alice(), 'places/osm-w45'), newPlace({ osmId: 'way/45' })));
    await assertSucceeds(setDoc(doc(alice(), 'places/osm-r7'), newPlace({ osmId: 'relation/7' })));
  });

  it('campos de texto vazios são aceitos (Photon sem bairro/cidade/endereço)', async () => {
    await assertSucceeds(setDoc(doc(alice(), 'places/osm-n123'), newPlace({ neighborhood: '', city: '', address: '' })));
  });

  it('anônimo não cria', async () => {
    await assertFails(setDoc(doc(anon(), 'places/osm-n123'), newPlace()));
  });

  it('id fora do padrão osm-[nwr][1-9][0-9]* é negado (inclusive zero à esquerda)', async () => {
    for (const id of ['novo', 'osm-x123', 'osm-n', 'osm-n12a', 'mangai-natal', 'osm-N123', 'xosm-n123', 'osm-n0', 'osm-n0123']) {
      await assertFails(setDoc(doc(alice(), 'places/' + id), newPlace()));
    }
  });

  it('zero à esquerda é negado mesmo com osmId coerente (seria duplicata de osm-n123)', async () => {
    await assertFails(setDoc(doc(alice(), 'places/osm-n0123'), newPlace({ osmId: 'node/0123' })));
  });

  it('osmId precisa casar com o id', async () => {
    await assertFails(setDoc(doc(alice(), 'places/osm-n123'), newPlace({ osmId: 'node/124' })));
    await assertFails(setDoc(doc(alice(), 'places/osm-n123'), newPlace({ osmId: 'way/123' })));
    await assertFails(setDoc(doc(alice(), 'places/osm-w123'), newPlace({ osmId: 'node/123' })));
  });

  it('coordenadas fora do Brasil ou não numéricas são negadas', async () => {
    await assertFails(setDoc(doc(alice(), 'places/osm-n123'), newPlace({ lat: 38.7223, lng: -9.1393 })));
    await assertFails(setDoc(doc(alice(), 'places/osm-n123'), newPlace({ lat: -34.9, lng: -56.16 })));
    await assertFails(setDoc(doc(alice(), 'places/osm-n123'), newPlace({ lat: 6, lng: -60 })));
    await assertFails(setDoc(doc(alice(), 'places/osm-n123'), newPlace({ lat: -10, lng: -75 })));
    await assertFails(setDoc(doc(alice(), 'places/osm-n123'), newPlace({ lat: '-23.5', lng: -46.6 })));
    await assertFails(setDoc(doc(alice(), 'places/osm-n123'), newPlace({ lat: null })));
  });

  it('chave extra ou faltando é negada', async () => {
    await assertFails(setDoc(doc(alice(), 'places/osm-n123'), newPlace({ photoUrl: 'https://x/y.jpg' })));
    await assertFails(setDoc(doc(alice(), 'places/osm-n123'), newPlace({ updatedAt: serverTimestamp() })));

    await assertFails(setDoc(doc(alice(), 'places/osm-n123'), newPlace({ searchTokens: ['ba', 'bar'] })));
    await assertFails(setDoc(doc(alice(), 'places/osm-n123'), newPlace({ nameLower: 'bar do ze' })));
    const { address: _a, ...missing } = newPlace();
    await assertFails(setDoc(doc(alice(), 'places/osm-n123'), missing));
  });

  it('nome: 1–120 caracteres, aparado', async () => {
    await assertFails(setDoc(doc(alice(), 'places/osm-n123'), newPlace({ name: '' })));
    await assertFails(setDoc(doc(alice(), 'places/osm-n123'), newPlace({ name: ' Bar ' })));
    await assertFails(setDoc(doc(alice(), 'places/osm-n123'), newPlace({ name: 'x'.repeat(121) })));
    await assertFails(setDoc(doc(alice(), 'places/osm-n123'), newPlace({ name: 42 })));
    await assertSucceeds(setDoc(doc(alice(), 'places/osm-n123'), newPlace({ name: 'x'.repeat(120) })));
  });

  it('categoria precisa ser do vocabulário', async () => {
    await assertFails(setDoc(doc(alice(), 'places/osm-n123'), newPlace({ category: 'Local' })));
    await assertFails(setDoc(doc(alice(), 'places/osm-n123'), newPlace({ category: 'Boate' })));
    await assertSucceeds(setDoc(doc(alice(), 'places/osm-n123'), newPlace({ category: 'Praça de alimentação' })));
  });

  it('geohash: 9 caracteres base32', async () => {
    await assertFails(setDoc(doc(alice(), 'places/osm-n123'), newPlace({ geohash: '6gyf4bf8' })));
    await assertFails(setDoc(doc(alice(), 'places/osm-n123'), newPlace({ geohash: '6gyf4bf8ma' })));
    await assertFails(setDoc(doc(alice(), 'places/osm-n123'), newPlace({ geohash: '6gyf4bf8a' })));
    await assertFails(setDoc(doc(alice(), 'places/osm-n123'), newPlace({ geohash: 123456789 })));
  });

  it('source "osm", createdBy = uid e createdAt do servidor', async () => {
    await assertFails(setDoc(doc(alice(), 'places/osm-n123'), newPlace({ source: 'curated' })));
    await assertFails(setDoc(doc(alice(), 'places/osm-n123'), newPlace({ createdBy: 'bob' })));
    await assertFails(setDoc(doc(alice(), 'places/osm-n123'), newPlace({ createdAt: Timestamp.now() })));
  });

  it('corrida: create num doc que já existe vira update e é negado (o app segue)', async () => {
    await assertSucceeds(setDoc(doc(alice(), 'places/osm-n123'), newPlace()));
    await assertFails(setDoc(doc(bob(), 'places/osm-n123'), newPlace({ createdBy: 'bob' })));
    const snap = await assertSucceeds(getDoc(doc(bob(), 'places/osm-n123')));
    if (snap.data().createdBy !== 'alice') throw new Error('o doc da 1ª criação deveria ficar');
  });

  it('update e delete do local criado são negados (inclusive ao criador)', async () => {
    await assertSucceeds(setDoc(doc(alice(), 'places/osm-n123'), newPlace()));
    await assertFails(updateDoc(doc(alice(), 'places/osm-n123'), { name: 'Outro' }));
    await assertFails(deleteDoc(doc(alice(), 'places/osm-n123')));
  });

  it('avaliação e local novo no mesmo batch', async () => {
    const db = alice();
    const batch = writeBatch(db);
    batch.set(doc(db, 'places/osm-n123'), newPlace());
    batch.set(doc(db, 'reviews/nova'), validReview({ placeId: 'osm-n123', placeName: 'Bar do Zé' }));
    setAudit(db, batch, 'reviews', 'nova', validReview({ placeId: 'osm-n123', placeName: 'Bar do Zé' }));
    batch.set(doc(db, lockPath('alice', 'osm-n123')), validLock('nova', { placeId: 'osm-n123' }));
    await assertSucceeds(batch.commit());
  });

  it('avaliação de local inexistente continua negada', async () => {
    await assertFails(setDoc(doc(alice(), 'reviews/nova'), validReview({ placeId: 'osm-n999', placeName: 'Bar do Zé' })));
  });

  it('batch com local forjado derruba a avaliação junto', async () => {
    const db = alice();
    const batch = writeBatch(db);
    batch.set(doc(db, 'places/osm-n123'), newPlace({ lat: 38.7, lng: -9.1 }));
    batch.set(doc(db, 'reviews/nova'), validReview({ placeId: 'osm-n123', placeName: 'Bar do Zé' }));
    setAudit(db, batch, 'reviews', 'nova', validReview({ placeId: 'osm-n123', placeName: 'Bar do Zé' }));
    batch.set(doc(db, lockPath('alice', 'osm-n123')), validLock('nova', { placeId: 'osm-n123' }));
    await assertFails(batch.commit());
  });

  it('salvar no Quero ir depois de criar o local', async () => {
    await assertFails(setDoc(doc(alice(), 'users/alice/saved/osm-n123'), { createdAt: serverTimestamp() }));
    await assertSucceeds(setDoc(doc(alice(), 'places/osm-n123'), newPlace()));
    await assertSucceeds(setDoc(doc(alice(), 'users/alice/saved/osm-n123'), { createdAt: serverTimestamp() }));
  });
});

describe('reviews', () => {
  it('consulta do detalhe (placeId ==, authorId in lote, orderBy createdAt desc) é permitida para logado', async () => {
    const q = query(
      collection(bob(), 'reviews'),
      where('placeId', '==', 'camaroes'),
      where('authorId', 'in', ['alice', 'bob']),
      orderBy('createdAt', 'desc'),
    );
    const snap = await assertSucceeds(getDocs(q));
    if (snap.size !== 1) throw new Error('esperava 1 review, veio ' + snap.size);
    await assertFails(getDocs(query(
      collection(anon(), 'reviews'),
      where('placeId', '==', 'camaroes'),
      where('authorId', 'in', ['alice']),
    )));
  });

  it('cria avaliação válida', async () => {
    await assertSucceeds(freshReview(alice(), validReview()));
  });

  it('cria avaliação válida sem companhia (null)', async () => {
    await assertSucceeds(freshReview(alice(), validReview({ companion: null })));
  });

  it('anônimo não avalia', async () => {
    await assertFails(freshReview(anon(), validReview()));
  });

  it('não forja authorId de outro uid', async () => {
    await assertFails(freshReview(bob(), validReview()));
  });

  it('authorName precisa ser o nome do perfil', async () => {
    await assertFails(freshReview(alice(), validReview({ authorName: 'Outra Pessoa' })));
  });

  it('usuário sem perfil não avalia', async () => {
    const db = env.authenticatedContext('ghost').firestore();
    await assertFails(freshReview(db, validReview({ authorId: 'ghost', authorName: 'Ghost' })));
  });

  for (const axis of ['food', 'ambience', 'service']) {
    it(axis + ': rejeita 0, 6, decimal e string', async () => {
      await assertFails(freshReview(alice(), validReview({ [axis]: 0 })));
      await assertFails(freshReview(alice(), validReview({ [axis]: 6 })));
      await assertFails(freshReview(alice(), validReview({ [axis]: 3.5 })));
      await assertFails(freshReview(alice(), validReview({ [axis]: '3' })));
    });

    it(axis + ': rejeita 4.5 e "5" (F14)', async () => {
      await assertFails(freshReview(alice(), validReview({ [axis]: 4.5 })));
      await assertFails(freshReview(alice(), validReview({ [axis]: '5' })));
    });

    it(axis + ': chave obrigatória, mesmo quando não avaliado (null)', async () => {
      const data = validReview();
      delete data[axis];
      await assertFails(freshReview(alice(), data));
    });

    it(axis + ': opcional (null) quando outro eixo foi avaliado (F14)', async () => {
      await assertSucceeds(freshReview(alice(), validReview({ [axis]: null })));
    });

    it(axis + ': avaliação só com este eixo é válida (F14)', async () => {
      const only = { food: null, ambience: null, service: null, [axis]: 4 };
      await assertSucceeds(freshReview(alice(), validReview(only)));
    });
  }

  it('os 3 eixos null é negado (mínimo 1 eixo; F14)', async () => {
    await assertFails(freshReview(alice(), validReview({ food: null, ambience: null, service: null })));
  });

  it('eixo inválido não passa só porque outro é null (F14)', async () => {
    await assertFails(freshReview(alice(), validReview({ food: null, ambience: 6, service: 3 })));
  });

  it('eixo ausente não vira zero: 0 com os outros null é negado (F14)', async () => {
    await assertFails(freshReview(alice(), validReview({ food: 0, ambience: null, service: null })));
  });

  it('aceita as fronteiras 1 e 5', async () => {
    await assertSucceeds(freshReview(alice(), validReview({ food: 1, ambience: 5, service: 1 })));
  });

  it('createdAt precisa ser do servidor', async () => {
    await assertFails(freshReview(alice(), validReview({ createdAt: Timestamp.fromMillis(0) })));
    await assertFails(freshReview(alice(), validReview({ createdAt: Timestamp.now() })));
  });

  it('não aceita campo extra (ex.: nota agregada, período, texto fora de comment)', async () => {
    await assertFails(freshReview(alice(), validReview({ overall: 5 })));
    await assertFails(freshReview(alice(), validReview({ dayPeriod: 'noite' })));
    await assertFails(freshReview(alice(), validReview({ text: 'top' })));
  });

  it('companion fora da lista é negado', async () => {
    await assertFails(freshReview(alice(), validReview({ companion: 'pet' })));
  });

  it('companion é chave obrigatória (null quando não informado)', async () => {
    const data = validReview();
    delete data.companion;
    await assertFails(freshReview(alice(), data));
  });

  it('comment null é aceito (comentário é opcional)', async () => {
    await assertSucceeds(freshReview(alice(), validReview({ comment: null })));
  });

  it('comment de 1 a 280 caracteres é aceito', async () => {
    await assertSucceeds(freshReview(alice(), validReview({ comment: 'a' })));
    await assertSucceeds(freshReview(alice(), validReview({ comment: 'Camarão top, fila grande.' })));
    await assertSucceeds(freshReview(alice(), validReview({ comment: 'x'.repeat(280) })));

    await assertSucceeds(freshReview(alice(), validReview({ comment: 'ã'.repeat(280) })));
  });

  it('comment vazio, acima de 280 ou não-string é negado', async () => {
    await assertFails(freshReview(alice(), validReview({ comment: '' })));
    await assertFails(freshReview(alice(), validReview({ comment: 'x'.repeat(281) })));

    await assertFails(freshReview(alice(), validReview({ comment: '😀'.repeat(141) })));
    await assertFails(freshReview(alice(), validReview({ comment: 42 })));
    await assertFails(freshReview(alice(), validReview({ comment: true })));
    await assertFails(freshReview(alice(), validReview({ comment: ['a'] })));
  });

  it('comment é chave obrigatória (null quando não informado): chaves permitidas = 11', async () => {
    const data = validReview();
    delete data.comment;
    await assertFails(freshReview(alice(), data));
    await assertFails(freshReview(alice(), validReview({ comment: 'ok', extra: 1 })));
  });

  it('janela de transição: review sem a chave hasPhoto continua aceita (= false)', async () => {
    const data = validReview();
    delete data.hasPhoto;
    await assertSucceeds(freshReview(alice(), data));

    const db = alice();
    const batch = writeBatch(db);
    batch.set(doc(db, 'reviews/semchave'), data);
    setAudit(db, batch, 'reviews', 'semchave', data);
    batch.set(doc(db, 'reviewPhotos/semchave'), validPhoto());
    batch.set(doc(db, lockPath('alice', 'camaroes')), validLock('semchave'));
    await assertFails(batch.commit());
  });

  it('hasPhoto, quando presente, é booleano', async () => {
    await assertFails(freshReview(alice(), validReview({ hasPhoto: null })));
    await assertFails(freshReview(alice(), validReview({ hasPhoto: 'true' })));
    await assertFails(freshReview(alice(), validReview({ hasPhoto: 1 })));
    await assertSucceeds(freshReview(alice(), validReview({ hasPhoto: false })));
  });

  it('hasPhoto: true sem a foto no mesmo batch é negado', async () => {
    await assertFails(freshReview(alice(), validReview({ hasPhoto: true })));
    await assertFails(reviewWithPhotoBatch(alice(), { withPhoto: false }));
  });


  it('priceBand: 1 a 5 e null são aceitos (F27)', async () => {
    for (const band of [1, 2, 3, 4, 5, null]) {
      await assertSucceeds(freshReview(alice(), validReview({ priceBand: band })));
    }
  });

  it('priceBand: build antigo sem a chave continua aceito (F27)', async () => {
    const data = validReview();
    delete data.priceBand;
    if ('priceBand' in data) throw new Error('a chave deveria estar ausente');
    await assertSucceeds(freshReview(alice(), data));
    let snap;
    await env.withSecurityRulesDisabled(async (ctx) => {
      snap = await getDocs(query(collection(ctx.firestore(), 'reviews'), where('authorId', '==', 'alice')));
    });
    const gravadas = snap.docs.filter((d) => d.id !== 'existing');
    if (gravadas.length !== 1 || 'priceBand' in gravadas[0].data()) {
      throw new Error('esperava 1 review gravada sem priceBand');
    }
  });

  it('priceBand com foto: review + foto + faixa no mesmo batch (F27)', async () => {
    await assertSucceeds(reviewWithPhotoBatch(alice(), { review: { priceBand: 3 } }));
    await assertFails(reviewWithPhotoBatch(alice(), { id: 'outra', review: { priceBand: 6 } }));
  });

  it('priceBand: forja 0, 6, "2", 2.5, true, -1 é negada (F27)', async () => {
    for (const band of [0, 6, '2', 2.5, true, -1, [2]]) {
      await assertFails(freshReview(alice(), validReview({ priceBand: band })));
    }
  });

  it('F28: couvert e taxa de 10% opcionais (bool ou null); forja negada', async () => {
    for (const extras of [{ couvert: true }, { couvert: false, serviceFee: true }, { couvert: null, serviceFee: null }]) {
      await assertSucceeds(freshReview(alice(), validReview(extras)));
    }
    for (const extras of [{ couvert: 'sim' }, { serviceFee: 10 }, { couvert: [true] }, { couvert: true, couvertValor: 15 }]) {
      await assertFails(freshReview(alice(), validReview(extras)));
    }
  });

  it('comentário é imutável como a avaliação (nem o autor edita)', async () => {
    await assertFails(updateDoc(doc(alice(), 'reviews/existing'), { comment: 'editado' }));
  });

  it('local precisa existir e placeName bater com o local', async () => {
    await assertFails(freshReview(alice(), validReview({ placeId: 'inexistente' })));
    await assertFails(freshReview(alice(), validReview({ placeName: 'Outro nome' })));
  });

  it('logado lê avaliações; anônimo não', async () => {
    await assertSucceeds(getDoc(doc(bob(), 'reviews/existing')));
    await assertFails(getDoc(doc(anon(), 'reviews/existing')));
  });

  it('consulta do feed (authorId in lote, orderBy createdAt desc) é permitida para logado', async () => {
    const q = query(
      collection(bob(), 'reviews'),
      where('authorId', 'in', ['alice']),
      orderBy('createdAt', 'desc'),
      limit(100),
    );
    const snap = await assertSucceeds(getDocs(q));
    if (snap.size !== 1) throw new Error('esperava 1 review, veio ' + snap.size);
    await assertFails(getDocs(query(collection(anon(), 'reviews'), where('authorId', 'in', ['alice']))));
  });

  it('busca de pessoas por prefixo de displayNameLower é permitida para logado', async () => {
    const q = query(
      collection(bob(), 'users'),
      where('displayNameLower', '>=', 'ali'),
      where('displayNameLower', '<', 'ali\uf8ff'),
      orderBy('displayNameLower'),
      limit(20),
    );
    const snap = await assertSucceeds(getDocs(q));
    if (snap.size !== 1) throw new Error('esperava 1 usuário, veio ' + snap.size);
  });

  it('ninguém edita nem exclui avaliação (nem o autor)', async () => {
    await assertFails(updateDoc(doc(alice(), 'reviews/existing'), { food: 5 }));
    await assertFails(deleteDoc(doc(alice(), 'reviews/existing')));
    await assertFails(deleteDoc(doc(bob(), 'reviews/existing')));
  });
});

describe('reviewPhotos/{reviewId}', () => {
  it('batch válido: review com hasPhoto true + foto do mesmo id e autor', async () => {
    await assertSucceeds(reviewWithPhotoBatch(alice()));
  });

  it('aceita exatamente 150.000 bytes; 150.001 é negado', async () => {
    await assertFails(reviewWithPhotoBatch(alice(), { id: 'grande', photo: { jpeg: jpegBytes(150001) } }));
    await assertSucceeds(reviewWithPhotoBatch(alice(), { id: 'limite', photo: { jpeg: jpegBytes(150000) } }));
  });

  it('foto sem review no mesmo batch é negada', async () => {
    await assertFails(setDoc(doc(alice(), 'reviewPhotos/solta'), validPhoto()));
    await assertFails(reviewWithPhotoBatch(alice(), { id: 'solta', withReview: false }));
  });

  it('foto para review já existente é negada (nem o autor anexa depois)', async () => {
    await assertFails(setDoc(doc(alice(), 'reviewPhotos/existing'), validPhoto()));
    await assertFails(setDoc(doc(bob(), 'reviewPhotos/existing'), validPhoto({ authorId: 'bob' })));
  });

  it('foto ligada a review de outro autor é negada', async () => {

    await assertFails(reviewWithPhotoBatch(bob(), {
      review: { authorId: 'bob', authorName: 'Bob' },
      photo: { authorId: 'alice' },
    }));


    await assertFails(reviewWithPhotoBatch(alice(), {
      review: { authorId: 'bob', authorName: 'Bob' },
    }));
  });

  it('review com hasPhoto false não leva foto', async () => {
    await assertFails(reviewWithPhotoBatch(alice(), { review: { hasPhoto: false } }));
  });

  it('jpeg precisa ser bytes não vazios', async () => {
    await assertFails(reviewWithPhotoBatch(alice(), { id: 's', photo: { jpeg: 'base64...' } }));
    await assertFails(reviewWithPhotoBatch(alice(), { id: 'l', photo: { jpeg: [255, 216] } }));
    await assertFails(reviewWithPhotoBatch(alice(), { id: 'n', photo: { jpeg: null } }));
    await assertFails(reviewWithPhotoBatch(alice(), { id: 'v', photo: { jpeg: Bytes.fromUint8Array(new Uint8Array(0)) } }));
  });

  it('jpeg precisa começar com o marcador JPEG (PNG é negado)', async () => {
    const png = new Uint8Array(1000);
    png.set([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    await assertFails(reviewWithPhotoBatch(alice(), { id: 'png', photo: { jpeg: Bytes.fromUint8Array(png) } }));

    const quase = new Uint8Array(1000);
    quase.set([0xff, 0xd8, 0x00]);
    await assertFails(reviewWithPhotoBatch(alice(), { id: 'quase', photo: { jpeg: Bytes.fromUint8Array(quase) } }));
    await assertSucceeds(reviewWithPhotoBatch(alice(), { id: 'jpg' }));
  });

  it('chaves exatas e createdAt do servidor', async () => {
    await assertFails(reviewWithPhotoBatch(alice(), { id: 'x', photo: { extra: 1 } }));
    const semAutor = validPhoto();
    delete semAutor.authorId;
    const db = alice();
    const batch = writeBatch(db);
    batch.set(doc(db, 'reviews/y'), validReview({ hasPhoto: true }));
    setAudit(db, batch, 'reviews', 'y', validReview({ hasPhoto: true }));
    batch.set(doc(db, 'reviewPhotos/y'), semAutor);
    batch.set(doc(db, lockPath('alice', 'camaroes')), validLock('y'));
    await assertFails(batch.commit());
    await assertFails(reviewWithPhotoBatch(alice(), { id: 'z', photo: { createdAt: Timestamp.now() } }));
  });

  it('anônimo não grava foto', async () => {
    await assertFails(reviewWithPhotoBatch(anon()));
  });

  it('foto é imutável: ninguém edita nem exclui', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'reviewPhotos/existing'), {
        authorId: 'alice',
        jpeg: jpegBytes(10),
        createdAt: Timestamp.now(),
      });
    });
    await assertFails(updateDoc(doc(alice(), 'reviewPhotos/existing'), { jpeg: jpegBytes(20) }));
    await assertFails(setDoc(doc(alice(), 'reviewPhotos/existing'), validPhoto()));
    await assertFails(deleteDoc(doc(alice(), 'reviewPhotos/existing')));
    await assertFails(deleteDoc(doc(bob(), 'reviewPhotos/existing')));
  });

  it('leitura só autenticada', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'reviewPhotos/existing'), {
        authorId: 'alice',
        jpeg: jpegBytes(10),
        createdAt: Timestamp.now(),
      });
    });
    await assertSucceeds(getDoc(doc(bob(), 'reviewPhotos/existing')));
    await assertFails(getDoc(doc(anon(), 'reviewPhotos/existing')));
  });
});

describe('users/{uid}/reviewLocks/{placeId} (F03: 30 dias entre avaliações)', () => {
  const lockRef = (db, uid = 'alice', placeId = 'camaroes') => doc(db, lockPath(uid, placeId));

  async function seedPlace(id, name) {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'places/' + id), { name, category: 'Restaurante' });
    });
  }


  async function seedReview(id, overrides = {}) {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'reviews/' + id), {
        ...validReview(overrides),
        createdAt: Timestamp.now(),
      });
    });
  }



  beforeEach(unlockAll);

  it('1ª avaliação: review + trava no mesmo batch', async () => {
    await assertSucceeds(addReview(alice(), validReview(), { id: 'primeira' }));
    const snap = await assertSucceeds(getDoc(lockRef(alice())));
    const d = snap.data();
    if (d.reviewId !== 'primeira' || d.placeId !== 'camaroes' || !(d.lastAt instanceof Timestamp)) {
      throw new Error('trava inesperada: ' + JSON.stringify(d));
    }
  });

  it('avaliação legada (sem trava) não bloqueia a 1ª avaliação nova', async () => {

    await assertSucceeds(addReview(alice(), validReview()));
  });

  it('mesmo dia: 2ª avaliação negada', async () => {
    await assertSucceeds(addReview(alice(), validReview(), { id: 'hoje1' }));
    await assertFails(addReview(alice(), validReview(), { id: 'hoje2' }));
  });

  it('há 10 dias e há 29,9 dias: negada', async () => {
    await seedLock('alice', 'camaroes', 10);
    await assertFails(addReview(alice(), validReview()));
    await seedLock('alice', 'camaroes', 29.9);
    await assertFails(addReview(alice(), validReview()));
  });

  it('após 30 dias: avaliação aceita e trava renovada', async () => {
    await seedLock('alice', 'camaroes', 31);
    await assertSucceeds(addReview(alice(), validReview(), { id: 'depois' }));
    const snap = await getDoc(lockRef(alice()));
    if (snap.data().reviewId !== 'depois') throw new Error('trava não renovada');
    const age = Date.now() - snap.data().lastAt.toMillis();
    if (age > 60 * 1000) throw new Error('lastAt não é a hora do servidor');
  });

  it('a trava é por local: outro local segue livre', async () => {
    await seedPlace('mangai', 'Mangai');
    await seedLock('alice', 'camaroes', 1);
    await assertSucceeds(addReview(alice(), validReview({ placeId: 'mangai', placeName: 'Mangai' })));
  });

  it('a trava é por usuário: outra pessoa avalia o mesmo local', async () => {
    await seedLock('alice', 'camaroes', 1);
    await assertSucceeds(addReview(bob(), validReview({ authorId: 'bob', authorName: 'Bob' })));
  });

  it('batch máximo (local novo + foto + trava + review + auditoria) cabe no limite de acessos', async () => {
    const db = alice();
    const batch = writeBatch(db);
    batch.set(doc(db, 'places/osm-n123'), newPlace());
    batch.set(doc(db, 'reviews/max'), validReview({ placeId: 'osm-n123', placeName: 'Bar do Zé', hasPhoto: true }));
    setAudit(db, batch, 'reviews', 'max', validReview({ placeId: 'osm-n123', placeName: 'Bar do Zé', hasPhoto: true }));
    batch.set(doc(db, 'reviewPhotos/max'), validPhoto());
    batch.set(doc(db, lockPath('alice', 'osm-n123')), validLock('max', { placeId: 'osm-n123' }));
    await assertSucceeds(batch.commit());
  });

  it('forja: review sem trava no batch é negada', async () => {
    await assertFails(addReview(alice(), validReview(), { lock: false }));
    await assertFails(addDoc(collection(alice(), 'reviews'), validReview()));
  });

  it('forja: trava sem review (ou apontando para review já existente) é negada', async () => {
    await assertFails(setDoc(lockRef(alice()), validLock('fantasma')));
    await assertFails(setDoc(lockRef(alice()), validLock('existing')));
  });

  it('forja: trava apontando para outra review do batch é negada', async () => {
    await assertFails(addReview(alice(), validReview(), { id: 'a1', lock: { reviewId: 'outra' } }));
  });

  it('forja: trava de outro uid é negada', async () => {

    await assertFails(addReview(alice(), validReview(), { lockAt: lockPath('bob', 'camaroes') }));

    await assertFails(addReview(bob(), validReview({ authorId: 'bob', authorName: 'Bob' }), { lockAt: lockPath('alice', 'camaroes') }));
  });

  it('forja: placeId da trava diferente do da review (ou do id da trava) é negado', async () => {
    await seedPlace('mangai', 'Mangai');
    await assertFails(addReview(alice(), validReview(), { lock: { placeId: 'mangai' }, lockAt: lockPath('alice', 'mangai') }));
    await assertFails(addReview(alice(), validReview(), { lock: { placeId: 'mangai' } }));
  });

  it('forja: review de local inexistente com trava válida é negada', async () => {
    await assertFails(addReview(alice(), validReview({ placeId: 'inexistente', placeName: 'X' })));
  });

  it('forja: lastAt do cliente é negado', async () => {
    await assertFails(addReview(alice(), validReview(), { lock: { lastAt: Timestamp.now() } }));
    await assertFails(addReview(alice(), validReview(), { lock: { lastAt: Timestamp.fromMillis(0) } }));
  });

  it('forja: lastAt do cliente sobre trava vencida também é negado', async () => {
    await seedLock('alice', 'camaroes', 40);
    await assertFails(addReview(alice(), validReview(), { lock: { lastAt: Timestamp.fromMillis(0) } }));
  });

  it('forja: chave extra ou faltando é negada', async () => {
    await assertFails(addReview(alice(), validReview(), { lock: { count: 1 } }));
    const db = alice();
    const batch = writeBatch(db);
    batch.set(doc(db, 'reviews/x'), validReview());
    setAudit(db, batch, 'reviews', 'x', validReview());
    batch.set(lockRef(db), { lastAt: serverTimestamp(), reviewId: 'x' });
    await assertFails(batch.commit());
  });

  it('forja: renovar a trava sem esperar 30 dias, nem via update parcial', async () => {
    await seedLock('alice', 'camaroes', 10);
    await assertFails(updateDoc(lockRef(alice()), { lastAt: Timestamp.fromMillis(0) }));
    await assertFails(updateDoc(lockRef(alice()), { lastAt: serverTimestamp() }));
  });

  it('forja: renovar trava vencida apontando para review de outro autor é negado', async () => {
    await seedLock('alice', 'camaroes', 40);

    const db = alice();
    const batch = writeBatch(db);
    batch.set(doc(db, 'reviews/debob'), validReview({ authorId: 'bob', authorName: 'Bob' }));
    setAudit(db, batch, 'reviews', 'debob', validReview({ authorId: 'bob', authorName: 'Bob' }));
    batch.set(lockRef(db), validLock('debob'));
    await assertFails(batch.commit());

    await seedReview('bobantiga', { authorId: 'bob', authorName: 'Bob' });
    await assertFails(setDoc(lockRef(alice()), validLock('bobantiga')));
  });

  it('ninguém apaga a trava (nem o dono, nem vencida)', async () => {
    await seedLock('alice', 'camaroes', 10);
    await assertFails(deleteDoc(lockRef(alice())));
    await assertFails(deleteDoc(lockRef(bob())));
    await seedLock('alice', 'camaroes', 40);
    await assertFails(deleteDoc(lockRef(alice())));
  });

  it('só o dono lê a trava (inclusive a ausente); terceiro e anônimo não', async () => {
    await assertSucceeds(getDoc(lockRef(alice())));
    await seedLock('alice', 'camaroes', 10);
    await assertSucceeds(getDoc(lockRef(alice())));
    await assertSucceeds(getDocs(collection(alice(), 'users/alice/reviewLocks')));
    await assertFails(getDoc(lockRef(bob())));
    await assertFails(getDoc(lockRef(anon())));
    await assertFails(getDocs(collection(bob(), 'users/alice/reviewLocks')));
  });

  it('corrida: dois envios simultâneos do mesmo cliente, só um passa', async () => {
    const db = alice();
    const results = await Promise.allSettled([
      addReview(db, validReview(), { id: 'c1' }),
      addReview(db, validReview(), { id: 'c2' }),
    ]);
    const ok = results.filter((r) => r.status === 'fulfilled').length;
    if (ok !== 1) throw new Error('esperava 1 sucesso, vieram ' + ok);
  });

  it('corrida: dois aparelhos do MESMO usuário (contextos separados), só um passa', async () => {
    const phone = env.authenticatedContext('alice').firestore();
    const tablet = env.authenticatedContext('alice').firestore();
    if (phone === tablet) throw new Error('os contextos deveriam ser clientes distintos');
    const results = await Promise.allSettled([
      addReview(phone, validReview(), { id: 'cel' }),
      addReview(tablet, validReview(), { id: 'tab' }),
    ]);
    const ok = results.filter((r) => r.status === 'fulfilled').length;
    if (ok !== 1) throw new Error('esperava 1 sucesso, vieram ' + ok);
    let count = 0;
    await env.withSecurityRulesDisabled(async (ctx) => {
      const snap = await getDocs(query(collection(ctx.firestore(), 'reviews'), where('placeId', '==', 'camaroes')));
      count = snap.size;
    });

    if (count !== 2) throw new Error('esperava 2 reviews, vieram ' + count);
  });

  it('a review com foto também exige a trava', async () => {
    await assertFails(reviewWithPhotoBatch(alice(), { withLock: false }));
    await assertSucceeds(reviewWithPhotoBatch(alice()));
  });
});



const visitLockPath = (uid, placeId) => 'users/' + uid + '/visitLocks/' + placeId;



function validVisit(overrides = {}) {
  return {
    authorId: 'alice',
    authorName: 'Alice',
    placeId: 'camaroes',
    placeName: 'Camarões Potiguar',
    companion: 'amigos',
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

function validVisitLock(visitId, overrides = {}) {
  return {
    lastAt: serverTimestamp(),
    visitId,
    placeId: 'camaroes',
    ...overrides,
  };
}

let visitSeq = 0;




function addVisit(db, data, { id, lock = {}, lockAt, audit = {} } = {}) {
  const visitId = id || 'v' + (++visitSeq);
  const batch = writeBatch(db);
  batch.set(doc(db, 'visits/' + visitId), data);
  if (lock !== false) {
    const placeId = typeof data.placeId === 'string' ? data.placeId : 'camaroes';
    batch.set(
      doc(db, lockAt || visitLockPath(data.authorId, placeId)),
      validVisitLock(visitId, { placeId, ...lock }),
    );
  }
  if (audit !== false) setAudit(db, batch, 'visits', visitId, data, audit);
  return batch.commit();
}


async function seedVisitLock(uid, placeId, hoursAgo, visitId = 'antiga') {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), visitLockPath(uid, placeId)), {
      lastAt: Timestamp.fromMillis(Date.now() - hoursAgo * 60 * 60 * 1000),
      visitId,
      placeId,
    });
  });
}

async function seedVisit(id, overrides = {}) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'visits/' + id), {
      ...validVisit(overrides),
      createdAt: Timestamp.now(),
    });
  });
}

describe('visits + users/{uid}/visitLocks (F15: "Voltei aqui", 12 h)', () => {
  const lockRef = (db, uid = 'alice', placeId = 'camaroes') => doc(db, visitLockPath(uid, placeId));

  it('registra visita: visita + trava no mesmo batch', async () => {
    await assertSucceeds(addVisit(alice(), validVisit(), { id: 'primeira' }));
    const snap = await assertSucceeds(getDoc(lockRef(alice())));
    const d = snap.data();
    if (d.visitId !== 'primeira' || d.placeId !== 'camaroes' || !(d.lastAt instanceof Timestamp)) {
      throw new Error('trava inesperada: ' + JSON.stringify(d));
    }
  });

  it('companhia é opcional (null), mas a chave é obrigatória e do vocabulário', async () => {
    await assertSucceeds(addVisit(alice(), validVisit({ companion: null })));
    await seedVisitLock('alice', 'camaroes', 13);
    await assertFails(addVisit(alice(), validVisit({ companion: 'pet' })));
    const semChave = validVisit();
    delete semChave.companion;
    await assertFails(addVisit(alice(), semChave));
  });

  it('visita e avaliação têm travas separadas (bloqueio do F03 não impede visitar)', async () => {
    await seedLock('alice', 'camaroes', 1);
    await assertSucceeds(addVisit(alice(), validVisit()));
    await unlockAll();
    await assertSucceeds(addReview(alice(), validReview()));
  });

  it('há 3 h e há 11,9 h: negada', async () => {
    await seedVisitLock('alice', 'camaroes', 3);
    await assertFails(addVisit(alice(), validVisit()));
    await seedVisitLock('alice', 'camaroes', 11.9);
    await assertFails(addVisit(alice(), validVisit()));
  });

  it('mesma hora: 2ª visita negada', async () => {
    await assertSucceeds(addVisit(alice(), validVisit(), { id: 'agora1' }));
    await assertFails(addVisit(alice(), validVisit(), { id: 'agora2' }));
  });

  it('após 12 h: visita aceita e trava renovada', async () => {
    await seedVisitLock('alice', 'camaroes', 12.1);
    await assertSucceeds(addVisit(alice(), validVisit(), { id: 'depois' }));
    const snap = await getDoc(lockRef(alice()));
    if (snap.data().visitId !== 'depois') throw new Error('trava não renovada');
    if (Date.now() - snap.data().lastAt.toMillis() > 60 * 1000) {
      throw new Error('lastAt não é a hora do servidor');
    }
  });

  it('a trava é por local e por usuário', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'places/mangai'), { name: 'Mangai', category: 'Restaurante' });
    });
    await seedVisitLock('alice', 'camaroes', 1);
    await assertSucceeds(addVisit(alice(), validVisit({ placeId: 'mangai', placeName: 'Mangai' })));
    await assertSucceeds(addVisit(bob(), validVisit({ authorId: 'bob', authorName: 'Bob' })));
  });

  it('local descoberto (Photon) é criado no batch da visita', async () => {
    const db = alice();
    const batch = writeBatch(db);
    batch.set(doc(db, 'places/osm-n123'), newPlace());
    batch.set(doc(db, 'visits/nova'), validVisit({ placeId: 'osm-n123', placeName: 'Bar do Zé' }));
    setAudit(db, batch, 'visits', 'nova', validVisit({ placeId: 'osm-n123', placeName: 'Bar do Zé' }));
    batch.set(doc(db, visitLockPath('alice', 'osm-n123')), validVisitLock('nova', { placeId: 'osm-n123' }));
    await assertSucceeds(batch.commit());
  });

  it('local inexistente, forjado ou placeName divergente: negado', async () => {
    await assertFails(addVisit(alice(), validVisit({ placeId: 'osm-n999', placeName: 'Bar do Zé' })));
    await assertFails(addVisit(alice(), validVisit({ placeName: 'Outro nome' })));
    const db = alice();
    const batch = writeBatch(db);
    batch.set(doc(db, 'places/osm-n123'), newPlace({ lat: 38.7, lng: -9.1 }));
    batch.set(doc(db, 'visits/nova'), validVisit({ placeId: 'osm-n123', placeName: 'Bar do Zé' }));
    setAudit(db, batch, 'visits', 'nova', validVisit({ placeId: 'osm-n123', placeName: 'Bar do Zé' }));
    batch.set(doc(db, visitLockPath('alice', 'osm-n123')), validVisitLock('nova', { placeId: 'osm-n123' }));
    await assertFails(batch.commit());
  });

  it('forja: anônimo, authorId de outro ou sem perfil', async () => {
    await assertFails(addVisit(anon(), validVisit()));
    await assertFails(addVisit(bob(), validVisit()));
    const ghost = env.authenticatedContext('ghost').firestore();
    await assertFails(addVisit(ghost, validVisit({ authorId: 'ghost', authorName: 'Ghost' })));
  });

  it('forja: authorName diferente do perfil (nunca anônima)', async () => {
    await assertFails(addVisit(alice(), validVisit({ authorName: 'Outra Pessoa' })));
    await assertFails(addVisit(alice(), validVisit({ authorName: '' })));
    await assertFails(addVisit(alice(), validVisit({ authorName: null })));
  });

  it('forja: chave extra (notas, comentário) ou faltando', async () => {
    await assertFails(addVisit(alice(), validVisit({ food: 5 })));
    await assertFails(addVisit(alice(), validVisit({ comment: 'top' })));
    await assertFails(addVisit(alice(), validVisit({ dayPeriod: 'noite' })));
    const semNome = validVisit();
    delete semNome.placeName;
    await assertFails(addVisit(alice(), semNome));
  });

  it('forja: createdAt do cliente', async () => {
    await assertFails(addVisit(alice(), validVisit({ createdAt: Timestamp.now() })));
    await assertFails(addVisit(alice(), validVisit({ createdAt: Timestamp.fromMillis(0) })));
  });

  it('forja: visita sem trava no batch', async () => {
    await assertFails(addVisit(alice(), validVisit(), { lock: false }));
    await assertFails(addDoc(collection(alice(), 'visits'), validVisit()));
  });

  it('forja: trava de outro uid', async () => {
    await assertFails(addVisit(alice(), validVisit(), { lockAt: visitLockPath('bob', 'camaroes') }));
    await assertFails(addVisit(bob(), validVisit({ authorId: 'bob', authorName: 'Bob' }), { lockAt: visitLockPath('alice', 'camaroes') }));
  });

  it('forja: trava sem visita, para visita existente ou para outra visita', async () => {
    await assertFails(setDoc(lockRef(alice()), validVisitLock('fantasma')));
    await seedVisit('existente');
    await assertFails(setDoc(lockRef(alice()), validVisitLock('existente')));
    await assertFails(addVisit(alice(), validVisit(), { id: 'v-a', lock: { visitId: 'outra' } }));
  });

  it('forja: trava de avaliação não serve para a visita (nem o contrário)', async () => {
    const db = alice();
    const batch = writeBatch(db);
    batch.set(doc(db, 'visits/x'), validVisit());
    setAudit(db, batch, 'visits', 'x', validVisit());
    batch.set(doc(db, lockPath('alice', 'camaroes')), validLock('x'));
    await assertFails(batch.commit());
    const batch2 = writeBatch(db);
    batch2.set(doc(db, 'reviews/y'), validReview());
    setAudit(db, batch2, 'reviews', 'y', validReview());
    batch2.set(lockRef(db), validVisitLock('y'));
    await assertFails(batch2.commit());
  });

  it('forja: lastAt do cliente, placeId divergente ou chave extra na trava', async () => {
    await assertFails(addVisit(alice(), validVisit(), { lock: { lastAt: Timestamp.now() } }));
    await seedVisitLock('alice', 'camaroes', 20);
    await assertFails(addVisit(alice(), validVisit(), { lock: { lastAt: Timestamp.fromMillis(0) } }));
    await assertFails(addVisit(alice(), validVisit(), { lock: { placeId: 'mangai' } }));
    await assertFails(addVisit(alice(), validVisit(), { lock: { count: 1 } }));
  });

  it('forja: renovar a trava sem esperar 12 h, nem via update parcial', async () => {
    await seedVisitLock('alice', 'camaroes', 3);
    await assertFails(updateDoc(lockRef(alice()), { lastAt: Timestamp.fromMillis(0) }));
    await assertFails(updateDoc(lockRef(alice()), { lastAt: serverTimestamp() }));
  });

  it('forja: update/delete da visita (nem o autor) e da trava', async () => {
    await seedVisit('existente');
    await assertFails(updateDoc(doc(alice(), 'visits/existente'), { companion: 'casal' }));
    await assertFails(setDoc(doc(alice(), 'visits/existente'), validVisit()));
    await assertFails(deleteDoc(doc(alice(), 'visits/existente')));
    await assertFails(deleteDoc(doc(bob(), 'visits/existente')));
    await seedVisitLock('alice', 'camaroes', 3);
    await assertFails(deleteDoc(lockRef(alice())));
    await seedVisitLock('alice', 'camaroes', 20);
    await assertFails(deleteDoc(lockRef(alice())));
  });

  it('logado lê visitas (consultas do feed e do detalhe); anônimo não', async () => {
    await seedVisit('existente');
    await assertSucceeds(getDoc(doc(bob(), 'visits/existente')));
    await assertFails(getDoc(doc(anon(), 'visits/existente')));
    const feed = await assertSucceeds(getDocs(query(
      collection(bob(), 'visits'),
      where('authorId', 'in', ['alice']),
      orderBy('createdAt', 'desc'),
      limit(100),
    )));
    if (feed.size !== 1) throw new Error('esperava 1 visita, veio ' + feed.size);
    const detail = await assertSucceeds(getDocs(query(
      collection(bob(), 'visits'),
      where('placeId', '==', 'camaroes'),
      where('authorId', 'in', ['alice', 'bob']),
      orderBy('createdAt', 'desc'),
    )));
    if (detail.size !== 1) throw new Error('esperava 1 visita, veio ' + detail.size);
  });

  it('só o dono lê a trava de visita', async () => {
    await assertSucceeds(getDoc(lockRef(alice())));
    await seedVisitLock('alice', 'camaroes', 3);
    await assertSucceeds(getDoc(lockRef(alice())));
    await assertFails(getDoc(lockRef(bob())));
    await assertFails(getDoc(lockRef(anon())));
    await assertFails(getDocs(collection(bob(), 'users/alice/visitLocks')));
  });

  it('priceBand: 1 a 5 e null são aceitos (F27)', async () => {
    for (const band of [1, 2, 3, 4, 5, null]) {

      await seedVisitLock('alice', 'camaroes', 13);
      await assertSucceeds(addVisit(alice(), validVisit({ priceBand: band })));
    }
  });

  it('priceBand: build antigo sem a chave continua aceito (F27)', async () => {
    const data = validVisit();
    delete data.priceBand;
    if ('priceBand' in data) throw new Error('a chave deveria estar ausente');
    await assertSucceeds(addVisit(alice(), data, { id: 'antigo' }));
    let snap;
    await env.withSecurityRulesDisabled(async (ctx) => {
      snap = await getDoc(doc(ctx.firestore(), 'visits/antigo'));
    });
    if ('priceBand' in snap.data()) throw new Error('visita gravada com priceBand');
  });

  it('priceBand válido não abre espaço para chave extra (F27)', async () => {
    await assertFails(addVisit(alice(), validVisit({ priceBand: 2, food: 5 })));
    await assertFails(addVisit(alice(), validVisit({ priceBand: 2, price: 45 })));
    await assertSucceeds(addVisit(alice(), validVisit({ priceBand: 2 })));
  });

  it('priceBand: forja 0, 6, "2", 2.5, true, -1 é negada (F27)', async () => {
    for (const band of [0, 6, '2', 2.5, true, -1, [2]]) {
      await assertFails(addVisit(alice(), validVisit({ priceBand: band })));
    }
  });

  it('F28: visita aceita couvert e taxa opcionais e nega forja', async () => {
    await assertSucceeds(addVisit(alice(), validVisit({ couvert: true, serviceFee: false })));
    for (const extras of [{ couvert: 'não' }, { serviceFee: 1 }, { couvert: true, taxa: 10 }]) {
      await assertFails(addVisit(alice(), validVisit(extras)));
    }
  });

  it('corrida: dois aparelhos ao mesmo tempo, só um passa', async () => {
    const phone = env.authenticatedContext('alice').firestore();
    const tablet = env.authenticatedContext('alice').firestore();
    const results = await Promise.allSettled([
      addVisit(phone, validVisit(), { id: 'cel' }),
      addVisit(tablet, validVisit(), { id: 'tab' }),
    ]);
    const ok = results.filter((r) => r.status === 'fulfilled').length;
    if (ok !== 1) throw new Error('esperava 1 sucesso, vieram ' + ok);
  });
});



const openLockPath = (uid, placeId) => 'users/' + uid + '/openReportLocks/' + placeId;



function validOpenReport(overrides = {}) {
  return {
    authorId: 'alice',
    authorName: 'Alice',
    placeId: 'camaroes',
    open: true,
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

function validOpenLock(reportId, overrides = {}) {
  return {
    lastAt: serverTimestamp(),
    reportId,
    placeId: 'camaroes',
    ...overrides,
  };
}

let openSeq = 0;




function addOpenReport(db, data, { id, lock = {}, lockAt, audit = {} } = {}) {
  const reportId = id || 'o' + (++openSeq);
  const batch = writeBatch(db);
  batch.set(doc(db, 'openReports/' + reportId), data);
  if (lock !== false) {
    const placeId = typeof data.placeId === 'string' ? data.placeId : 'camaroes';
    batch.set(
      doc(db, lockAt || openLockPath(data.authorId, placeId)),
      validOpenLock(reportId, { placeId, ...lock }),
    );
  }
  if (audit !== false) setAudit(db, batch, 'openReports', reportId, data, audit);
  return batch.commit();
}


async function seedOpenLock(uid, placeId, minutesAgo, reportId = 'antigo') {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), openLockPath(uid, placeId)), {
      lastAt: Timestamp.fromMillis(Date.now() - minutesAgo * 60 * 1000),
      reportId,
      placeId,
    });
  });
}

async function seedOpenReport(id, minutesAgo = 0, overrides = {}) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'openReports/' + id), {
      ...validOpenReport(overrides),
      createdAt: Timestamp.fromMillis(Date.now() - minutesAgo * 60 * 1000),
    });
  });
}

describe('openReports + users/{uid}/openReportLocks (F20: "Está aberto agora?", 30 min)', () => {
  const lockRef = (db, uid = 'alice', placeId = 'camaroes') => doc(db, openLockPath(uid, placeId));

  it('relata "Sim" e "Não": relato + trava no mesmo batch', async () => {
    await assertSucceeds(addOpenReport(alice(), validOpenReport(), { id: 'primeiro' }));
    const snap = await assertSucceeds(getDoc(lockRef(alice())));
    const d = snap.data();
    if (d.reportId !== 'primeiro' || d.placeId !== 'camaroes' || !(d.lastAt instanceof Timestamp)) {
      throw new Error('trava inesperada: ' + JSON.stringify(d));
    }
    await assertSucceeds(addOpenReport(bob(), validOpenReport({ authorId: 'bob', authorName: 'Bob', open: false })));
  });

  it('há 10 min e há 29,9 min: negado', async () => {
    await seedOpenLock('alice', 'camaroes', 10);
    await assertFails(addOpenReport(alice(), validOpenReport()));
    await seedOpenLock('alice', 'camaroes', 29.9);
    await assertFails(addOpenReport(alice(), validOpenReport({ open: false })));
  });

  it('mesma hora: 2º relato negado', async () => {
    await assertSucceeds(addOpenReport(alice(), validOpenReport(), { id: 'a1' }));
    await assertFails(addOpenReport(alice(), validOpenReport({ open: false }), { id: 'a2' }));
  });

  it('após 30 min: relato aceito e trava renovada', async () => {
    await seedOpenLock('alice', 'camaroes', 30.5);
    await assertSucceeds(addOpenReport(alice(), validOpenReport(), { id: 'depois' }));
    const snap = await getDoc(lockRef(alice()));
    if (snap.data().reportId !== 'depois') throw new Error('trava não renovada');
    if (Date.now() - snap.data().lastAt.toMillis() > 60 * 1000) {
      throw new Error('lastAt não é a hora do servidor');
    }
  });

  it('a trava é por local e por usuário, e separada da visita (F15)', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'places/mangai'), { name: 'Mangai', category: 'Restaurante' });
    });
    await seedOpenLock('alice', 'camaroes', 1);
    await assertSucceeds(addOpenReport(alice(), validOpenReport({ placeId: 'mangai' })));
    await assertSucceeds(addOpenReport(bob(), validOpenReport({ authorId: 'bob', authorName: 'Bob' })));
    await seedVisitLock('alice', 'mangai', 1);
    await seedOpenLock('alice', 'mangai', 31);
    await assertSucceeds(addOpenReport(alice(), validOpenReport({ placeId: 'mangai' })));
  });

  it('local descoberto (Photon) é criado no batch do relato', async () => {
    const db = alice();
    const batch = writeBatch(db);
    batch.set(doc(db, 'places/osm-n123'), newPlace());
    batch.set(doc(db, 'openReports/novo'), validOpenReport({ placeId: 'osm-n123' }));
    setAudit(db, batch, 'openReports', 'novo', validOpenReport({ placeId: 'osm-n123' }));
    batch.set(doc(db, openLockPath('alice', 'osm-n123')), validOpenLock('novo', { placeId: 'osm-n123' }));
    await assertSucceeds(batch.commit());
  });

  it('local inexistente ou forjado: negado', async () => {
    await assertFails(addOpenReport(alice(), validOpenReport({ placeId: 'osm-n999' })));
    const db = alice();
    const batch = writeBatch(db);
    batch.set(doc(db, 'places/osm-n123'), newPlace({ lat: 38.7, lng: -9.1 }));
    batch.set(doc(db, 'openReports/novo'), validOpenReport({ placeId: 'osm-n123' }));
    setAudit(db, batch, 'openReports', 'novo', validOpenReport({ placeId: 'osm-n123' }));
    batch.set(doc(db, openLockPath('alice', 'osm-n123')), validOpenLock('novo', { placeId: 'osm-n123' }));
    await assertFails(batch.commit());
  });

  it('forja: anônimo, outro autor ou sem perfil', async () => {
    await assertFails(addOpenReport(anon(), validOpenReport()));
    await assertFails(addOpenReport(bob(), validOpenReport()));
    await assertFails(addOpenReport(bob(), validOpenReport(), { lockAt: openLockPath('bob', 'camaroes') }));
    const ghost = env.authenticatedContext('ghost').firestore();
    await assertFails(addOpenReport(ghost, validOpenReport({ authorId: 'ghost', authorName: 'Ghost' })));
  });

  it('forja: authorName diferente do perfil (nunca anônimo)', async () => {
    await assertFails(addOpenReport(alice(), validOpenReport({ authorName: 'Outra Pessoa' })));
    await assertFails(addOpenReport(alice(), validOpenReport({ authorName: '' })));
    await assertFails(addOpenReport(alice(), validOpenReport({ authorName: null })));
  });

  it('forja: open não-bool', async () => {
    for (const open of ['true', 1, 0, null, 'sim', [true], { v: true }]) {
      await assertFails(addOpenReport(alice(), validOpenReport({ open })));
    }
  });

  it('forja: chave extra ou faltando', async () => {
    await assertFails(addOpenReport(alice(), validOpenReport({ queue: 3 })));
    await assertFails(addOpenReport(alice(), validOpenReport({ placeName: 'Camarões Potiguar' })));
    await assertFails(addOpenReport(alice(), validOpenReport({ lat: -5.8 })));
    for (const key of ['authorId', 'authorName', 'placeId', 'open', 'createdAt']) {
      const data = validOpenReport();
      delete data[key];
      await assertFails(addOpenReport(alice(), data));
    }
  });

  it('forja: createdAt do cliente', async () => {
    await assertFails(addOpenReport(alice(), validOpenReport({ createdAt: Timestamp.now() })));
    await assertFails(addOpenReport(alice(), validOpenReport({ createdAt: Timestamp.fromMillis(0) })));
  });

  it('forja: relato sem trava no batch', async () => {
    await assertFails(addOpenReport(alice(), validOpenReport(), { lock: false }));
    await assertFails(addDoc(collection(alice(), 'openReports'), validOpenReport()));
  });

  it('forja: trava de outro uid', async () => {
    await assertFails(addOpenReport(alice(), validOpenReport(), { lockAt: openLockPath('bob', 'camaroes') }));
    await assertFails(addOpenReport(bob(), validOpenReport({ authorId: 'bob', authorName: 'Bob' }), { lockAt: openLockPath('alice', 'camaroes') }));
  });

  it('forja: trava sem relato, para relato existente ou para outro relato', async () => {
    await assertFails(setDoc(lockRef(alice()), validOpenLock('fantasma')));
    await seedOpenReport('existente', 40);
    await assertFails(setDoc(lockRef(alice()), validOpenLock('existente')));
    await assertFails(addOpenReport(alice(), validOpenReport(), { id: 'o-a', lock: { reportId: 'outro' } }));
  });

  it('forja: trava de visita não serve para o relato (nem o contrário)', async () => {
    const db = alice();
    const batch = writeBatch(db);
    batch.set(doc(db, 'openReports/x'), validOpenReport());
    setAudit(db, batch, 'openReports', 'x', validOpenReport());
    batch.set(doc(db, visitLockPath('alice', 'camaroes')), validVisitLock('x'));
    await assertFails(batch.commit());
    const batch2 = writeBatch(db);
    batch2.set(doc(db, 'visits/y'), validVisit());
    setAudit(db, batch2, 'visits', 'y', validVisit());
    batch2.set(lockRef(db), validOpenLock('y'));
    await assertFails(batch2.commit());
  });

  it('forja: lastAt do cliente, placeId divergente ou chave extra na trava', async () => {
    await assertFails(addOpenReport(alice(), validOpenReport(), { lock: { lastAt: Timestamp.now() } }));
    await seedOpenLock('alice', 'camaroes', 40);
    await assertFails(addOpenReport(alice(), validOpenReport(), { lock: { lastAt: Timestamp.fromMillis(0) } }));
    await assertFails(addOpenReport(alice(), validOpenReport(), { lock: { placeId: 'mangai' } }));
    await assertFails(addOpenReport(alice(), validOpenReport(), { lock: { count: 1 } }));
  });

  it('forja: renovar a trava sem esperar 30 min, nem via update parcial', async () => {
    await seedOpenLock('alice', 'camaroes', 10);
    await assertFails(updateDoc(lockRef(alice()), { lastAt: Timestamp.fromMillis(0) }));
    await assertFails(updateDoc(lockRef(alice()), { lastAt: serverTimestamp() }));
  });

  it('forja: update/delete do relato (nem o autor) e da trava', async () => {
    await seedOpenReport('existente', 5);
    await assertFails(updateDoc(doc(alice(), 'openReports/existente'), { open: false }));
    await assertFails(setDoc(doc(alice(), 'openReports/existente'), validOpenReport({ open: false })));
    await assertFails(deleteDoc(doc(alice(), 'openReports/existente')));
    await assertFails(deleteDoc(doc(bob(), 'openReports/existente')));
    await seedOpenLock('alice', 'camaroes', 10);
    await assertFails(deleteDoc(lockRef(alice())));
    await seedOpenLock('alice', 'camaroes', 40);
    await assertFails(deleteDoc(lockRef(alice())));
  });

  it('logado lê relatos (consultas do detalhe e do Perto); anônimo não', async () => {
    await seedOpenReport('recente', 20);
    await seedOpenReport('velho', 200, { authorId: 'bob', authorName: 'Bob', open: false });
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'places/mangai'), { name: 'Mangai', category: 'Restaurante' });
    });
    await seedOpenReport('mangai', 5, { placeId: 'mangai', open: false });
    await assertSucceeds(getDoc(doc(bob(), 'openReports/recente')));
    await assertFails(getDoc(doc(anon(), 'openReports/recente')));
    const since = Timestamp.fromMillis(Date.now() - 3 * 60 * 60 * 1000);
    const detail = await assertSucceeds(getDocs(query(
      collection(bob(), 'openReports'),
      where('placeId', '==', 'camaroes'),
      where('createdAt', '>=', since),
      orderBy('createdAt', 'desc'),
      limit(50),
    )));
    if (detail.size !== 1 || detail.docs[0].id !== 'recente') {
      throw new Error('detalhe: esperava só o relato recente, veio ' + detail.size);
    }
    const nearby = await assertSucceeds(getDocs(query(
      collection(bob(), 'openReports'),
      where('placeId', 'in', ['camaroes', 'mangai']),
      where('createdAt', '>=', since),
      orderBy('createdAt', 'desc'),
      limit(300),
    )));
    const ids = nearby.docs.map((d) => d.id).join(',');
    if (ids !== 'mangai,recente') throw new Error('Perto: veio ' + ids);
  });

  it('só o dono lê a trava de relato', async () => {
    await assertSucceeds(getDoc(lockRef(alice())));
    await seedOpenLock('alice', 'camaroes', 10);
    await assertSucceeds(getDoc(lockRef(alice())));
    await assertFails(getDoc(lockRef(bob())));
    await assertFails(getDoc(lockRef(anon())));
    await assertFails(getDocs(collection(bob(), 'users/alice/openReportLocks')));
  });

  it('corrida: dois aparelhos ao mesmo tempo, só um passa', async () => {
    const phone = env.authenticatedContext('alice').firestore();
    const tablet = env.authenticatedContext('alice').firestore();
    const results = await Promise.allSettled([
      addOpenReport(phone, validOpenReport(), { id: 'cel' }),
      addOpenReport(tablet, validOpenReport({ open: false }), { id: 'tab' }),
    ]);
    const ok = results.filter((r) => r.status === 'fulfilled').length;
    if (ok !== 1) throw new Error('esperava 1 sucesso, vieram ' + ok);
  });
});



describe('auditLog (F04: auditoria de avaliações, visitas e relatos)', () => {

  async function readAudit(collectionName, docId) {
    let snap;
    await env.withSecurityRulesDisabled(async (ctx) => {
      snap = await getDoc(doc(ctx.firestore(), auditPath(collectionName, docId)));
    });
    return snap;
  }

  async function seedAudit(collectionName, docId) {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), auditPath(collectionName, docId)), {
        ...validAudit(collectionName, docId),
        at: Timestamp.now(),
      });
    });
  }

  beforeEach(unlockAll);

  it('avaliação grava a entrada com chaves exatas, autor e hora do servidor', async () => {
    await assertSucceeds(addReview(alice(), validReview(), { id: 'aud1' }));
    const d = (await readAudit('reviews', 'aud1')).data();
    const keys = Object.keys(d).sort().join(',');
    if (keys !== 'action,actorUid,at,collection,docId,placeId') throw new Error('chaves: ' + keys);
    if (d.actorUid !== 'alice' || d.action !== 'create' || d.collection !== 'reviews' || d.docId !== 'aud1' || d.placeId !== 'camaroes') {
      throw new Error('entrada inesperada: ' + JSON.stringify(d));
    }
    if (!(d.at instanceof Timestamp) || Date.now() - d.at.toMillis() > 60 * 1000) {
      throw new Error('at não é a hora do servidor');
    }
  });

  it('visita e relato também gravam a entrada', async () => {
    await assertSucceeds(addVisit(alice(), validVisit(), { id: 'audv' }));
    await assertSucceeds(addOpenReport(alice(), validOpenReport(), { id: 'audo' }));
    if (!(await readAudit('visits', 'audv')).exists()) throw new Error('sem auditoria da visita');
    if (!(await readAudit('openReports', 'audo')).exists()) throw new Error('sem auditoria do relato');
  });

  it('avaliação com foto e com local novo: batch com a auditoria passa', async () => {
    await assertSucceeds(reviewWithPhotoBatch(alice(), { id: 'comfoto' }));
    const db = alice();
    const batch = writeBatch(db);
    batch.set(doc(db, 'places/osm-n123'), newPlace());
    const data = validReview({ placeId: 'osm-n123', placeName: 'Bar do Zé' });
    batch.set(doc(db, 'reviews/novo'), data);
    batch.set(doc(db, lockPath('alice', 'osm-n123')), validLock('novo', { placeId: 'osm-n123' }));
    setAudit(db, batch, 'reviews', 'novo', data);
    await assertSucceeds(batch.commit());
  });

  it('forja: review, visita ou relato sem a auditoria no batch', async () => {
    await assertFails(addReview(alice(), validReview(), { audit: false }));
    await assertFails(reviewWithPhotoBatch(alice(), { id: 'semaud', withAudit: false }));
    await assertFails(addVisit(alice(), validVisit(), { audit: false }));
    await assertFails(addOpenReport(alice(), validOpenReport(), { audit: false }));
  });

  it('forja: auditoria sem o doc auditado no batch', async () => {
    await assertFails(setDoc(doc(alice(), auditPath('reviews', 'fantasma')), validAudit('reviews', 'fantasma')));
    await assertFails(setDoc(doc(alice(), auditPath('visits', 'fantasma')), validAudit('visits', 'fantasma')));
    await assertFails(setDoc(doc(alice(), auditPath('openReports', 'fantasma')), validAudit('openReports', 'fantasma')));
  });

  it('forja: auditoria de doc já existente (antigo, sem backfill)', async () => {
    await assertFails(setDoc(doc(alice(), auditPath('reviews', 'existing')), validAudit('reviews', 'existing')));
    await seedVisit('velha');
    await assertFails(setDoc(doc(alice(), auditPath('visits', 'velha')), validAudit('visits', 'velha')));
    await seedOpenReport('velho', 40);
    await assertFails(setDoc(doc(alice(), auditPath('openReports', 'velho')), validAudit('openReports', 'velho')));
  });

  it('forja: outro actorUid ou alvo de outro autor', async () => {
    await assertFails(addReview(alice(), validReview(), { audit: { actorUid: 'bob' } }));
    await assertFails(addVisit(alice(), validVisit(), { audit: { actorUid: 'bob' } }));
    await assertFails(addOpenReport(alice(), validOpenReport(), { audit: { actorUid: 'bob' } }));

    await assertFails(setDoc(doc(alice(), auditPath('reviews', 'dobob')), validAudit('reviews', 'dobob')));
    const db = bob();
    const data = validReview({ authorId: 'bob', authorName: 'Bob' });
    const batch = writeBatch(db);
    batch.set(doc(db, 'reviews/dobob'), data);
    batch.set(doc(db, lockPath('bob', 'camaroes')), validLock('dobob'));
    batch.set(doc(db, auditPath('reviews', 'dobob')), validAudit('reviews', 'dobob'));
    await assertFails(batch.commit());
  });

  it('forja: placeId diferente do alvo', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'places/mangai'), { name: 'Mangai', category: 'Restaurante' });
    });
    await assertFails(addReview(alice(), validReview(), { audit: { placeId: 'mangai' } }));
    await assertFails(addVisit(alice(), validVisit(), { audit: { placeId: 'mangai' } }));
    await assertFails(addOpenReport(alice(), validOpenReport(), { audit: { placeId: 'mangai' } }));
  });

  it('forja: id fora de {coleção}-{docId}, coleção trocada ou fora da lista', async () => {

    await assertFails(addReview(alice(), validReview(), { id: 'a1', audit: { docId: 'a2' } }));

    await assertFails(addReview(alice(), validReview(), { id: 'a3', audit: { collection: 'visits' } }));

    const db = alice();
    const batch = writeBatch(db);
    batch.set(doc(db, 'users/alice/saved/camaroes'), { createdAt: serverTimestamp() });
    batch.set(doc(db, 'auditLog/saved-camaroes'), validAudit('saved', 'camaroes'));
    await assertFails(batch.commit());

    const b2 = writeBatch(db);
    b2.set(doc(db, 'reviews/a4'), validReview());
    b2.set(doc(db, lockPath('alice', 'camaroes')), validLock('a4'));
    b2.set(doc(db, 'auditLog/a4'), validAudit('reviews', 'a4'));
    await assertFails(b2.commit());
  });

  it('forja: at do cliente, action diferente de create, chave extra ou faltando', async () => {
    await assertFails(addReview(alice(), validReview(), { audit: { at: Timestamp.now() } }));
    await assertFails(addReview(alice(), validReview(), { audit: { at: Timestamp.fromMillis(0) } }));
    await assertFails(addReview(alice(), validReview(), { audit: { action: 'update' } }));
    await assertFails(addReview(alice(), validReview(), { audit: { action: 'delete' } }));
    await assertFails(addReview(alice(), validReview(), { audit: { ip: '1.2.3.4' } }));
    await assertFails(addReview(alice(), validReview(), { audit: { placeId: null } }));
    for (const key of ['actorUid', 'action', 'collection', 'docId', 'placeId', 'at']) {
      const db = alice();
      const batch = writeBatch(db);
      batch.set(doc(db, 'reviews/k-' + key), validReview());
      batch.set(doc(db, lockPath('alice', 'camaroes')), validLock('k-' + key));
      const audit = validAudit('reviews', 'k-' + key);
      delete audit[key];
      batch.set(doc(db, auditPath('reviews', 'k-' + key)), audit);
      await assertFails(batch.commit());
    }
  });

  it('anônimo não grava auditoria', async () => {
    await assertFails(setDoc(doc(anon(), auditPath('reviews', 'x')), validAudit('reviews', 'x')));
  });

  it('ninguém lê, altera nem apaga pelo app (nem o autor)', async () => {
    await assertSucceeds(addReview(alice(), validReview(), { id: 'lida' }));
    await assertFails(getDoc(doc(alice(), auditPath('reviews', 'lida'))));
    await assertFails(getDoc(doc(bob(), auditPath('reviews', 'lida'))));
    await assertFails(getDoc(doc(anon(), auditPath('reviews', 'lida'))));
    await assertFails(getDocs(collection(alice(), 'auditLog')));
    await assertFails(getDocs(query(collection(alice(), 'auditLog'), where('actorUid', '==', 'alice'))));
    await assertFails(updateDoc(doc(alice(), auditPath('reviews', 'lida')), { placeId: 'mangai' }));
    await assertFails(setDoc(doc(alice(), auditPath('reviews', 'lida')), validAudit('reviews', 'lida')));
    await assertFails(deleteDoc(doc(alice(), auditPath('reviews', 'lida'))));
    await seedAudit('visits', 'semar');
    await assertFails(deleteDoc(doc(alice(), auditPath('visits', 'semar'))));
  });

  it('retry depois de falha reusa o mesmo id (o batch negado não gravou nada)', async () => {
    const data = validReview({ placeId: 'osm-n123', placeName: 'Bar do Zé' });

    await assertFails(addReview(alice(), data, { id: 'retry' }));
    if ((await readAudit('reviews', 'retry')).exists()) throw new Error('auditoria gravada sem a review');

    const db = alice();
    const batch = writeBatch(db);
    batch.set(doc(db, 'places/osm-n123'), newPlace());
    batch.set(doc(db, 'reviews/retry'), data);
    batch.set(doc(db, lockPath('alice', 'osm-n123')), validLock('retry', { placeId: 'osm-n123' }));
    setAudit(db, batch, 'reviews', 'retry', data);
    await assertSucceeds(batch.commit());


    await assertFails(addReview(alice(), data, { id: 'retry' }));
  });
});

describe('Onda 5 — titularidade e preferências privadas', () => {
  it('pedido privado só nasce pendente para local existente e não é alterável pelo cliente', async () => {
    const ref = doc(alice(), 'users/alice/ownershipRequests/camaroes');
    await assertSucceeds(setDoc(ref, { status: 'pending', createdAt: serverTimestamp() }));
    await assertSucceeds(getDoc(ref));
    await assertFails(getDoc(doc(bob(), ref.path)));
    await assertFails(getDoc(doc(anon(), ref.path)));
    await assertFails(updateDoc(ref, { status: 'approved' }));
    await assertFails(deleteDoc(ref));
    await assertFails(setDoc(doc(bob(), 'users/alice/ownershipRequests/other'), { status: 'pending', createdAt: serverTimestamp() }));
    await assertFails(setDoc(doc(alice(), 'users/alice/ownershipRequests/missing'), { status: 'pending', createdAt: serverTimestamp() }));
  });
  it('nega autoaprovação, timestamp forjado, documento pessoal e gravação de titular', async () => {
    for (const data of [
      { status: 'approved', createdAt: serverTimestamp() },
      { status: 'pending', createdAt: Timestamp.fromMillis(1) },
      { status: 'pending', createdAt: serverTimestamp(), cpf: 'não permitido' },
    ]) await assertFails(setDoc(doc(alice(), 'users/alice/ownershipRequests/camaroes'), data));
    await assertFails(setDoc(doc(alice(), 'placeOwners/camaroes'), { uid: 'alice', verifiedAt: serverTimestamp() }));
  });
  it('autenticados leem titularidade, mas nunca criam, editam ou apagam', async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'placeOwners/camaroes'), { uid: 'alice', verifiedAt: Timestamp.now() }));
    await assertSucceeds(getDoc(doc(bob(), 'placeOwners/camaroes')));
    await assertFails(getDoc(doc(anon(), 'placeOwners/camaroes')));
    await assertFails(updateDoc(doc(alice(), 'placeOwners/camaroes'), { uid: 'bob' }));
    await assertFails(deleteDoc(doc(alice(), 'placeOwners/camaroes')));
  });
  it('pedido pendente não bloqueia contribuição; aprovado bloqueia todas as chamadas diretas no próprio local', async () => {
    await setDoc(doc(alice(), 'users/alice/ownershipRequests/camaroes'), { status: 'pending', createdAt: serverTimestamp() });
    await assertSucceeds(addReview(alice(), validReview({ tags: ['vegano'] })));
    await unlockAll();
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'placeOwners/camaroes'), { uid: 'alice', verifiedAt: Timestamp.now() }));
    await assertFails(addReview(alice(), validReview()));
    await assertFails(addVisit(alice(), validVisit({ priceBand: 2 })));
    await assertFails(addOpenReport(alice(), validOpenReport()));

    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'placeOwners/camaroes'), { uid: 'bob', verifiedAt: Timestamp.now() }));
    await assertSucceeds(addVisit(alice(), validVisit()));
    await assertSucceeds(getDoc(doc(alice(), 'reviews/existing')));
  });
  it('preferências persistem no documento privado com vocabulário exato, sem duplicatas nem privilégios', async () => {
    const ref = doc(alice(), 'users/alice/preferences/food');
    await assertSucceeds(setDoc(ref, { tags: ['vegano', 'integral'] }));
    await assertSucceeds(getDoc(ref));
    await assertFails(getDoc(doc(bob(), ref.path)));
    await assertFails(getDoc(doc(anon(), ref.path)));
    await assertFails(setDoc(doc(bob(), ref.path), { tags: [] }));
    for (const data of [{ tags: ['vegano', 'vegano'] }, { tags: ['sem-gluten'] }, { tags: 'vegano' }, { tags: [], owner: true }, {}]) {
      await assertFails(setDoc(ref, data));
    }
    await assertSucceeds(setDoc(ref, { tags: [] }));
    await assertFails(setDoc(doc(alice(), 'users/alice/preferences/other'), { tags: [] }));
  });
  it('review aceita tags opcionais válidas e nega tags forjadas, duplicatas e contadores', async () => {
    for (const tags of [[], ['caseiro', 'vegetariano', 'vegano', 'low-carb', 'integral']]) {
      await unlockAll();
      await assertSucceeds(addReview(alice(), validReview({ tags })));
    }
    for (const tags of [['vegano', 'vegano'], ['sem-gluten'], null, 'vegano', [1]]) {
      await unlockAll();
      await assertFails(addReview(alice(), validReview({ tags })));
    }
    await unlockAll();
    await assertFails(addReview(alice(), validReview({ tags: ['vegano'], tagCounts: { vegano: 3 } })));
    await assertFails(updateDoc(doc(alice(), 'reviews/existing'), { tags: ['vegano'] }));
  });
  it('F30: tags de comida caseira valem na review e nas preferências, todas as 8 juntas', async () => {
    const all = ['caseiro', 'vegetariano', 'vegano', 'low-carb', 'integral', 'marmita', 'quentinha', 'self-service'];
    for (const tags of [['marmita'], ['quentinha', 'self-service'], all]) {
      await unlockAll();
      await assertSucceeds(addReview(alice(), validReview({ tags })));
    }
    for (const tags of [['self-service-por-quilo'], ['marmita', 'marmita'], [...all, 'sem-gluten']]) {
      await unlockAll();
      await assertFails(addReview(alice(), validReview({ tags })));
    }
    const ref = doc(alice(), 'users/alice/preferences/food');
    await assertSucceeds(setDoc(ref, { tags: ['marmita', 'self-service'] }));
    await assertSucceeds(setDoc(ref, { tags: all }));
  });
});

describe('Administração de titularidade', () => {
  const requestPath = 'users/alice/ownershipRequests/camaroes';
  const admin = () => env.authenticatedContext('operator').firestore();
  async function setup() {
    await env.withSecurityRulesDisabled(async ctx => {
      await setDoc(doc(ctx.firestore(), 'admins/operator'), { enabled: true });
      await setDoc(doc(ctx.firestore(), requestPath), { status: 'pending', createdAt: Timestamp.fromMillis(1000) });
    });
  }
  function decision(db, approve = true, overrides = {}, owner = true) {
    const batch = writeBatch(db);
    const trio = { operator: 'operator', reason: 'Verificação presencial', decidedAt: serverTimestamp() };
    batch.update(doc(db, requestPath), { ...trio, status: approve ? 'approved' : 'rejected', [approve ? 'approval' : 'rejection']: trio, ...overrides });
    if (approve && owner) batch.set(doc(db, 'placeOwners/camaroes'), { uid: 'alice', verifiedAt: serverTimestamp() });
    return batch.commit();
  }
  beforeEach(setup);
  it('membership própria somente leitura, sem enumeração nem auto concessão', async () => {
    await assertSucceeds(getDoc(doc(admin(), 'admins/operator')));
    await assertFails(getDocs(collection(admin(), 'admins')));
    await assertFails(getDoc(doc(alice(), 'admins/operator')));
    await assertFails(setDoc(doc(alice(), 'admins/alice'), { enabled: true }));
    await assertFails(updateDoc(doc(admin(), 'admins/operator'), { enabled: false }));
  });
  it('fila collectionGroup exclusiva de administradores enabled', async () => {
    const q = db => query(collectionGroup(db, 'ownershipRequests'), where('status', '==', 'pending'), orderBy('createdAt'), limit(20));
    await assertSucceeds(getDocs(q(admin())));
    await assertFails(getDocs(q(alice())));
    await env.withSecurityRulesDisabled(ctx => updateDoc(doc(ctx.firestore(), 'admins/operator'), { enabled: false }));
    await assertFails(getDocs(q(admin())));
    await assertFails(decision(admin()));
  });
  it('aprovação e titular são inseparáveis e decisão final é imutável', async () => {
    await assertFails(decision(admin(), true, {}, false));
    await assertFails(setDoc(doc(admin(), 'placeOwners/camaroes'), { uid: 'alice', verifiedAt: serverTimestamp() }));
    await assertSucceeds(decision(admin()));
    await assertFails(decision(admin()));
    await assertFails(updateDoc(doc(admin(), requestPath), { reason: 'mudado' }));
    const result = await getDoc(doc(alice(), requestPath));
    if (result.data().reason !== 'Verificação presencial') throw Error('Motivo ausente');
  });
  it('reprovação dispensa titular; motivo é obrigatório, aparado e limitado', async () => {
    for (const reason of ['', ' espaço ', 'x'.repeat(501)]) {
      await assertFails(decision(admin(), false, { reason }));
    }
    await assertFails(decision(admin(), false, { createdAt: serverTimestamp() }));
    await assertFails(decision(admin(), false, { operator: 'forjado' }));
    await assertFails(decision(admin(), false, { rejection: { operator: 'operator', reason: 'outro', decidedAt: serverTimestamp() } }));
    await assertSucceeds(decision(admin(), false));
    await assertFails(decision(admin(), false));
  });
  it('nega solicitante comum e administrador decidindo próprio pedido', async () => {
    await assertFails(decision(alice()));
    await env.withSecurityRulesDisabled(ctx => setDoc(doc(ctx.firestore(), 'admins/alice'), { enabled: true }));
    await assertFails(decision(alice(), false, { operator: 'alice', rejection: { operator: 'alice', reason: 'Verificação presencial', decidedAt: serverTimestamp() } }));
  });
  it('nega substituir qualquer titular inclusive o mesmo UID', async () => {
    await env.withSecurityRulesDisabled(ctx => setDoc(doc(ctx.firestore(), 'placeOwners/camaroes'), { uid: 'alice', verifiedAt: Timestamp.now() }));
    await assertFails(decision(admin()));
  });
  it('concorrência permite apenas uma decisão final', async () => {
    const results = await Promise.allSettled([decision(admin()), decision(admin(), false)]);
    if (results.filter(r => r.status === 'fulfilled').length !== 1) throw Error('Duas decisões ou nenhuma');
  });
  it('nega pedido/local inexistente e timestamps forjados', async () => {
    await assertFails(decision(admin(), false, { decidedAt: Timestamp.fromMillis(1000) }));
    await env.withSecurityRulesDisabled(ctx => deleteDoc(doc(ctx.firestore(), 'places/camaroes')));
    await assertFails(decision(admin(), false));
    await env.withSecurityRulesDisabled(ctx => deleteDoc(doc(ctx.firestore(), requestPath)));
    await assertFails(decision(admin(), false));
  });
});


it('fila administrativa pagina 45 caminhos com data e local iguais sem duplicatas', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'admins/operator'), { enabled: true });
    for (let i = 0; i < 45; i++) {
      await setDoc(doc(db, `users/u${String(i).padStart(2, '0')}/ownershipRequests/camaroes`), { status: 'pending', createdAt: Timestamp.fromMillis(1000) });
    }
  });
  const db = env.authenticatedContext('operator').firestore();
  const paths = []; let cursor; let pages = 0;
  do {
    const filters = [where('status', '==', 'pending'), orderBy('createdAt'), orderBy(documentId())];
    if (cursor) filters.push(startAfter(cursor));
    const page = await assertSucceeds(getDocs(query(collectionGroup(db, 'ownershipRequests'), ...filters, limit(20))));
    pages++; paths.push(...page.docs.map(d => d.ref.path));
    cursor = page.size === 20 ? page.docs.at(-1) : null;
    if (pages > 3) throw Error('Cursor não termina');
  } while (cursor);
  if (paths.length !== 45 || new Set(paths).size !== 45 || pages !== 3) throw Error('Paginação com perda ou duplicação');
});


describe('Onda 6 — respostas, privacidade, fila e Destaque', () => {
  async function seedOwner() {
    await env.withSecurityRulesDisabled(ctx => setDoc(doc(ctx.firestore(), 'placeOwners/camaroes'), {uid:'bob', verifiedAt:Timestamp.now()}));
  }
  function replyBatch(db, overrides = {}, audit = true) {
    const data = {authorId:'bob',authorName:'Bob',placeId:'camaroes',reviewId:'existing',text:'Obrigado!',createdAt:serverTimestamp(),...overrides};
    const batch=writeBatch(db);
    batch.set(doc(db,'ownerReplies/existing'),data);
    if(audit) setAudit(db,batch,'ownerReplies','existing',data);
    return batch.commit();
  }
  function queueBatch(db, id, overrides = {}, {audit = true, lock = true} = {}) {
    const data={authorId:'alice',authorName:'Alice',placeId:'camaroes',minutes:10,createdAt:serverTimestamp(),...overrides};
    const batch=writeBatch(db);
    batch.set(doc(db,'queueReports/'+id),data);
    if(audit) setAudit(db,batch,'queueReports',id,data);
    if(lock) batch.set(doc(db,'users/'+data.authorId+'/queueReportLocks/camaroes'), {lastAt:serverTimestamp(),reportId:id,placeId:'camaroes'});
    return batch.commit();
  }
  it('titular atual responde cliente não seguido; resposta/auditoria imutáveis sobrevivem à revogação', async () => {
    await seedOwner();
    await assertSucceeds(replyBatch(bob()));
    await assertSucceeds(getDoc(doc(alice(),'ownerReplies/existing')));
    await assertFails(replyBatch(bob()));
    await assertFails(updateDoc(doc(bob(),'ownerReplies/existing'),{text:'editado'}));
    await assertFails(deleteDoc(doc(bob(),'ownerReplies/existing')));
    await env.withSecurityRulesDisabled(ctx => deleteDoc(doc(ctx.firestore(),'placeOwners/camaroes')));
    await assertSucceeds(getDoc(doc(alice(),'ownerReplies/existing')));
    await env.withSecurityRulesDisabled(async ctx => {
      const data=(await getDoc(doc(ctx.firestore(),'reviews/existing'))).data();
      require('node:assert/strict').equal(data.food,4);
      require('node:assert/strict').equal((await getDoc(doc(ctx.firestore(),'auditLog/ownerReplies-existing'))).data().actorUid,'bob');
    });
  });
  it('titular falso, identidade/hora forjadas e falta de auditoria são negados', async () => {
    await assertFails(replyBatch(bob()));
    await seedOwner();
    await assertFails(replyBatch(alice(),{authorId:'alice',authorName:'Alice'}));
    await assertFails(replyBatch(bob(),{authorName:'Forjado'}));
    await assertFails(replyBatch(bob(),{createdAt:Timestamp.now()}));
    await assertFails(replyBatch(bob(),{},false));
    await assertFails(replyBatch(bob(),{extra:true}));
    for(const text of ['', ' ', ' fora ', 'x'.repeat(1001)]) await assertFails(replyBatch(bob(),{text}));
    await assertSucceeds(replyBatch(bob(),{text:'x'.repeat(1000)}));
  });
  it('preferência privada exata e silent booleano; legado público e histórico imutável', async () => {
    const ref=doc(alice(),'users/alice/preferences/privacy');
    await assertSucceeds(setDoc(ref,{silent:true}));
    await assertFails(getDoc(doc(bob(),'users/alice/preferences/privacy')));
    await assertFails(setDoc(ref,{silent:true,extra:1}));
    await assertFails(setDoc(ref,{silent:'true'}));
    await assertSucceeds(addReview(alice(),validReview({silent:true,tags:['vegano'],priceBand:3}),{id:'silent'}));
    await assertFails(updateDoc(doc(alice(),'reviews/silent'),{silent:false}));
    await assertSucceeds(setDoc(ref,{silent:false}));
    await assertSucceeds(getDoc(doc(bob(),'reviews/silent')));
    await assertSucceeds(freshReview(alice(),validReview(),{id:'legacy'}));
    await assertFails(freshReview(alice(),validReview({silent:1}),{id:'bad'}));
    await assertSucceeds(addVisit(alice(),validVisit({silent:true}),{id:'silent-visit'}));
  });
  it('fila valida inteiro 0–180, identidade, schema, horário e par atômico', async () => {
    for(const minutes of [-1,181,1.5,'10',null]) await assertFails(queueBatch(alice(),'bad'+String(minutes),{minutes}));
    await assertFails(queueBatch(alice(),'bad-name',{authorName:'Forjado'}));
    await assertFails(queueBatch(alice(),'bad-time',{createdAt:Timestamp.now()}));
    await assertFails(queueBatch(alice(),'bad-extra',{lat:0}));
    await assertFails(queueBatch(alice(),'no-audit',{}, {audit:false}));
    await assertFails(queueBatch(alice(),'no-lock',{}, {lock:false}));
    await assertSucceeds(queueBatch(alice(),'zero',{minutes:0}));
    await assertFails(queueBatch(alice(),'cooldown'));
    await assertFails(updateDoc(doc(alice(),'queueReports/zero'),{minutes:1}));
    await assertFails(deleteDoc(doc(alice(),'users/alice/queueReportLocks/camaroes')));
    await env.withSecurityRulesDisabled(ctx => setDoc(doc(ctx.firestore(),'users/alice/queueReportLocks/camaroes'),{
      lastAt:Timestamp.fromMillis(Date.now()-31*60000),reportId:'zero',placeId:'camaroes'}));
    await assertSucceeds(queueBatch(alice(),'max',{minutes:180}));
  });
  it('titular não relata própria fila e SDK não pode forjar auditoria/trava isolada', async () => {
    await seedOwner();
    await assertFails(queueBatch(bob(),'owner',{authorId:'bob',authorName:'Bob'}));
    await assertFails(setDoc(doc(alice(),'users/alice/queueReportLocks/camaroes'),{lastAt:serverTimestamp(),reportId:'inventado',placeId:'camaroes'}));
    await assertFails(setDoc(doc(alice(),'auditLog/queueReports-inventado'),validAudit('queueReports','inventado')));
  });
  it('batch máximo descoberto+relato+trava+auditoria respeita limite de acessos', async () => {
    const db=alice(), id='osm-n123';
    const batch=writeBatch(db);

    batch.set(doc(db,'places/'+id), {
      name:'Local',category:'Bar',neighborhood:'',city:'',address:'',lat:-23.5,lng:-46.6,
      geohash:'6gyf4bf0v',osmId:'node/123',source:'osm',createdBy:'alice',createdAt:serverTimestamp(),
    });
    const data={authorId:'alice',authorName:'Alice',placeId:id,minutes:20,createdAt:serverTimestamp()};
    batch.set(doc(db,'queueReports/discovered'),data);
    batch.set(doc(db,'users/alice/queueReportLocks/'+id),{lastAt:serverTimestamp(),reportId:'discovered',placeId:id});
    setAudit(db,batch,'queueReports','discovered',data);
    await assertSucceeds(batch.commit());
  });
  it('slots são negados sem flag/false e cliente nunca grava flag ou slot', async () => {
    const ref=doc(alice(),'sponsoredSlots/slot');
    await env.withSecurityRulesDisabled(ctx => setDoc(doc(ctx.firestore(),'sponsoredSlots/slot'),{
      placeId:'camaroes',startsAt:Timestamp.fromMillis(Date.now()-60000),endsAt:Timestamp.fromMillis(Date.now()+60000)}));
    await assertFails(getDoc(ref));
    await assertFails(setDoc(doc(alice(),'config/features'),{sponsorshipEnabled:true}));
    await assertFails(setDoc(ref,{placeId:'camaroes'}));
    await seedOwner();
    await env.withSecurityRulesDisabled(ctx => setDoc(doc(ctx.firestore(),'config/features'),{sponsorshipEnabled:false}));
    await assertFails(getDoc(ref));
    await env.withSecurityRulesDisabled(ctx => setDoc(doc(ctx.firestore(),'config/features'),{sponsorshipEnabled:true,sponsoredSlotIds:['slot']}));
    const flags = await getDoc(doc(alice(),'config/features'));
    for (const id of flags.data().sponsoredSlotIds) {
      await assertSucceeds(getDoc(doc(alice(),'sponsoredSlots/'+id)));
    }
    await assertFails(updateDoc(ref,{endsAt:Timestamp.now()}));
    await env.withSecurityRulesDisabled(ctx => deleteDoc(doc(ctx.firestore(),'placeOwners/camaroes')));
    await assertFails(getDoc(ref));
  });
  it('slots vencidos ou futuros não são lidos nem com flag true e titular', async () => {
    await seedOwner();
    await env.withSecurityRulesDisabled(async ctx => {
      const db=ctx.firestore();
      await setDoc(doc(db,'config/features'),{sponsorshipEnabled:true});
      for(const [id,start,end] of [['expired',-120000,-60000],['future',60000,120000]]) {
        await setDoc(doc(db,'sponsoredSlots/'+id),{placeId:'camaroes',startsAt:Timestamp.fromMillis(Date.now()+start),endsAt:Timestamp.fromMillis(Date.now()+end)});
      }
    });
    await assertFails(getDoc(doc(alice(),'sponsoredSlots/expired')));
    await assertFails(getDoc(doc(alice(),'sponsoredSlots/future')));
  });
  it('SDK cliente reconcilia batch tardio por ID, valida auditoria/trava, impede retry duplicado e permite novo envio após cooldown', async () => {
    const db=alice();
    let writes=0;

    const operation=new Promise(resolve=>setTimeout(resolve,80)).then(()=>{
      writes++;return queueBatch(db,'sdk-attempt',{minutes:10});
    });
    const timeout=new Promise((_,reject)=>setTimeout(()=>reject(new Error('timeout')),10));
    await require('node:assert/strict').rejects(Promise.race([operation,timeout]),/timeout/);

    await operation;
    const saved=await getDoc(doc(db,'queueReports/sdk-attempt'));
    require('node:assert/strict').equal(saved.data().minutes,10);
    const lock=await getDoc(doc(db,'users/alice/queueReportLocks/camaroes'));
    require('node:assert/strict').equal(lock.data().reportId,'sdk-attempt');
    require('node:assert/strict').equal(writes,1);
    await assertFails(queueBatch(db,'sdk-attempt',{minutes:40}));
    await assertFails(queueBatch(db,'sdk-too-soon',{minutes:40}));
    await env.withSecurityRulesDisabled(async ctx=>{
      const admin=ctx.firestore();
      const audit=await getDoc(doc(admin,'auditLog/queueReports-sdk-attempt'));
      require('node:assert/strict').equal(audit.data().actorUid,'alice');
      await setDoc(doc(admin,'users/alice/queueReportLocks/camaroes'),{
        placeId:'camaroes',reportId:'sdk-attempt',lastAt:Timestamp.fromMillis(Date.now()-31*60000),
      });
    });
    await assertSucceeds(queueBatch(db,'sdk-next',{minutes:40}));
    require('node:assert/strict').equal((await getDoc(doc(db,'queueReports/sdk-next'))).data().minutes,40);
    require('node:assert/strict').equal((await getDoc(doc(db,'queueReports/sdk-attempt'))).data().minutes,10);
  });

});
