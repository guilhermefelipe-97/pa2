import 'package:naarea/domain/models/companion.dart';
import 'package:naarea/domain/models/place.dart';
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
  String? comment,
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
    comment: comment,
    createdAt: createdAt ?? DateTime.utc(2026, 9, 1, 15),
  );
}

Place place({
  String id = 'p1',
  String? name,
  String category = 'Restaurante',
  String neighborhood = 'Ponta Negra',
  String city = 'Natal',
  String? photoUrl,
  String? photoAuthor,
  String? photoLicense,
  bool photoIllustrative = false,
  String? cuisine,
  String? address,
  String? osmId,
  PlaceSource source = PlaceSource.curated,
}) {
  return Place(
    id: id,
    name: name ?? 'Local $id',
    category: category,
    neighborhood: neighborhood,
    city: city,
    photoUrl: photoUrl,
    photoAuthor: photoAuthor,
    photoLicense: photoLicense,
    photoIllustrative: photoIllustrative,
    cuisine: cuisine,
    address: address,
    osmId: osmId,
    source: source,
  );
}
