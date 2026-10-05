import 'companion.dart';
import 'day_period.dart';
import 'scores.dart';

/// Avaliação já gravada (lida do Firestore).
class Review {
  const Review({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.placeId,
    required this.placeName,
    required this.scores,
    required this.companion,
    required this.createdAt,
    this.comment,
    this.hasPhoto = false,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String placeId;
  final String placeName;
  final Scores scores;
  final Companion? companion;

  /// Comentário opcional do autor (aparado; nunca vazio). Imutável como a
  /// avaliação.
  final String? comment;

  /// Timestamp do servidor.
  final DateTime createdAt;

  /// Há uma foto do autor em `reviewPhotos/{id}` (G1). Avaliações antigas,
  /// sem a chave, são tratadas como sem foto.
  final bool hasPhoto;

  /// Derivado, nunca gravado.
  DayPeriod get dayPeriod => DayPeriod.fromTimestamp(createdAt);

  /// Mesmo limite das Security Rules (`comment.size() <= 280`).
  static const int maxCommentLength = 280;

  /// Texto aparado; vazio ou só espaços vira `null` (sem comentário).
  static String? normalizeComment(String? raw) {
    final trimmed = raw?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// Conta em unidades UTF-16 (`String.length`), igual ao `size()` das Rules
  /// (verificado no Emulator): um emoji fora do BMP conta 2.
  static bool isCommentWithinLimit(String? raw) =>
      (normalizeComment(raw)?.length ?? 0) <= maxCommentLength;
}

/// Dados que o cliente envia para criar uma avaliação. `createdAt` não existe
/// aqui de propósito: é sempre o timestamp do servidor.
class NewReview {
  NewReview({
    required this.authorId,
    required this.authorName,
    required this.placeId,
    required this.placeName,
    required this.scores,
    this.companion,
    String? comment,
  }) : comment = Review.normalizeComment(comment);

  final String authorId;
  final String authorName;
  final String placeId;
  final String placeName;
  final Scores scores;
  final Companion? companion;

  /// Normalizado na criação (trim; vazio → `null`).
  final String? comment;
}
