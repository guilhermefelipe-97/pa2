import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/queue_status.dart';
import 'package:naarea/domain/models/queue_report.dart';
import 'package:naarea/domain/models/place_activity.dart';
import 'package:naarea/domain/models/scores.dart';
import 'package:naarea/domain/feed.dart';

void main() {
  test(
    'Proximidade de fila rejeita NaN, infinito e coordenadas fora do intervalo',
    () {
      const place = (lat: -23.5, lng: -46.6);
      for (final device in [
        (lat: double.nan, lng: -46.6),
        (lat: double.infinity, lng: 0.0),
        (lat: 91.0, lng: 0.0),
        (lat: 0.0, lng: 181.0),
      ]) {
        expect(nearForQueue(device, place), false);
        expect(nearForQueue(place, device), false);
      }
      expect(nearForQueue(place, place), true);
    },
  );
  final now = DateTime.utc(2026, 10, 30, 21);
  QueueReport report(String id, String uid, int minutes, DateTime at) =>
      QueueReport(
        id: id,
        authorId: uid,
        authorName: uid,
        placeId: 'p',
        minutes: minutes,
        createdAt: at,
      );
  test(
    'Histórico distingue bucket UTC de UTC−3 e faixa local que cruza meia-noite UTC',
    () {
      final evening = DateTime.utc(2026, 10, 30, 21);
      final rows = [
        for (var i = 1; i <= 3; i++)
          report('$i', 'a$i', 10, evening.subtract(Duration(days: 7 * i))),
      ];
      rows.add(report('fora', 'fora', 180, DateTime.utc(2026, 10, 23, 20)));
      expect(historicalQueue(rows, evening)!.count, 3);
      // 23 UTC e 00 UTC pertencem à mesma faixa local 20–21 e ao mesmo dia local.
      final midnight = DateTime.utc(2026, 10, 31, 0);
      final crossing = [
        for (var i = 1; i <= 3; i++)
          report(
            '$i',
            'a$i',
            10,
            DateTime.utc(2026, 10, 30, 23).subtract(Duration(days: 7 * i)),
          ),
      ];
      expect(historicalQueue(crossing, midnight)!.count, 3);
    },
  );
  test(
    'Ao vivo usa último relato por pessoa, mediana, idade e expira em 60 min',
    () {
      final rows = [
        report('1', 'a', 100, now.subtract(const Duration(minutes: 40))),
        report('2', 'a', 10, now.subtract(const Duration(minutes: 5))),
        report('3', 'b', 30, now.subtract(const Duration(minutes: 3))),
        report('4', 'c', 180, now.subtract(const Duration(hours: 1))),
        report('5', 'd', 180, now.add(const Duration(minutes: 1))),
      ];
      final live = liveQueue(rows, now)!;
      expect(live.count, 2);
      expect(live.median, 20);
      expect(live.latest, now.subtract(const Duration(minutes: 3)));
      expect(
        liveQueue(rows.take(4), now.add(const Duration(hours: 1))),
        isNull,
      );
    },
  );
  test(
    'Histórico recorta UTC−3, dia/faixa2h, 28dias e 3 pessoas distintas',
    () {
      final rows = [
        report('1', 'a', 10, now.subtract(const Duration(days: 7))),
        report('2', 'b', 20, now.subtract(const Duration(days: 14))),
        report('3', 'c', 30, now.subtract(const Duration(days: 21))),
        report('4', 'd', 180, now.subtract(const Duration(days: 28))),
        report('5', 'e', 180, now.subtract(const Duration(days: 7, hours: 2))),
        report('6', 'f', 180, now.subtract(const Duration(days: 6))),
      ];
      final history = historicalQueue(rows, now)!;
      expect(history.count, 3);
      expect(history.median, 20);
      expect(history.p25, 15);
      expect(history.p75, 25);
      expect(historicalQueue(rows.take(2), now), isNull);
    },
  );
  test(
    'Amigos não cria nem ordena card ou revela foto/comentário/fonte/selo silencioso',
    () {
      Review review(String id, String place, bool silent, DateTime at) =>
          Review(
            id: id,
            authorId: id,
            authorName: id,
            placeId: place,
            placeName: place,
            scores: Scores(food: 4),
            companion: null,
            createdAt: at,
            silent: silent,
            comment: silent ? 'Segredo' : null,
            hasPhoto: silent,
          );
      final rows = [
        review('a', 'p', false, now.subtract(const Duration(days: 1))),
        review('b', 'p', true, now),
        review('c', 'q', true, now),
      ];
      final public = groupPublicActivitiesIntoFeed(rows);
      expect(public, hasLength(1));
      expect(public.single.latestAt, rows.first.createdAt);
      expect(public.single.latestPhoto, isNull);
      expect(public.single.latestComment, isNull);
      expect(public.single.authorNames, ['a']);
      expect(public.single.recurrent, isNull);
      expect(groupActivitiesIntoFeed(rows), hasLength(2));
    },
  );
}
