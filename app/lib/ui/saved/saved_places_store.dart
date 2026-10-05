import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/saved_repository.dart';

enum SavedStatus { idle, loading, ready, error }

/// Resultado imediato de uma troca otimista: o novo estado já aplicado e o
/// Future da escrita (`false` = falhou e o otimismo foi revertido).
typedef SaveChange = ({bool saved, Future<bool> done});

/// Fonte única do "Quero ir" (F11): ids salvos do usuário logado, carregados
/// uma vez por sessão. Feed, detalhe, seletor e aba leem daqui, então o
/// marcador fica consistente em todas as telas.
///
/// Trocas são otimistas e serializadas por local: enquanto uma escrita de um
/// id está em voo, novos toques só mudam o estado desejado; quando ela
/// termina, uma nova escrita sai só se o desejado ainda divergir do que o
/// servidor confirmou. Nunca há duas escritas simultâneas para o mesmo id.
class SavedPlacesStore extends ChangeNotifier {
  SavedPlacesStore({
    required AuthRepository authRepository,
    required SavedRepository savedRepository,
    DateTime Function()? clock,
  }) : _auth = authRepository,
       _repo = savedRepository,
       _clock = clock ?? DateTime.now {
    _auth.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  final AuthRepository _auth;
  final SavedRepository _repo;
  final DateTime Function() _clock;

  String? _uid;

  /// Muda a cada troca de usuário/recarga: respostas antigas são descartadas.
  int _generation = 0;

  SavedStatus _status = SavedStatus.idle;
  SavedStatus get status => _status;
  bool get isReady => _status == SavedStatus.ready;
  bool get isLoading => _status == SavedStatus.loading;
  bool get hasError => _status == SavedStatus.error;

  /// Estado exibido (otimista): id → quando foi salvo.
  final Map<String, DateTime> _entries = {};

  /// Último estado confirmado pelo servidor.
  final Map<String, DateTime> _confirmed = {};

  /// Data de salvamento de quem acabou de ser removido (para o "Desfazer").
  final Map<String, DateTime> _removedAt = {};

  /// Escrita em andamento por id.
  final Map<String, Future<bool>> _workers = {};

  Future<void>? _loading;
  bool _disposed = false;

  bool isSaved(String placeId) => _entries.containsKey(placeId);

  /// Salvos do mais recente para o mais antigo.
  List<({String placeId, DateTime savedAt})> get entries {
    final list =
        [for (final e in _entries.entries) (placeId: e.key, savedAt: e.value)]
          ..sort((a, b) {
            final byDate = b.savedAt.compareTo(a.savedAt);
            return byDate != 0 ? byDate : a.placeId.compareTo(b.placeId);
          });
    return list;
  }

  void _onAuthChanged() {
    final uid = _auth.currentUserId;
    if (uid == _uid) return;
    _uid = uid;
    _generation++;
    _entries.clear();
    _confirmed.clear();
    _removedAt.clear();
    _workers.clear();
    _loading = null;
    _status = SavedStatus.idle;
    if (uid != null) {
      reload();
    } else {
      _notify();
    }
  }

  /// Carrega os salvos (também é o "Tentar de novo"). Chamadas simultâneas
  /// compartilham a mesma leitura.
  Future<void> reload() {
    final uid = _uid;
    if (uid == null) return Future.value();
    return _loading ??= _load(uid, _generation);
  }

  Future<void> _load(String uid, int generation) async {
    // Recarga com a lista já pronta (ex.: puxar para atualizar) não bloqueia
    // o marcador: os toques continuam valendo durante a leitura.
    if (!isReady) {
      _status = SavedStatus.loading;
      _notify();
    }
    try {
      // Escritas em voo primeiro: a leitura já reflete o que elas fizeram.
      if (_workers.isNotEmpty) await Future.wait(_workers.values.toList());
      if (generation != _generation) return;
      final list = await _repo.listSaved(uid);
      if (generation != _generation) return;
      _merge({for (final s in list) s.placeId: s.savedAt});
      _status = SavedStatus.ready;
    } on Object {
      if (generation != _generation) return;
      // Falha numa recarga de fundo mantém a lista que já estava na tela.
      if (!isReady) _status = SavedStatus.error;
    } finally {
      if (generation == _generation) {
        _loading = null;
        _notify();
      }
    }
  }

  /// Aplica o que veio do servidor sem perder toques otimistas: id com
  /// escrita em voo ou com estado desejado ainda não confirmado mantém o
  /// desejado (e volta a sincronizar); os demais seguem o servidor.
  void _merge(Map<String, DateTime> server) {
    final pending = {
      for (final id in {..._entries.keys, ..._confirmed.keys})
        if (_workers.containsKey(id) || !_inSync(id)) id,
    };
    final desired = {for (final id in pending) id: _entries[id]};
    final confirmedPending = {
      for (final id in pending)
        if (_workers.containsKey(id)) id: _confirmed[id],
    };
    _confirmed
      ..clear()
      ..addAll(server);
    // Worker em voo é dono do confirmado do seu id.
    confirmedPending.forEach((id, at) {
      if (at != null) {
        _confirmed[id] = at;
      } else {
        _confirmed.remove(id);
      }
    });
    _entries
      ..clear()
      ..addAll(_confirmed);
    desired.forEach((id, at) {
      if (at != null) {
        _entries[id] = _confirmed[id] ?? at;
      } else {
        _entries.remove(id);
      }
    });
    final uid = _uid;
    if (uid == null) return;
    for (final id in pending) {
      if (!_workers.containsKey(id) && !_inSync(id)) {
        _workers[id] = _sync(uid, id, _generation);
      }
    }
  }

  /// Inverte o estado de [placeId] já (otimista). `null` quando os salvos
  /// ainda não foram carregados (não dá para saber o estado atual).
  SaveChange? toggle(String placeId) {
    if (!isReady) return null;
    final saved = !isSaved(placeId);
    return (saved: saved, done: setSaved(placeId, saved));
  }

  /// Leva [placeId] para [saved] (otimista) e sincroniza com o servidor.
  /// Completa com `false` se a escrita falhou (estado revertido).
  Future<bool> setSaved(String placeId, bool saved) {
    final uid = _uid;
    if (!isReady || uid == null) return Future.value(false);
    if (saved != isSaved(placeId)) {
      if (saved) {
        // "Desfazer" de uma remoção volta à data em que foi salvo.
        _entries[placeId] =
            _removedAt.remove(placeId) ?? _confirmed[placeId] ?? _clock();
      } else {
        final at = _entries.remove(placeId);
        if (at != null) _removedAt[placeId] = at;
      }
      _notify();
    }
    final running = _workers[placeId];
    if (running != null) return running;
    if (_inSync(placeId)) return Future.value(true);
    // A 1ª volta de _sync sempre espera uma escrita: o worker fica registrado
    // antes do `finally` dele rodar.
    final worker = _sync(uid, placeId, _generation);
    _workers[placeId] = worker;
    return worker;
  }

  bool _inSync(String placeId) =>
      _entries.containsKey(placeId) == _confirmed.containsKey(placeId);

  Future<bool> _sync(String uid, String placeId, int generation) async {
    try {
      while (generation == _generation) {
        if (_inSync(placeId)) return true;
        final want = _entries[placeId];
        try {
          if (want != null) {
            DateTime? serverAt;
            try {
              await _repo.save(uid: uid, placeId: placeId);
            } on Object {
              // Já existia (set vira update, negado) ou a resposta se perdeu:
              // se o doc está lá, está salvo.
              serverAt = await _savedAtOf(uid, placeId);
              if (serverAt == null) rethrow;
            }
            // Hora real do servidor no lugar do relógio do aparelho.
            serverAt ??= await _savedAtOf(uid, placeId);
            if (generation == _generation) {
              final at = serverAt ?? want;
              _confirmed[placeId] = at;
              if (_entries.containsKey(placeId) && _entries[placeId] != at) {
                _entries[placeId] = at;
                _notify();
              }
            }
          } else {
            await _repo.remove(uid: uid, placeId: placeId);
            if (generation == _generation) _confirmed.remove(placeId);
          }
        } on Object {
          if (generation != _generation) return false;
          // O último toque já voltou ao que o servidor tem: nada a desfazer.
          if (_inSync(placeId)) return true;
          // Volta ao que o servidor tem.
          final confirmed = _confirmed[placeId];
          if (confirmed != null) {
            _entries[placeId] = confirmed;
          } else {
            _entries.remove(placeId);
          }
          _notify();
          return false;
        }
      }
      return false;
    } finally {
      if (generation == _generation) _workers.remove(placeId);
    }
  }

  /// `null` quando o doc não existe ou a leitura falhou.
  Future<DateTime?> _savedAtOf(String uid, String placeId) async {
    try {
      return await _repo.savedAtOf(uid: uid, placeId: placeId);
    } on Object {
      return null;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }
}
