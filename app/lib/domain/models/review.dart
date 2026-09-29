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
  });

  final String id;
  final String authorId;
  final String authorName;
  final String placeId;
  final String placeName;
  final Scores scores;
  final Companion? companion;

  /// Timestamp do servidor.
  final DateTime createdAt;

  /// Derivado, nunca gravado.
  DayPeriod get dayPeriod => DayPeriod.fromTimestamp(createdAt);
}

/// Dados que o cliente envia para criar uma avaliação. `createdAt` não existe
/// aqui de propósito: é sempre o timestamp do servidor.
class NewReview {
  const NewReview({
    required this.authorId,
    required this.authorName,
    required this.placeId,
    required this.placeName,
    required this.scores,
    this.companion,
  });

  final String authorId;
  final String authorName;
  final String placeId;
  final String placeName;
  final Scores scores;
  final Companion? companion;
}
