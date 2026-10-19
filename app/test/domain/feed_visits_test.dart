import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/feed.dart';
import 'package:naarea/domain/models/place_activity.dart';
import 'package:naarea/domain/models/scores.dart';

import '../support/builders.dart';

DateTime t(int h) => DateTime.utc(2026, 9, 1, h);

/// Exaustivo sem caso genérico: `PlaceActivity` é sealed.
String kind(PlaceActivity a) => switch (a) {
  Review() => 'avaliação',
  Visit() => 'visita',
};

void main() {
  group('F15: idas no feed e recorrência', () {
    test('local só com visitas vira card, com fonte sem eixos', () {
      final feed = groupActivitiesIntoFeed([
        visit(authorId: 'ana', placeId: 'x', createdAt: t(10)),
      ]);
      expect(feed, hasLength(1));
      final item = feed.single;
      expect(item.reviews, isEmpty);
      expect(item.placeName, 'Local x');
      expect(item.averages, isNull);
      expect(item.headline, 'ANA foi aqui');
      final s = item.sources.single;
      expect(s.onlyVisits, isTrue);
      expect(s.reviewIsOlder, isFalse);
      expect(s.trips, 1);
      expect(item.recurrent, isNull);
    });

    test('Ana: 1 avaliação + 2 visitas = 3 idas; eixos da avaliação, ida '
        'mais recente da visita; selo de recorrência', () {
      final r = review(
        authorId: 'ana',
        placeId: 'x',
        createdAt: t(1),
        scores: Scores(food: 5, ambience: 4, service: null),
      );
      final v1 = visit(authorId: 'ana', placeId: 'x', createdAt: t(5));
      final v2 = visit(authorId: 'ana', placeId: 'x', createdAt: t(9));
      final item = groupActivitiesIntoFeed([v1, r, v2]).single;
      final s = item.sources.single;
      expect(s.trips, 3);
      expect(s.latest, same(v2));
      expect(s.latestReview, same(r));
      expect(s.reviewIsOlder, isTrue);
      expect(item.latestAt, t(9));
      expect(item.trips, 3);
      expect(item.activities.map(kind), ['visita', 'visita', 'avaliação']);
      expect(item.reviews, [r]);
      expect(item.visits, [v2, v1]);
      expect(item.recurrent, same(s));
      // Texto sem o emoji: o selo acrescenta o 🔁 decorativo.
      expect(recurrenceLabel('Ana', s.trips), 'Ana voltou 3 vezes');
      expect(item.averages!.total, 1);
    });

    test('FeedItem recebe as idas em qualquer ordem, sem exigir avaliação', () {
      final item = FeedItem(
        place: place(id: 'x'),
        activities: [
          visit(authorId: 'a', placeId: 'x', createdAt: t(1)),
          visit(authorId: 'b', placeId: 'x', createdAt: t(3)),
        ],
      );
      expect(item.activities.map((a) => a.authorId), ['b', 'a']);
      expect(item.reviews, isEmpty);
    });

    test('ordem dos cards e das fontes considera visitas', () {
      final feed = groupActivitiesIntoFeed([
        review(authorId: 'bia', placeId: 'x', createdAt: t(3)),
        review(authorId: 'bia', placeId: 'y', createdAt: t(4)),
        visit(authorId: 'ana', placeId: 'x', createdAt: t(8)),
      ]);
      expect(feed.map((i) => i.placeId), ['x', 'y']);
      expect(feed.first.sources.map((s) => s.authorId), ['ana', 'bia']);
    });

    test('nome do fallback vem da avaliação, se houver', () {
      final item = groupActivitiesIntoFeed([
        review(placeId: 'x', placeName: 'Nome da avaliação', createdAt: t(1)),
        visit(placeId: 'x', placeName: 'Nome da visita', createdAt: t(5)),
      ]).single;
      expect(item.placeName, 'Nome da avaliação');
    });

    test('selo: quem mais voltou (empate: mais recente); nenhum com 1 ida', () {
      final item = groupActivitiesIntoFeed([
        review(authorId: 'bia', placeId: 'x', createdAt: t(1)),
        review(authorId: 'caio', placeId: 'x', createdAt: t(2)),
        visit(authorId: 'bia', placeId: 'x', createdAt: t(3)),
        visit(authorId: 'caio', placeId: 'x', createdAt: t(6)),
      ]).single;
      expect(item.recurrent!.authorId, 'caio');
      final none = groupActivitiesIntoFeed([
        review(authorId: 'bia', placeId: 'x'),
        visit(authorId: 'caio', placeId: 'x'),
      ]).single;
      expect(none.recurrent, isNull);
    });

    test('TrustSource: avaliação mais recente é a dona dos eixos', () {
      final r = review(authorId: 'ana');
      final s = TrustSource(latest: r, trips: 2);
      expect(s.latestReview, same(r));
      expect(s.onlyVisits, isFalse);
      expect(s.reviewIsOlder, isFalse);
      expect(
        TrustSource(latest: visit(authorId: 'ana'), trips: 1).onlyVisits,
        isTrue,
      );
    });

    test('rótulo do detalhe (sem emoji): "5 idas de 3 amigos" e variações', () {
      String? label(int trips, int friends, int own, {bool returned = true}) =>
          placeRecurrenceLabel(
            trips: trips,
            friends: friends,
            ownTrips: own,
            anyoneReturned: returned,
          );
      expect(label(5, 3, 0), '5 idas de 3 amigos');
      expect(label(2, 1, 0), '2 idas de 1 amigo');
      expect(label(3, 0, 3), '3 idas suas');
      expect(label(4, 2, 2), '4 idas suas e de 2 amigos');
      expect(label(3, 3, 0, returned: false), isNull);
    });
  });
}
