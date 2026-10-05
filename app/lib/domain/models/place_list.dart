import '../search_tokens.dart' show foldAccents;

/// Lista nomeada dentro do "Quero ir" (F12): `users/{uid}/lists/{listId}`,
/// privada. É um subconjunto dos salvos.
class PlaceList {
  const PlaceList({
    required this.id,
    required this.name,
    required this.emoji,
    required this.placeIds,
    required this.createdAt,
  });

  final String id;
  final String name;

  /// Um de [listEmojis] ou `null`.
  final String? emoji;

  /// Membros, na ordem em que entraram (sem repetição).
  final List<String> placeIds;

  /// `createdAt` do servidor (ordem dos chips).
  final DateTime createdAt;

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
  }) => PlaceList(
    id: id,
    name: name ?? this.name,
    emoji: emoji == null ? this.emoji : emoji(),
    placeIds: placeIds ?? this.placeIds,
    createdAt: createdAt,
  );

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
