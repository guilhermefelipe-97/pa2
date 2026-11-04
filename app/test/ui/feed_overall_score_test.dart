import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/feed.dart';
import 'package:naarea/domain/models/scores.dart';
import 'package:naarea/ui/feed/widgets/feed_card.dart';

import '../support/builders.dart';
import '../support/app_harness.dart';
import '../support/fakes.dart';

void main() {
  testWidgets(
    'feed mostra comentário recente com autoria e ignora texto vazio',
    (tester) async {
      final users = FakeUserRepository()
        ..addUser('me', 'Bianca')
        ..addUser('ana', 'Ana Silva')
        ..followingByUser['me'] = {'ana'};
      final reviews = FakeReviewRepository()
        ..stored.addAll([
          review(
            authorId: 'ana',
            comment: '   ',
            createdAt: DateTime.utc(2026, 10, 31),
          ),
          review(
            authorId: 'ana',
            authorName: 'Ana Silva',
            comment: 'Café muito bom.',
            createdAt: DateTime.utc(2026, 10, 30),
          ),
          review(
            authorId: 'ana',
            comment: 'Comentário antigo',
            createdAt: DateTime.utc(2026, 10, 29),
          ),
        ]);
      await pumpApp(tester, users: users, reviews: reviews, places: [place()]);
      expect(find.text('“Café muito bom.”'), findsOneWidget);
      expect(find.text('— Ana Silva'), findsOneWidget);
      expect(find.textContaining('Comentário antigo'), findsNothing);
    },
  );

  test(
    'nota geral usa a avaliação mais recente de cada amigo e os eixos informados',
    () {
      final item = FeedItem(
        place: place(),
        activities: [
          review(
            authorId: 'ana',
            createdAt: DateTime.utc(2026, 1, 2),
            scores: Scores(food: 5),
          ),
          review(
            authorId: 'ana',
            createdAt: DateTime.utc(2026, 1, 1),
            scores: Scores(food: 1),
          ),
          review(authorId: 'bia', scores: Scores(food: 3, ambience: 5)),
          visit(authorId: 'caio'),
        ],
      );
      expect(friendsOverallScore(item), 4.5);
      expect(
        friendsOverallScore(FeedItem(place: place(), activities: [visit()])),
        isNull,
      );
    },
  );
}
