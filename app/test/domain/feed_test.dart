import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/feed.dart';

import '../support/builders.dart';

DateTime t(int day, [int hour = 12]) => DateTime.utc(2026, 9, day, hour);

void main() {
  group('groupReviewsIntoFeed', () {
    test('lista vazia gera feed vazio', () {
      expect(groupReviewsIntoFeed([]), isEmpty);
    });

    test('A e B avaliaram X: um único card com os dois', () {
      final feed = groupReviewsIntoFeed([
        review(authorId: 'a', authorName: 'Ana', placeId: 'x', createdAt: t(1)),
        review(authorId: 'b', authorName: 'Beto', placeId: 'x', createdAt: t(2)),
      ]);
      expect(feed, hasLength(1));
      expect(feed.single.placeId, 'x');
      expect(feed.single.reviews, hasLength(2));
      // mais recente primeiro
      expect(feed.single.authorNames, ['Beto', 'Ana']);
      expect(feed.single.headline, 'Beto e Ana foram aqui');
    });

    test('cards ordenados pela avaliação mais recente de cada local', () {
      final feed = groupReviewsIntoFeed([
        review(placeId: 'x', createdAt: t(1)),
        review(placeId: 'y', createdAt: t(3)),
        review(placeId: 'x', createdAt: t(5)),
        review(placeId: 'z', createdAt: t(4)),
      ]);
      expect(feed.map((i) => i.placeId), ['x', 'z', 'y']);
      expect(feed.first.latestAt, t(5));
    });

    test('reviews dentro do card ordenadas da mais recente para a mais antiga', () {
      final feed = groupReviewsIntoFeed([
        review(id: 'old', placeId: 'x', createdAt: t(1)),
        review(id: 'new', placeId: 'x', createdAt: t(9)),
        review(id: 'mid', placeId: 'x', createdAt: t(5)),
      ]);
      expect(feed.single.reviews.map((r) => r.id), ['new', 'mid', 'old']);
    });

    test('mesmo autor duas vezes no local aparece uma vez no título', () {
      final feed = groupReviewsIntoFeed([
        review(authorId: 'a', authorName: 'Ana', placeId: 'x', createdAt: t(1)),
        review(authorId: 'a', authorName: 'Ana', placeId: 'x', createdAt: t(2)),
      ]);
      expect(feed.single.authorNames, ['Ana']);
      expect(feed.single.headline, 'Ana foi aqui');
    });

    test('empate de data é determinístico (por placeId)', () {
      final feed = groupReviewsIntoFeed([
        review(placeId: 'b', createdAt: t(1)),
        review(placeId: 'a', createdAt: t(1)),
      ]);
      expect(feed.map((i) => i.placeId), ['a', 'b']);
    });
  });

  group('formatVisitors', () {
    test('1, 2 e 3 nomes', () {
      expect(formatVisitors(['Ana']), 'Ana foi aqui');
      expect(formatVisitors(['Ana', 'Beto']), 'Ana e Beto foram aqui');
      expect(formatVisitors(['Ana', 'Beto', 'Caio']), 'Ana, Beto e Caio foram aqui');
    });
  });
}
