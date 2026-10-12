import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/data/lru_ttl_cache.dart';

void main() {
  test('passa da capacidade: sai a usada há mais tempo', () {
    final c = LruTtlCache<String, int>(capacity: 2);
    c['a'] = 1;
    c['b'] = 2;
    expect(c['a'], 1); // "a" vira a mais recente
    c['c'] = 3;
    expect(c['b'], isNull);
    expect(c['a'], 1);
    expect(c['c'], 3);
    expect(c.length, 2);
  });

  test('expira depois do TTL', () {
    var now = DateTime.utc(2026, 10, 12, 12);
    final c = LruTtlCache<String, int>(
      ttl: const Duration(minutes: 30),
      clock: () => now,
    );
    c['a'] = 1;
    now = now.add(const Duration(minutes: 29));
    expect(c['a'], 1);
    now = now.add(const Duration(minutes: 2));
    expect(c['a'], isNull);
    expect(c.length, 0);
  });

  test('padrão: 200 entradas e 30 min', () {
    final c = LruTtlCache<int, int>();
    for (var i = 0; i < 250; i++) {
      c[i] = i;
    }
    expect(c.length, 200);
    expect(c[0], isNull);
    expect(c[249], 249);
    expect(c.ttl, const Duration(minutes: 30));
  });
}
