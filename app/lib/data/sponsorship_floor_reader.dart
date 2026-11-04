import '../domain/sponsorship_floor.dart';
import 'lru_ttl_cache.dart';
import 'repositories/place_history_repository.dart';

/// Lê as avaliações da janela do piso (F26) e aplica [SponsorshipFloor].
/// O resultado fica em cache por [ttl]: a seção Patrocinado se atualiza a
/// cada 15 s e não deve reler a janela inteira a cada vez. Chamadas
/// simultâneas para o mesmo local compartilham a mesma leitura; uma falha
/// não fica em cache.
class SponsorshipFloorReader {
  SponsorshipFloorReader(
    this._history, {
    Duration ttl = const Duration(minutes: 10),
    DateTime Function()? clock,
  }) : _cache = LruTtlCache(capacity: 100, ttl: ttl, clock: clock);

  final PlaceHistoryRepository _history;
  final LruTtlCache<String, Future<FloorCheck>> _cache;

  Future<FloorCheck> check(String placeId, DateTime now) {
    final cached = _cache[placeId];
    if (cached != null) return cached;
    final read = _history
        .reviewsSince(placeId, SponsorshipFloor.windowStart(now))
        .then((reviews) => SponsorshipFloor.check(reviews, now));
    _cache[placeId] = read;
    read.catchError((Object _) {
      _cache.removeIfSame(placeId, read);
      return const FloorCheck(FloorStatus.insufficientSample, null, 0);
    });
    return read;
  }

  void clear() => _cache.clear();
}
