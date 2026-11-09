import 'dart:async';

import '../domain/models/review.dart';
import '../domain/taste_match.dart';
import 'repositories/candidate_reviews_repository.dart';
import 'repositories/review_repository.dart';

/// Calcula o "gosto parecido" (F07) do usuário com outras pessoas.
///
/// Usa as avaliações mais recentes do usuário (até o limite por lote do
/// repositório) e, para os mesmos locais, todas as avaliações das pessoas
/// comparadas. Pedidos feitos no mesmo quadro (vários selos do feed) viram
/// uma leitura só; o resultado fica em memória por [ttl] e é descartado
/// quando a conta muda. Falha não fica em cache.
class TasteMatchService {
  TasteMatchService(
    this._reviews, {
    this.ttl = const Duration(minutes: 10),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ReviewRepository _reviews;
  final Duration ttl;
  final DateTime Function() _clock;

  String? _me;
  DateTime? _loadedAt;
  Future<List<Review>>? _mine;
  final _cache = <String, Future<TasteMatch>>{};
  final _pending = <String, Completer<TasteMatch>>{};
  bool _scheduled = false;

  Future<TasteMatch> matchFor(String me, String other) {
    if (me == other) return Future.value(TasteMatch.none);
    final now = _clock();
    if (_me != me || _loadedAt == null || now.difference(_loadedAt!) > ttl) {
      _me = me;
      _loadedAt = now;
      _mine = null;
      _cache.clear();
    }
    final cached = _cache[other];
    if (cached != null) return cached;
    final completer = _pending.putIfAbsent(other, Completer.new);
    _cache[other] = completer.future;
    if (!_scheduled) {
      _scheduled = true;
      scheduleMicrotask(() => _flush(me));
    }
    return completer.future;
  }

  Future<void> _flush(String me) async {
    _scheduled = false;
    final batch = Map.of(_pending);
    _pending.clear();
    try {
      final mine = await (_mine ??= _reviews
          .fetchReviewsByAuthors([me])
          .then((b) => b.items));
      final places = mine.map((r) => r.placeId).toSet().toList();
      final repo = _reviews;
      final theirs = places.isEmpty || repo is! CandidateReviewsRepository
          ? const <Review>[]
          : await (repo as CandidateReviewsRepository).reviewsForCandidates(
              places,
              batch.keys.toList(),
            );
      for (final MapEntry(key: uid, value: done) in batch.entries) {
        done.complete(
          TasteRule.compare(mine, theirs.where((r) => r.authorId == uid)),
        );
      }
    } on Object catch (e, s) {
      _mine = null;
      for (final MapEntry(key: uid, value: done) in batch.entries) {
        _cache.remove(uid);
        done.completeError(e, s);
      }
    }
  }
}
