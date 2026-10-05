/// Normalização e tokens de busca dos locais.
///
/// REGRAS IDÊNTICAS às de `firebase/seed/osm/tokens.js` (o script grava
/// `searchTokens` e `nameLower` em `places`; o app monta a consulta). Os dois
/// lados são testados contra `firebase/tests/fixtures/search-tokens.json`.
///
/// 1. minúsculas;
/// 2. marcas combinantes U+0300–U+036F removidas (texto em NFD) e acentos /
///    letras especiais trocados por uma tabela explícita;
/// 3. palavras = sequências de `[a-z0-9]`; o resto separa palavras;
/// 4. tokens = prefixos de 2 até o tamanho inteiro de cada palavra (palavras
///    de 1 letra não geram token), sem repetição, na ordem em que aparecem.
library;

const _accents = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
  'ç': 'c', 'ñ': 'n',
  'ø': 'o', 'æ': 'ae', 'ß': 'ss', 'ý': 'y', 'ÿ': 'y', 'œ': 'oe', 'º': 'o',
  'ª': 'a',
};

/// Marca combinante (acento separado da letra, texto NFD).
bool _isCombining(int codeUnit) => codeUnit >= 0x300 && codeUnit <= 0x36f;

/// Tamanho mínimo de um token (e de um termo consultável no servidor).
const minTokenLength = 2;

final _separators = RegExp('[^a-z0-9]+');

/// Minúsculas e sem acento.
String foldAccents(String text) {
  final buf = StringBuffer();
  for (final ch in text.toLowerCase().split('')) {
    if (_isCombining(ch.codeUnitAt(0))) continue;
    buf.write(_accents[ch] ?? ch);
  }
  return buf.toString();
}

/// Palavras normalizadas (`[a-z0-9]+`).
List<String> searchWords(String text) =>
    foldAccents(text).split(_separators).where((w) => w.isNotEmpty).toList();

/// Tokens de busca de um nome: prefixos ≥ 2 de cada palavra.
List<String> searchTokens(String name) {
  final seen = <String>{};
  for (final w in searchWords(name)) {
    for (var i = minTokenLength; i <= w.length; i++) {
      seen.add(w.substring(0, i));
    }
  }
  return seen.toList();
}

/// Chave de ordenação gravada em `nameLower`.
String nameLower(String name) => searchWords(name).join(' ');

/// Termos normalizados do que o usuário digitou.
List<String> normalizeQuery(String query) => searchWords(query);

/// O termo mais longo com ao menos [minTokenLength] letras (empate: o 1º).
/// É o único que vai ao servidor (`array-contains` aceita um valor) e o mais
/// seletivo; os demais são filtrados no cliente. null → busca curta.
String? serverTerm(List<String> terms) {
  String? best;
  for (final t in terms) {
    if (t.length >= minTokenLength && (best == null || t.length > best.length)) {
      best = t;
    }
  }
  return best;
}

/// Todos os [terms] são prefixo de alguma palavra de [name] (filtro no
/// cliente dos termos que não foram ao servidor).
bool nameMatchesTerms(String name, List<String> terms) {
  final words = searchWords(name);
  return terms.every((t) => words.any((w) => w.startsWith(t)));
}
