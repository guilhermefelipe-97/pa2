/// Relógio do app, injetado via Provider: telas criadas pelo router (ex.: o
/// detalhe e a foto em tela cheia) usam o mesmo "agora" que os testes fixam.
class AppClock {
  const AppClock([this._now]);

  final DateTime Function()? _now;

  DateTime now() => (_now ?? DateTime.now)();
}
