import 'package:characters/characters.dart';

import '../search_tokens.dart' show foldAccents;

/// Crédito de uma lista copiada (F13): de quem e de qual lista veio. Gravado
/// só na criação e imutável (as Rules conferem o nome com o perfil).
class ListCredit {
  const ListCredit({
    required this.uid,
    required this.name,
    required this.listId,
  });

  /// Autora da lista original.
  final String uid;

  /// `displayName` da autora (imutável, então nunca fica desatualizado).
  final String name;

  /// Id da lista original (`users/{uid}/lists/{listId}`).
  final String listId;

  @override
  bool operator ==(Object other) =>
      other is ListCredit &&
      other.uid == uid &&
      other.name == name &&
      other.listId == listId;

  @override
  int get hashCode => Object.hash(uid, name, listId);
}

/// Lista nomeada dentro do "Quero ir" (F12): `users/{uid}/lists/{listId}`.
/// É um subconjunto dos salvos. Privada por padrão; com [visible] (F13),
/// quem segue a dona vê e copia.
class PlaceList {
  const PlaceList({
    required this.id,
    required this.name,
    required this.emoji,
    required this.placeIds,
    required this.createdAt,
    this.visible = false,
    this.copiedFrom,
  });

  final String id;
  final String name;

  /// Um de [listEmojis] ou `null`.
  final String? emoji;

  /// Membros, na ordem em que entraram (sem repetição).
  final List<String> placeIds;

  /// `createdAt` do servidor (ordem dos chips).
  final DateTime createdAt;

  /// "Visível para quem me segue" (F13). Listas antigas, sem o campo, são
  /// privadas.
  final bool visible;

  /// Crédito, se a lista foi copiada de alguém (F13).
  final ListCredit? copiedFrom;

  /// Mesmos limites das Security Rules.
  static const int maxNameLength = 40;
  static const int maxPlaces = 200;

  /// Limite do app (as Rules não contam documentos).
  static const int maxLists = 30;

  /// "🎉 Sábado com as meninas" / "Sábado com as meninas".
  String get label => emoji == null ? name : '$emoji $name';

  bool contains(String placeId) => placeIds.contains(placeId);

  bool get isFull => placeIds.length >= maxPlaces;

  PlaceList copyWith({
    String? name,
    String? Function()? emoji,
    List<String>? placeIds,
    bool? visible,
  }) => PlaceList(
    id: id,
    name: name ?? this.name,
    emoji: emoji == null ? this.emoji : emoji(),
    placeIds: placeIds ?? this.placeIds,
    createdAt: createdAt,
    visible: visible ?? this.visible,
    copiedFrom: copiedFrom,
  );

  /// Nome da cópia (F13) de uma lista chamada [name] de [author]: o mesmo
  /// nome; se já existir ([isTaken]), "`name` (de `author`)". Se esse
  /// também existir (2ª cópia da mesma lista), põe um número no fim
  /// ("… (de Ana) 2", "… 3").
  ///
  /// Para caber em [maxNameLength], só o nome-base é cortado: " (de
  /// `Autora`)" e o número ficam inteiros (nunca sobra parêntese aberto). Se
  /// o crédito sozinho não couber, o nome da autora é cortado e o parêntese
  /// fechado. Os cortes são por grafema: emoji com ZWJ ou tom de pele nunca
  /// é partido.
  static String copyName(
    String name,
    String author, {
    required bool Function(String name) isTaken,
  }) {
    final base = normalizeName(name);
    if (isValidName(base) && !isTaken(base)) return base;
    final who = normalizeName(author);
    for (var n = 1; ; n++) {
      final candidate = _credited(base, who, n == 1 ? '' : ' $n');
      if (!isTaken(candidate)) return candidate;
    }
  }

  /// "`base` (de `author`)`suffix`" em até [maxNameLength] unidades.
  static String _credited(String base, String author, String suffix) {
    const open = ' (de ';
    const close = ')';
    // Pelo menos 1 unidade para o nome-base; o resto do crédito, inteiro.
    final maxAuthor =
        maxNameLength - 1 - open.length - close.length - suffix.length;
    final who = _cutGraphemes(author, maxAuthor);
    final tail = '$open$who$close$suffix';
    final head = _cutGraphemes(base, maxNameLength - tail.length);
    return normalizeName('$head$tail');
  }

  /// [raw] com no máximo [max] unidades UTF-16 (o `size()` das Rules),
  /// cortado entre grafemas e sem espaço no fim.
  static String _cutGraphemes(String raw, int max) {
    if (raw.length <= max) return raw;
    final out = StringBuffer();
    var used = 0;
    for (final g in raw.characters) {
      if (used + g.length > max) break;
      out.write(g);
      used += g.length;
    }
    return out.toString().trimRight();
  }

  /// Nome para gravação: sem espaços nas pontas e com espaços internos
  /// repetidos colapsados num só (as Rules negam `\s\s`).
  static String normalizeName(String raw) =>
      raw.trim().replaceAll(_spaces, ' ');

  static final _spaces = RegExp(r'\s+');

  /// Chave de unicidade: aparado, sem diferenciar caixa nem acento.
  static String nameKey(String raw) => foldAccents(normalizeName(raw));

  /// 1–40 caracteres depois de aparar.
  static bool isValidName(String raw) {
    final n = normalizeName(raw);
    return n.isNotEmpty && n.length <= maxNameLength;
  }

  static bool isValidEmoji(String? emoji) =>
      emoji == null || listEmojis.contains(emoji);
}

/// Conjunto fixo de emojis de lista. MESMA lista de `listEmojis()` em
/// `firebase/firestore.rules`.
const List<String> listEmojis = [
  '🎉',
  '🍕',
  '🍔',
  '🍣',
  '🍻',
  '☕',
  '🍰',
  '🌮',
  '🌊',
  '💑',
  '👯',
  '⭐',
];
