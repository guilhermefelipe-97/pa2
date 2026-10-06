import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/feed.dart';
import 'package:naarea/ui/core/follow_events.dart';
import 'package:naarea/ui/place/place_detail_view_model.dart';

import '../support/builders.dart';
import '../support/fakes.dart';

void main() {
  late FakeAuthRepository auth;
  late FakeUserRepository users;
  late FakeReviewRepository reviews;
  late FakePlaceRepository places;

  setUp(() {
    auth = FakeAuthRepository(uid: 'me');
    users = FakeUserRepository()..followingByUser['me'] = {'a', 'b'};
    reviews = FakeReviewRepository()
      ..stored.addAll([
        review(
          id: 'r1',
          authorId: 'a',
          placeId: 'x',
          createdAt: DateTime.utc(2026, 9, 1),
        ),
        review(
          id: 'r2',
          authorId: 'b',
          placeId: 'x',
          createdAt: DateTime.utc(2026, 9, 3),
        ),
        review(
          id: 'r3',
          authorId: 'estranho',
          placeId: 'x',
          createdAt: DateTime.utc(2026, 9, 4),
        ),
        review(
          id: 'r5',
          authorId: 'a',
          placeId: 'y',
          createdAt: DateTime.utc(2026, 9, 2),
        ),
      ]);
    places = FakePlaceRepository([
      place(id: 'x', name: 'Mangai'),
      place(id: 'y'),
    ]);
  });

  PlaceDetailViewModel make(String id, {Object? initial}) =>
      PlaceDetailViewModel(
        placeId: id,
        initial: initial,
        authRepository: auth,
        userRepository: users,
        placeRepository: places,
        reviewRepository: reviews,
        followEvents: FollowEvents(),
      );

  test(
    'só com o id: carrega o local e só as avaliações de quem sigo, mais recentes primeiro',
    () async {
      final vm = make('x');
      expect(vm.place, isNull);
      await vm.load();
      expect(vm.place!.name, 'Mangai');
      expect(vm.reviews.map((r) => r.id), ['r2', 'r1']);
      expect(vm.item!.headline, 'B e A foram aqui');
      expect(vm.reviewCountLabel, '2 avaliações de amigos');
      expect(vm.hasOwnReview, isFalse);
    },
  );

  test(
    'avaliação própria aparece como "Você" e o CTA vira "Avaliar de novo"',
    () async {
      reviews.stored.add(
        review(
          id: 'mine',
          authorId: 'me',
          authorName: 'Eu',
          placeId: 'x',
          createdAt: DateTime.utc(2026, 9, 5),
        ),
      );
      final vm = make('x');
      await vm.load();
      expect(vm.reviews.first.id, 'mine');
      expect(vm.reviews.first.authorName, 'Você');
      expect(vm.hasOwnReview, isTrue);
      expect(vm.item!.headline, 'Você, B e A foram aqui');
      expect(vm.reviewCountLabel, '3 avaliações');
    },
  );

  test(
    'amigo com avaliação antiga não se perde atrás de 50 avaliações de terceiros',
    () async {
      reviews.stored.addAll([
        for (var i = 0; i < 60; i++)
          review(
            id: 'x$i',
            authorId: 'outro$i',
            placeId: 'x',
            createdAt: DateTime.utc(2026, 9, 10).add(Duration(minutes: i)),
          ),
      ]);
      final vm = make('x');
      await vm.load();
      expect(vm.reviews.map((r) => r.id), ['r2', 'r1']);
    },
  );

  test('não altera o Set devolvido por getFollowing', () async {
    final following = {'a', 'b'};
    users.getFollowingOverride = (_) async => following;
    await make('x').load();
    expect(following, {'a', 'b'});
  });

  test(
    'sem avaliações de amigos: reviewsKnown e lista vazia (sem item)',
    () async {
      users.followingByUser['me'] = {};
      final vm = make('x');
      await vm.load();
      expect(vm.place, isNotNull);
      expect(vm.reviewsKnown, isTrue);
      expect(vm.reviews, isEmpty);
      expect(vm.item, isNull);
    },
  );

  test(
    'id inexistente: notFound; recarga com o local de volta limpa o notFound',
    () async {
      final vm = make('z');
      await vm.load();
      expect(vm.notFound, isTrue);

      places.places.add(place(id: 'z', name: 'Voltou'));
      await vm.load();
      expect(vm.notFound, isFalse);
      expect(vm.place!.name, 'Voltou');
    },
  );

  test('sem usuário: erro em vez de carregar para sempre', () async {
    auth.restoreSession(null);
    final vm = make('x');
    await vm.load();
    expect(vm.isLoading, isFalse);
    expect(vm.errorMessage, PlaceDetailViewModel.errorText);
  });

  test(
    'com Place pronto (aba Quero ir): pinta já, avaliações chegam depois',
    () async {
      final vm = make(
        'x',
        initial: place(id: 'x', name: 'Mangai'),
      );
      expect(vm.place!.name, 'Mangai');
      expect(vm.reviewsKnown, isFalse);
      await vm.load();
      expect(vm.reviews, hasLength(2));
    },
  );

  test(
    'com Place pronto e falha nas avaliações: errorMessage preenchido',
    () async {
      reviews.placeFetchError = Exception('offline');
      final vm = make(
        'x',
        initial: place(id: 'x', name: 'Mangai'),
      );
      await vm.load();
      expect(vm.errorMessage, PlaceDetailViewModel.errorText);
      expect(vm.place, isNotNull);
    },
  );

  test(
    'FeedItem de local fora do catálogo continua (não vira "não encontrado")',
    () async {
      final item = groupReviewsIntoFeed([
        review(authorId: 'a', placeId: 'sumiu', placeName: 'Sumiu'),
      ]).single;
      final vm = make('sumiu', initial: item);
      await vm.load();
      expect(vm.notFound, isFalse);
      expect(vm.place!.name, 'Sumiu');
      expect(vm.place!.inCatalog, isFalse);
    },
  );

  test(
    'erro sem dados prontos: mensagem; com FeedItem pronto: silencioso',
    () async {
      reviews.placeFetchError = Exception('offline');
      final bare = make('x');
      await bare.load();
      expect(bare.errorMessage, PlaceDetailViewModel.errorText);

      final item = groupReviewsIntoFeed([
        review(authorId: 'a', placeId: 'x'),
      ]).single;
      final ready = make('x', initial: item);
      await ready.load();
      expect(ready.errorMessage, isNull);
      expect(ready.item, isNotNull);
    },
  );

  test('extra de outro local é ignorado', () {
    final vm = make('x', initial: place(id: 'y'));
    expect(vm.place, isNull);
  });

  test(
    'F06: deixar de seguir em outra tela marca stale; reloadIfStale tira a pessoa',
    () async {
      final events = FollowEvents();
      final vm = PlaceDetailViewModel(
        placeId: 'x',
        authRepository: auth,
        userRepository: users,
        placeRepository: places,
        reviewRepository: reviews,
        followEvents: events,
      );
      await vm.load();
      await vm.reloadIfStale();
      expect(reviews.placeFetchCalls, hasLength(1), reason: 'nada mudou');

      users.followingByUser['me'] = {'b'};
      events.changed();
      expect(vm.isStale, isTrue);
      await vm.reloadIfStale();
      expect(reviews.placeFetchCalls, hasLength(2));
      expect(vm.reviews.map((r) => r.id), ['r2']);
      vm.dispose();
    },
  );
}
