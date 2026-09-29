abstract final class Routes {
  static const splash = '/splash';
  static const login = '/login';
  static const signUp = '/cadastro';
  static const feed = '/';
  static const people = '/pessoas';
  static const pickPlace = '/avaliar';

  static String reviewFor(String placeId) => '/avaliar/$placeId';
}
