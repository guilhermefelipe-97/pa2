import 'package:flutter/foundation.dart';

/// Avisa que o usuário seguiu ou deixou de seguir alguém (aba Pessoas ou
/// perfil). É o mecanismo único para as telas que dependem de quem é seguido
/// (feed, Pessoas, detalhe do local, perfil) saberem que ficaram
/// desatualizadas, sem leituras extras.
class FollowEvents extends ChangeNotifier {
  int _version = 0;

  /// Quantas mudanças já houve (para testes e diagnóstico).
  int get version => _version;

  void changed() {
    _version++;
    notifyListeners();
  }
}

/// Lado de um ViewModel: fica [isStale] quando *outra* tela avisa uma mudança
/// em [FollowEvents]; avisos feitos pelo próprio dono ([announce]) não o
/// marcam. O dono limpa ([clear]) ao começar uma carga, que já lê o estado
/// novo, e chama [dispose] junto com o seu.
class FollowStaleness {
  FollowStaleness(this._events) {
    _events.addListener(_mark);
  }

  final FollowEvents _events;
  bool _stale = false;
  bool _announcing = false;

  bool get isStale => _stale;

  void _mark() {
    if (!_announcing) _stale = true;
  }

  void clear() => _stale = false;

  /// Avisa as outras telas sem marcar o próprio dono.
  void announce() {
    _announcing = true;
    try {
      _events.changed();
    } finally {
      _announcing = false;
    }
  }

  void dispose() => _events.removeListener(_mark);
}
