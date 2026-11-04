class UserProfile {
  const UserProfile({
    required this.uid,
    required this.displayName,
    this.username = '',
    this.bio = '',
    this.city = '',
    this.instagram = '',
  });

  final String uid;
  final String displayName;
  final String username, bio, city, instagram;
  static bool validInstagram(String value) =>
      value.isEmpty || RegExp(r'^[a-zA-Z0-9._]{1,30}$').hasMatch(value);
  static const maxBioLength = 240;
  static bool validUsername(String value) =>
      RegExp(r'^[a-z0-9][a-z0-9._]{2,23}$').hasMatch(value);

  static const int maxNameLength = 60;

  static String normalizeName(String raw) => raw.trim();

  static bool isNonEmptyName(String raw) => normalizeName(raw).isNotEmpty;

  static bool isNameWithinLimit(String raw) =>
      normalizeName(raw).length <= maxNameLength;

  static bool isValidName(String raw) =>
      isNonEmptyName(raw) && isNameWithinLimit(raw);
}
