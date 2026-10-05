import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
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
}
