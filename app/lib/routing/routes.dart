abstract final class Routes {
  static const splash = '/splash';
  static const login = '/login';
  static const signUp = '/cadastro';
  static const feed = '/';
  static const nearby = '/perto';
  static const saved = '/quero-ir';
  static const people = '/pessoas';
  static const pickPlace = '/avaliar';

  static const placeDetailPattern = '/local/:placeId';
  static const personPattern = '/pessoa/:uid';

  /// Lista visível de uma pessoa (F13), com "Copiar lista".
  static const personListPattern = '/pessoa/:uid/lista/:listId';

  static String reviewFor(String placeId) => '/avaliar/$placeId';

  static String placeDetail(String placeId) =>
      '/local/${Uri.encodeComponent(placeId)}';

  static String person(String uid) => '/pessoa/${Uri.encodeComponent(uid)}';

  static String personList(String uid, String listId) =>
      '/pessoa/${Uri.encodeComponent(uid)}/lista/'
      '${Uri.encodeComponent(listId)}';
}
