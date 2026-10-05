// Normalização e tokens de busca dos locais.
//
// REGRAS IDÊNTICAS às de `app/lib/domain/search_tokens.dart` (o app gera a
// consulta, este script gera os tokens gravados no Firestore). Os dois lados
// são testados contra o mesmo arquivo de casos:
// `firebase/tests/fixtures/search-tokens.json`.
//
// 1. minúsculas;
// 2. marcas combinantes U+0300–U+036F removidas (texto já em NFD) e acentos /
//    letras especiais trocados por uma tabela explícita (o Dart não tem NFD);
// 3. palavras = sequências de [a-z0-9]; o resto separa palavras;
// 4. tokens = prefixos de 2 até o tamanho inteiro de cada palavra (palavras de
//    1 letra não geram token), sem repetição, na ordem em que aparecem.

const ACCENTS = {
  á: 'a', à: 'a', â: 'a', ã: 'a', ä: 'a',
  é: 'e', è: 'e', ê: 'e', ë: 'e',
  í: 'i', ì: 'i', î: 'i', ï: 'i',
  ó: 'o', ò: 'o', ô: 'o', õ: 'o', ö: 'o',
  ú: 'u', ù: 'u', û: 'u', ü: 'u',
  ç: 'c', ñ: 'n',
  ø: 'o', æ: 'ae', ß: 'ss', ý: 'y', ÿ: 'y', œ: 'oe', º: 'o', ª: 'a',
};

/** Marca combinante (acento separado da letra, texto NFD). */
function isCombining(ch) {
  const c = ch.codePointAt(0);
  return c >= 0x300 && c <= 0x36f;
}

const MIN_TOKEN = 2;

/** Minúsculas e sem acento. */
function fold(text) {
  let out = '';
  for (const ch of String(text ?? '').toLowerCase()) {
    if (isCombining(ch)) continue;
    out += ACCENTS[ch] ?? ch;
  }
  return out;
}

/** Palavras normalizadas (`[a-z0-9]+`). */
function words(text) {
  return fold(text).split(/[^a-z0-9]+/).filter(Boolean);
}

/** Tokens de busca de um nome: prefixos ≥ 2 de cada palavra. */
function searchTokens(name) {
  const seen = new Set();
  for (const w of words(name)) {
    for (let i = MIN_TOKEN; i <= w.length; i++) seen.add(w.slice(0, i));
  }
  return [...seen];
}

/** Chave de ordenação (`nameLower`): minúsculas sem acento, espaços colapsados. */
function nameLower(name) {
  return words(name).join(' ');
}

module.exports = { fold, words, searchTokens, nameLower, MIN_TOKEN };
