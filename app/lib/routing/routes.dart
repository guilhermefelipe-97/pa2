abstract final class Routes {
  static const splash = '/splash';
  static const login = '/login';
  static const signUp = '/cadastro';
  static const feed = '/';
  static const saved = '/quero-ir';
  static const people = '/pessoas';
  static const pickPlace = '/avaliar';

  static const placeDetailPattern = '/local/:placeId';
  static const personPattern = '/pessoa/:uid';

  static String reviewFor(String placeId) => '/avaliar/$placeId';

  static String placeDetail(String placeId) =>
      '/local/${Uri.encodeComponent(placeId)}';

  static String person(String uid) => '/pessoa/${Uri.encodeComponent(uid)}';
}
