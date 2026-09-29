/// Perfil público de um usuário (`users/{uid}`).
class UserProfile {
  const UserProfile({required this.uid, required this.displayName});

  final String uid;
  final String displayName;

  /// Mesmo limite das Security Rules (`displayName.size() <= 60`).
  static const int maxNameLength = 60;

  /// Nome normalizado para gravação: sem espaços nas pontas.
  static String normalizeName(String raw) => raw.trim();

  /// Nome não vazio depois de `trim`.
  static bool isNonEmptyName(String raw) => normalizeName(raw).isNotEmpty;

  /// Nome não excede [maxNameLength] depois de `trim`.
  static bool isNameWithinLimit(String raw) =>
      normalizeName(raw).length <= maxNameLength;

  /// Nome válido = não vazio e dentro do limite, depois de `trim`.
  static bool isValidName(String raw) => isNonEmptyName(raw) && isNameWithinLimit(raw);
}
