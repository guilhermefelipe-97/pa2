// Testes das Security Rules do NaÁrea. Como rodar: ver app/README.md (seção "Testes das Rules").
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
  arrayUnion,
  arrayRemove,
  writeBatch,
  Bytes,
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

/// JPEG falso de [n] bytes (as Rules só olham tipo e tamanho).
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

/// Avaliação com foto: review + reviewPhotos/{mesmo id} num único batch.
function reviewWithPhotoBatch(db, { id = 'nova', review = {}, photo = {}, withReview = true, withPhoto = true } = {}) {
  const batch = writeBatch(db);
  if (withReview) batch.set(doc(db, 'reviews/' + id), validReview({ hasPhoto: true, ...review }));
  if (withPhoto) batch.set(doc(db, 'reviewPhotos/' + id), validPhoto(photo));
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

  it('nome é imutável: nem o dono renomeia (authorName desnormalizado ficaria desatualizado)', async () => {
    await assertFails(updateDoc(doc(alice(), 'users/alice'), { displayName: 'Alice S', displayNameLower: 'alice s' }));
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
});

describe('places', () => {
  it('logado lê; anônimo não', async () => {
    await assertSucceeds(getDoc(doc(alice(), 'places/camaroes')));
    await assertFails(getDoc(doc(anon(), 'places/camaroes')));
  });

  it('cliente nunca escreve', async () => {
    await assertFails(setDoc(doc(alice(), 'places/novo'), { name: 'X' }));
    await assertFails(updateDoc(doc(alice(), 'places/camaroes'), { name: 'X' }));
    await assertFails(deleteDoc(doc(alice(), 'places/camaroes')));
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
    await assertSucceeds(addDoc(collection(alice(), 'reviews'), validReview()));
  });

  it('cria avaliação válida sem companhia (null)', async () => {
    await assertSucceeds(addDoc(collection(alice(), 'reviews'), validReview({ companion: null })));
  });

  it('anônimo não avalia', async () => {
    await assertFails(addDoc(collection(anon(), 'reviews'), validReview()));
  });

  it('não forja authorId de outro uid', async () => {
    await assertFails(addDoc(collection(bob(), 'reviews'), validReview()));
  });

  it('authorName precisa ser o nome do perfil', async () => {
    await assertFails(addDoc(collection(alice(), 'reviews'), validReview({ authorName: 'Outra Pessoa' })));
  });

  it('usuário sem perfil não avalia', async () => {
    const db = env.authenticatedContext('ghost').firestore();
    await assertFails(addDoc(collection(db, 'reviews'), validReview({ authorId: 'ghost', authorName: 'Ghost' })));
  });

  for (const axis of ['food', 'ambience', 'service']) {
    it(axis + ': rejeita 0, 6, decimal e string', async () => {
      await assertFails(addDoc(collection(alice(), 'reviews'), validReview({ [axis]: 0 })));
      await assertFails(addDoc(collection(alice(), 'reviews'), validReview({ [axis]: 6 })));
      await assertFails(addDoc(collection(alice(), 'reviews'), validReview({ [axis]: 3.5 })));
      await assertFails(addDoc(collection(alice(), 'reviews'), validReview({ [axis]: '3' })));
    });

    it(axis + ': rejeita 4.5 e "5" (F14)', async () => {
      await assertFails(addDoc(collection(alice(), 'reviews'), validReview({ [axis]: 4.5 })));
      await assertFails(addDoc(collection(alice(), 'reviews'), validReview({ [axis]: '5' })));
    });

    it(axis + ': chave obrigatória, mesmo quando não avaliado (null)', async () => {
      const data = validReview();
      delete data[axis];
      await assertFails(addDoc(collection(alice(), 'reviews'), data));
    });

    it(axis + ': opcional (null) quando outro eixo foi avaliado (F14)', async () => {
      await assertSucceeds(addDoc(collection(alice(), 'reviews'), validReview({ [axis]: null })));
    });

    it(axis + ': avaliação só com este eixo é válida (F14)', async () => {
      const only = { food: null, ambience: null, service: null, [axis]: 4 };
      await assertSucceeds(addDoc(collection(alice(), 'reviews'), validReview(only)));
    });
  }

  it('os 3 eixos null é negado (mínimo 1 eixo; F14)', async () => {
    await assertFails(addDoc(collection(alice(), 'reviews'), validReview({ food: null, ambience: null, service: null })));
  });

  it('eixo inválido não passa só porque outro é null (F14)', async () => {
    await assertFails(addDoc(collection(alice(), 'reviews'), validReview({ food: null, ambience: 6, service: 3 })));
  });

  it('eixo ausente não vira zero: 0 com os outros null é negado (F14)', async () => {
    await assertFails(addDoc(collection(alice(), 'reviews'), validReview({ food: 0, ambience: null, service: null })));
  });

  it('aceita as fronteiras 1 e 5', async () => {
    await assertSucceeds(addDoc(collection(alice(), 'reviews'), validReview({ food: 1, ambience: 5, service: 1 })));
  });

  it('createdAt precisa ser do servidor', async () => {
    await assertFails(addDoc(collection(alice(), 'reviews'), validReview({ createdAt: Timestamp.fromMillis(0) })));
    await assertFails(addDoc(collection(alice(), 'reviews'), validReview({ createdAt: Timestamp.now() })));
  });

  it('não aceita campo extra (ex.: nota agregada, período, texto fora de comment)', async () => {
    await assertFails(addDoc(collection(alice(), 'reviews'), validReview({ overall: 5 })));
    await assertFails(addDoc(collection(alice(), 'reviews'), validReview({ dayPeriod: 'noite' })));
    await assertFails(addDoc(collection(alice(), 'reviews'), validReview({ text: 'top' })));
  });

  it('companion fora da lista é negado', async () => {
    await assertFails(addDoc(collection(alice(), 'reviews'), validReview({ companion: 'pet' })));
  });

  it('companion é chave obrigatória (null quando não informado)', async () => {
    const data = validReview();
    delete data.companion;
    await assertFails(addDoc(collection(alice(), 'reviews'), data));
  });

  it('comment null é aceito (comentário é opcional)', async () => {
    await assertSucceeds(addDoc(collection(alice(), 'reviews'), validReview({ comment: null })));
  });

  it('comment de 1 a 280 caracteres é aceito', async () => {
    await assertSucceeds(addDoc(collection(alice(), 'reviews'), validReview({ comment: 'a' })));
    await assertSucceeds(addDoc(collection(alice(), 'reviews'), validReview({ comment: 'Camarão top, fila grande.' })));
    await assertSucceeds(addDoc(collection(alice(), 'reviews'), validReview({ comment: 'x'.repeat(280) })));
    // size() conta unidades UTF-16 (igual a String.length no Dart): acento = 1.
    await assertSucceeds(addDoc(collection(alice(), 'reviews'), validReview({ comment: 'ã'.repeat(280) })));
  });

  it('comment vazio, acima de 280 ou não-string é negado', async () => {
    await assertFails(addDoc(collection(alice(), 'reviews'), validReview({ comment: '' })));
    await assertFails(addDoc(collection(alice(), 'reviews'), validReview({ comment: 'x'.repeat(281) })));
    // emoji fora do BMP = 2 unidades UTF-16: 141 emojis = 282.
    await assertFails(addDoc(collection(alice(), 'reviews'), validReview({ comment: '😀'.repeat(141) })));
    await assertFails(addDoc(collection(alice(), 'reviews'), validReview({ comment: 42 })));
    await assertFails(addDoc(collection(alice(), 'reviews'), validReview({ comment: true })));
    await assertFails(addDoc(collection(alice(), 'reviews'), validReview({ comment: ['a'] })));
  });

  it('comment é chave obrigatória (null quando não informado): chaves permitidas = 11', async () => {
    const data = validReview();
    delete data.comment;
    await assertFails(addDoc(collection(alice(), 'reviews'), data));
    await assertFails(addDoc(collection(alice(), 'reviews'), validReview({ comment: 'ok', extra: 1 })));
  });

  it('janela de transição: review sem a chave hasPhoto continua aceita (= false)', async () => {
    const data = validReview();
    delete data.hasPhoto;
    await assertSucceeds(addDoc(collection(alice(), 'reviews'), data));
    // ...e não leva foto: a foto exige hasPhoto true na review.
    const db = alice();
    const batch = writeBatch(db);
    batch.set(doc(db, 'reviews/semchave'), data);
    batch.set(doc(db, 'reviewPhotos/semchave'), validPhoto());
    await assertFails(batch.commit());
  });

  it('hasPhoto, quando presente, é booleano', async () => {
    await assertSucceeds(addDoc(collection(alice(), 'reviews'), validReview({ hasPhoto: false })));
    await assertFails(addDoc(collection(alice(), 'reviews'), validReview({ hasPhoto: null })));
    await assertFails(addDoc(collection(alice(), 'reviews'), validReview({ hasPhoto: 'true' })));
    await assertFails(addDoc(collection(alice(), 'reviews'), validReview({ hasPhoto: 1 })));
  });

  it('hasPhoto: true sem a foto no mesmo batch é negado', async () => {
    await assertFails(addDoc(collection(alice(), 'reviews'), validReview({ hasPhoto: true })));
    await assertFails(reviewWithPhotoBatch(alice(), { withPhoto: false }));
  });

  it('comentário é imutável como a avaliação (nem o autor edita)', async () => {
    await assertFails(updateDoc(doc(alice(), 'reviews/existing'), { comment: 'editado' }));
  });

  it('local precisa existir e placeName bater com o local', async () => {
    await assertFails(addDoc(collection(alice(), 'reviews'), validReview({ placeId: 'inexistente' })));
    await assertFails(addDoc(collection(alice(), 'reviews'), validReview({ placeName: 'Outro nome' })));
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
    await assertSucceeds(reviewWithPhotoBatch(alice(), { id: 'limite', photo: { jpeg: jpegBytes(150000) } }));
    await assertFails(reviewWithPhotoBatch(alice(), { id: 'grande', photo: { jpeg: jpegBytes(150001) } }));
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
    // Bob cria a própria review com foto, mas o doc da foto diz ser de Alice.
    await assertFails(reviewWithPhotoBatch(bob(), {
      review: { authorId: 'bob', authorName: 'Bob' },
      photo: { authorId: 'alice' },
    }));
    // Alice tenta anexar foto à review que Bob cria no mesmo batch: só o
    // autor da review grava a foto (e a review de Bob nem passa com Alice).
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
    // Só FF D8 sem o FF seguinte também não passa.
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
    batch.set(doc(db, 'reviewPhotos/y'), semAutor);
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
