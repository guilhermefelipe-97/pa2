import 'package:naarea/domain/models/companion.dart';
import 'package:naarea/domain/models/review.dart';
import 'package:naarea/domain/models/scores.dart';

int _seq = 0;

Review review({
  String? id,
  String authorId = 'a',
  String? authorName,
  String placeId = 'p1',
  String? placeName,
  DateTime? createdAt,
  Scores? scores,
  Companion? companion,
}) {
  _seq++;
  return Review(
    id: id ?? 'r$_seq',
    authorId: authorId,
    authorName: authorName ?? authorId.toUpperCase(),
    placeId: placeId,
    placeName: placeName ?? 'Local $placeId',
    scores: scores ?? Scores(food: 4, ambience: 3, service: 5),
    companion: companion,
    createdAt: createdAt ?? DateTime.utc(2026, 9, 1, 15),
  );
}
