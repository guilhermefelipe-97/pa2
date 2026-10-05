import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/feed.dart';

import '../support/builders.dart';

DateTime t(int hour) => DateTime.utc(2026, 9, 1, hour);

void main() {
  test('A (com foto, há 1 h) e B (sem foto, agora): capa é a foto de A', () {
    final item = groupReviewsIntoFeed([
      review(
        id: 'ra',
        authorId: 'a',
        placeId: 'x',
        createdAt: t(10),
        hasPhoto: true,
      ),
      review(id: 'rb', authorId: 'b', placeId: 'x', createdAt: t(11)),
    ]).single;
    expect(item.latestPhoto?.id, 'ra');
  });

  test('várias com foto: a mais recente vence; photoReviews em ordem', () {
    final item = groupReviewsIntoFeed([
      review(id: 'r1', placeId: 'x', createdAt: t(8), hasPhoto: true),
      review(id: 'r2', placeId: 'x', createdAt: t(9)),
      review(id: 'r3', placeId: 'x', createdAt: t(10), hasPhoto: true),
    ]).single;
    expect(item.latestPhoto?.id, 'r3');
    expect(item.photoReviews.map((r) => r.id), ['r3', 'r1']);
  });

  test('ninguém com foto: sem capa de amigo', () {
    final item = groupReviewsIntoFeed([review(placeId: 'x')]).single;
    expect(item.latestPhoto, isNull);
    expect(item.photoReviews, isEmpty);
  });
}
