import 'dart:collection';

/// Cache em memória com no máximo [capacity] entradas (sai a usada há mais
/// tempo) e validade [ttl] por entrada. Usado para não guardar a sessão
/// inteira de consultas ao Photon nem de locais descobertos (G2).
class LruTtlCache<K, V> {
  LruTtlCache({
    this.capacity = 200,
    this.ttl = const Duration(minutes: 30),
    DateTime Function()? clock,
  }) : assert(capacity > 0),
       _clock = clock ?? DateTime.now;

  final int capacity;
  final Duration ttl;
  final DateTime Function() _clock;

  /// Ordem de inserção = ordem de uso (a mais antiga primeiro).
  final LinkedHashMap<K, ({V value, DateTime at})> _map = LinkedHashMap();

  int get length => _map.length;

  /// Valor válido de [key] (renova o uso), ou `null`.
  V? operator [](K key) {
    final e = _map.remove(key);
    if (e == null) return null;
    if (_clock().difference(e.at) > ttl) return null;
    _map[key] = e;
    return e.value;
  }

  void operator []=(K key, V value) {
    _map.remove(key);
    _map[key] = (value: value, at: _clock());
    while (_map.length > capacity) {
      _map.remove(_map.keys.first);
    }
  }

  V? remove(K key) => _map.remove(key)?.value;

  /// Remove [key] só se ainda guardar exatamente [value].
  void removeIfSame(K key, V value) {
    final e = _map[key];
    if (e != null && identical(e.value, value)) _map.remove(key);
  }

  void clear() => _map.clear();
}
