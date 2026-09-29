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
    createdAt: serverTimestamp(),
    ...overrides,
  };
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

    it(axis + ': obrigatório', async () => {
      const data = validReview();
      delete data[axis];
      await assertFails(addDoc(collection(alice(), 'reviews'), data));
    });
  }

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

  it('comment é chave obrigatória (null quando não informado): chaves exatas = 10', async () => {
    const data = validReview();
    delete data.comment;
    await assertFails(addDoc(collection(alice(), 'reviews'), data));
    await assertFails(addDoc(collection(alice(), 'reviews'), validReview({ comment: 'ok', extra: 1 })));
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
