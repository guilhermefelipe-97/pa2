import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'auth_repository.dart';

/// Fotos das avaliações (G1), lidas sob demanda quando o card ou a miniatura
/// aparece na tela.
abstract class ReviewPhotoRepository {
  /// Bytes JPEG da foto da avaliação [reviewId], ou `null` se não existe.
  Future<Uint8List?> getPhoto(String reviewId);

  /// Bytes já carregados (cache), sem esperar; `null` se ainda não vieram.
  Uint8List? peek(String reviewId);

  /// Esquece tudo (ex.: troca de usuário).
  void clear();
}

/// Leitura recente falhou: espera [CachedReviewPhotoRepository.retryBackoff]
/// antes de tentar o mesmo id de novo.
class ReviewPhotoBackoffException implements Exception {
  const ReviewPhotoBackoffException(this.reviewId);

  final String reviewId;

  @override
  String toString() => 'ReviewPhotoBackoffException($reviewId)';
}

/// Contrato comum de cache: fotos são imutáveis, então os bytes ficam em
/// memória (LRU de [maxCached]); pedidos simultâneos do mesmo id viram uma
/// leitura só; `null` (sem foto) não é guardado; depois de um erro, o mesmo id
/// só é relido após [retryBackoff]. Ouve o [AuthRepository] (quando dado) e
/// limpa tudo na troca de usuário.
abstract class CachedReviewPhotoRepository implements ReviewPhotoRepository {
  CachedReviewPhotoRepository({
    AuthRepository? authRepository,
    DateTime Function()? clock,
    this.maxCached = defaultMaxCached,
    this.retryBackoff = defaultRetryBackoff,
  }) : _auth = authRepository,
       _clock = clock ?? DateTime.now {
    _uid = _auth?.currentUserId;
    _auth?.addListener(_onAuthChanged);
  }

  static const int defaultMaxCached = 60;
  static const Duration defaultRetryBackoff = Duration(seconds: 30);

  final int maxCached;
  final Duration retryBackoff;
  final AuthRepository? _auth;
  final DateTime Function() _clock;
  String? _uid;

  /// Ordem de inserção = ordem de uso (o mais antigo sai primeiro).
  final LinkedHashMap<String, Uint8List> _bytes = LinkedHashMap();
  final Map<String, Future<Uint8List?>> _inFlight = {};
  final Map<String, DateTime> _failedAt = {};

  /// Muda a cada [clear]: leituras antigas não repovoam o cache.
  int _generation = 0;

  /// Leituras feitas na fonte.
  @visibleForTesting
  int readCount = 0;

  /// Lê a foto na fonte (sem cache).
  @protected
  Future<Uint8List?> fetch(String reviewId);

  static bool _validId(String id) => id.isNotEmpty && !id.contains('/');

  @override
  Uint8List? peek(String reviewId) {
    final hit = _bytes.remove(reviewId);
    if (hit != null) _bytes[reviewId] = hit; // marca como recente
    return hit;
  }

  @override
  Future<Uint8List?> getPhoto(String reviewId) {
    if (!_validId(reviewId)) return Future.value(null);
    final hit = peek(reviewId);
    if (hit != null) return Future.value(hit);
    final pending = _inFlight[reviewId];
    if (pending != null) return pending;
    final failed = _failedAt[reviewId];
    if (failed != null && _clock().difference(failed) < retryBackoff) {
      return Future.error(ReviewPhotoBackoffException(reviewId));
    }
    final generation = _generation;
    // Future.sync: um throw síncrono da fonte vira Future com erro e passa
    // pelo mesmo tratamento (sai de _inFlight, entra no backoff).
    final future = _inFlight.putIfAbsent(
      reviewId,
      () => Future.sync(() {
        readCount++;
        return fetch(reviewId);
      }),
    );
    future
        .then(
          (bytes) {
            if (generation != _generation) return;
            _failedAt.remove(reviewId);
            if (bytes != null && bytes.isNotEmpty) _remember(reviewId, bytes);
          },
          onError: (Object _) {
            if (generation != _generation) return;
            _failedAt[reviewId] = _clock();
          },
        )
        .whenComplete(() {
          if (identical(_inFlight[reviewId], future)) {
            _inFlight.remove(reviewId);
          }
        });
    return future;
  }

  void _remember(String reviewId, Uint8List bytes) {
    _bytes.remove(reviewId);
    _bytes[reviewId] = bytes;
    while (_bytes.length > maxCached) {
      _bytes.remove(_bytes.keys.first);
    }
  }

  @override
  void clear() {
    _generation++;
    _bytes.clear();
    _inFlight.clear();
    _failedAt.clear();
  }

  void _onAuthChanged() {
    final uid = _auth?.currentUserId;
    if (uid == _uid) return;
    _uid = uid;
    clear();
  }

  void dispose() => _auth?.removeListener(_onAuthChanged);
}
