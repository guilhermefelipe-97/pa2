import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/ui/core/follow_events.dart';
import 'package:naarea/ui/feed/feed_view_model.dart';

import '../support/builders.dart';
import '../support/fakes.dart';

void main() {
  late FakeUserRepository users;
  late FakeReviewRepository reviews;
  late FakePlaceRepository places;
  late FeedViewModel vm;

  setUp(() {
    users = FakeUserRepository()
      ..addUser('me', 'Eu')
      ..addUser('a', 'Ana')
      ..addUser('b', 'Beto');
    reviews = FakeReviewRepository();
    places = FakePlaceRepository([
      place(
        id: 'x',
        name: 'Mangai',
        neighborhood: 'Tirol',
        photoUrl: 'https://f/x.jpg',
      ),
    ]);
    vm = FeedViewModel(
      authRepository: FakeAuthRepository(uid: 'me'),
      userRepository: users,
      reviewRepository: reviews,
      placeRepository: places,
      clock: () => DateTime.utc(2026, 9, 28, 15),
      followEvents: FollowEvents(),
    );
  });

  test(
    'não segue ninguém: estado vazio com CTA, sem consultar reviews',
    () async {
      await vm.load();
      expect(vm.followsNobody, isTrue);
      expect(vm.items, isEmpty);
      expect(reviews.fetchCalls, isEmpty);
    },
  );

  test('segue A e B que avaliaram X: 1 card "B e A foram aqui"', () async {
    users.followingByUser['me'] = {'a', 'b'};
    reviews.stored.addAll([
      review(
        authorId: 'a',
        authorName: 'Ana',
        placeId: 'x',
        createdAt: DateTime.utc(2026, 9, 1),
      ),
      review(
        authorId: 'b',
        authorName: 'Beto',
        placeId: 'x',
        createdAt: DateTime.utc(2026, 9, 2),
      ),
      review(
        authorId: 'z',
        authorName: 'Zé',
        placeId: 'x',
        createdAt: DateTime.utc(2026, 9, 3),
      ),
    ]);
    await vm.load();
    expect(vm.followsNobody, isFalse);
    expect(vm.items, hasLength(1));
    expect(vm.items.single.headline, 'Beto e Ana foram aqui');
    expect(vm.items.single.reviews, hasLength(2), reason: 'não segue Zé');
  });

  test('ordena cards pela avaliação mais recente', () async {
    users.followingByUser['me'] = {'a'};
    reviews.stored.addAll([
      review(authorId: 'a', placeId: 'x', createdAt: DateTime.utc(2026, 9, 1)),
      review(authorId: 'a', placeId: 'y', createdAt: DateTime.utc(2026, 9, 5)),
    ]);
    await vm.load();
    expect(vm.items.map((i) => i.placeId), ['y', 'x']);
  });

  test('erro de rede: mensagem e "Tentar de novo" recupera', () async {
    users.followingByUser['me'] = {'a'};
    reviews.stored.add(review(authorId: 'a', placeId: 'x'));
    reviews.fetchError = Exception('unavailable');
    await vm.load();
    expect(vm.errorMessage, isNotNull);
    expect(vm.isLoading, isFalse);

    reviews.fetchError = null;
    await vm.load();
    expect(vm.errorMessage, isNull);
    expect(vm.items, hasLength(1));
  });

  test(
    'segue mais de 30: repassa todos os uids (lotes no repositório)',
    () async {
      final ids = List.generate(65, (i) => 'u$i');
      users.followingByUser['me'] = ids.toSet();
      await vm.load();
      expect(reviews.fetchCalls.single.toSet(), ids.toSet());
    },
  );

  test(
    'load pedido durante uma carga não é perdido: roda de novo em seguida',
    () async {
      final gate = Completer<Set<String>>();
      var calls = 0;
      users.getFollowingOverride = (uid) {
        calls++;
        // 1ª carga fica presa até liberarmos; a 2ª já vê o novo following.
        return calls == 1 ? gate.future : Future.value({'a'});
      };
      reviews.stored.add(review(authorId: 'a', placeId: 'x'));

      final first = vm.load();
      expect(vm.isLoading, isTrue);
      final second = vm.load(); // chega durante a 1ª
      final third = vm.load(); // várias chegadas viram uma só recarga

      gate.complete(<String>{}); // 1ª carga: não seguia ninguém
      await Future.wait([first, second, third]);

      expect(calls, 2);
      expect(vm.followsNobody, isFalse);
      expect(vm.items.single.placeId, 'x');
      expect(vm.isLoading, isFalse);
    },
  );

  test('ignora o próprio uid caso apareça em following', () async {
    users.followingByUser['me'] = {'me', 'a'};
    await vm.load();
    expect(reviews.fetchCalls.single, ['a']);
  });

  test(
    'cards trazem o Place (foto, bairro) vindo do PlaceRepository',
    () async {
      users.followingByUser['me'] = {'a'};
      reviews.stored.add(
        review(authorId: 'a', placeId: 'x', placeName: 'Mangai'),
      );
      await vm.load();
      expect(vm.items.single.place.photoUrl, 'https://f/x.jpg');
      expect(vm.items.single.place.neighborhood, 'Tirol');
    },
  );

  test('lê só os locais que aparecem no feed, numa chamada', () async {
    users.followingByUser['me'] = {'a'};
    reviews.stored.addAll([
      review(authorId: 'a', placeId: 'x'),
      review(authorId: 'a', placeId: 'x'),
      review(authorId: 'a', placeId: 'fora-do-catalogo', placeName: 'Antigo'),
    ]);
    await vm.load();
    expect(places.getCalls, [
      {'x', 'fora-do-catalogo'},
    ]);
    expect(places.searchCalls, isEmpty);
    expect(places.suggestionCalls, 0);
    // Local ausente do catálogo: Place mínimo com o nome da avaliação.
    final antigo = vm.items.firstWhere((i) => i.placeId == 'fora-do-catalogo');
    expect(antigo.placeName, 'Antigo');
    expect(antigo.place.photoUrl, isNull);
  });

  test(
    'falha ao ler locais não derruba o feed: card com fallback e nova tentativa depois',
    () async {
      users.followingByUser['me'] = {'a'};
      reviews.stored.add(
        review(authorId: 'a', placeId: 'x', placeName: 'Mangai'),
      );
      places.fail = true;
      await vm.load();
      expect(vm.errorMessage, isNull);
      expect(vm.items.single.placeName, 'Mangai');
      expect(vm.items.single.place.photoUrl, isNull);

      places.fail = false;
      await vm.load();
      expect(places.getCalls, hasLength(2));
      expect(vm.items.single.place.photoUrl, 'https://f/x.jpg');
    },
  );

  test('não segue ninguém: não lê locais', () async {
    await vm.load();
    expect(places.getCalls, isEmpty);
  });

  test('segue alguém sem avaliações: não lê locais', () async {
    users.followingByUser['me'] = {'a'};
    await vm.load();
    expect(places.getCalls, isEmpty);
  });

  test('now() usa o relógio injetado (tempo relativo testável)', () {
    expect(vm.now(), DateTime.utc(2026, 9, 28, 15));
  });

  group('F06: relação e recarga quando o following muda', () {
    late FollowEvents events;
    late FakeAuthRepository auth;
    late FeedViewModel feed;

    setUp(() {
      events = FollowEvents();
      auth = FakeAuthRepository(uid: 'me');
      feed = FeedViewModel(
        authRepository: auth,
        userRepository: users,
        reviewRepository: reviews,
        placeRepository: places,
        followEvents: events,
      );
      users.followingByUser['me'] = {'a'};
      reviews.stored.add(review(authorId: 'a', placeId: 'x'));
    });

    tearDown(() => feed.dispose());

    test(
      'isFollowing vem do following já carregado, sem leituras extras',
      () async {
        await feed.load();
        final calls = users.getFollowingCalls;
        expect(feed.isFollowing('a'), isTrue);
        expect(feed.isFollowing('b'), isFalse);
        expect(feed.isFollowing('me'), isFalse);
        expect(users.getFollowingCalls, calls);
      },
    );

    test('reloadIfStale só recarrega depois de um aviso de mudança', () async {
      await feed.load();
      final calls = users.getFollowingCalls;

      await feed.reloadIfStale();
      expect(users.getFollowingCalls, calls, reason: 'nada mudou');

      // Deixou de seguir Ana no perfil.
      users.followingByUser['me'] = {};
      events.changed();
      expect(feed.isStale, isTrue);
      await feed.reloadIfStale();
      expect(users.getFollowingCalls, calls + 1);
      expect(feed.items, isEmpty);
      expect(feed.followsNobody, isTrue);
      expect(feed.isStale, isFalse);

      await feed.reloadIfStale();
      expect(users.getFollowingCalls, calls + 1, reason: 'já recarregou');
    });

    test(
      'carga em andamento que começou depois da mudança não agenda outra',
      () async {
        await feed.load();
        events.changed();
        final gate = Completer<Set<String>>();
        users.getFollowingOverride = (_) => gate.future;
        final calls = users.getFollowingCalls;

        final running = feed.load(); // começou depois do aviso
        await feed.reloadIfStale();
        await feed.reloadIfStale();
        users.getFollowingOverride = null;
        gate.complete({'a'});
        await running;
        expect(users.getFollowingCalls, calls + 1);
      },
    );

    test('aviso durante uma carga: uma única recarga depois dela', () async {
      await feed.load();
      final gate = Completer<Set<String>>();
      users.getFollowingOverride = (_) => gate.future;
      final calls = users.getFollowingCalls;

      final running = feed.load();
      events.changed(); // mudou enquanto a carga lia o estado antigo
      final again = feed.reloadIfStale();
      feed.reloadIfStale();
      users.getFollowingOverride = null;
      gate.complete({'a'});
      await running;
      await again;
      expect(users.getFollowingCalls, calls + 2);
    });

    test('carga com erro não fica recarregando sozinha ao voltar', () async {
      await feed.load();
      events.changed();
      users.failGetFollowing = true;
      await feed.reloadIfStale();
      expect(feed.errorMessage, isNotNull);
      final calls = users.getFollowingCalls;

      await feed.reloadIfStale();
      expect(
        users.getFollowingCalls,
        calls,
        reason: '"Tentar de novo" é manual',
      );
    });

    test(
      'falha no meio da carga não troca o following (estado coerente)',
      () async {
        await feed.load();
        users.followingByUser['me'] = {'b'};
        reviews.fetchError = Exception('network');
        await feed.load();
        expect(feed.errorMessage, isNotNull);
        expect(
          feed.isFollowing('a'),
          isTrue,
          reason: 'mantém a carga anterior',
        );
        expect(feed.isFollowing('b'), isFalse);
        expect(feed.items.single.sources.single.authorId, 'a');
      },
    );

    test('troca de usuário limpa a relação e os cards do anterior', () async {
      await feed.load();
      expect(feed.isFollowing('a'), isTrue);

      auth.restoreSession('outro');
      users.failGetFollowing = true;
      await feed.load();
      expect(feed.isFollowing('a'), isFalse);
      expect(feed.items, isEmpty);

      auth.restoreSession(null);
      await feed.load();
      expect(feed.isFollowing('a'), isFalse);
    });
  });
}
