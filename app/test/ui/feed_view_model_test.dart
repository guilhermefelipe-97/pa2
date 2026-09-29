import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/ui/feed/feed_view_model.dart';

import '../support/builders.dart';
import '../support/fakes.dart';

void main() {
  late FakeUserRepository users;
  late FakeReviewRepository reviews;
  late FeedViewModel vm;

  setUp(() {
    users = FakeUserRepository()
      ..addUser('me', 'Eu')
      ..addUser('a', 'Ana')
      ..addUser('b', 'Beto');
    reviews = FakeReviewRepository();
    vm = FeedViewModel(
      authRepository: FakeAuthRepository(uid: 'me'),
      userRepository: users,
      reviewRepository: reviews,
    );
  });

  test('não segue ninguém: estado vazio com CTA, sem consultar reviews', () async {
    await vm.load();
    expect(vm.followsNobody, isTrue);
    expect(vm.items, isEmpty);
    expect(reviews.fetchCalls, isEmpty);
  });

  test('segue A e B que avaliaram X: 1 card "B e A foram aqui"', () async {
    users.followingByUser['me'] = {'a', 'b'};
    reviews.stored.addAll([
      review(authorId: 'a', authorName: 'Ana', placeId: 'x', createdAt: DateTime.utc(2026, 9, 1)),
      review(authorId: 'b', authorName: 'Beto', placeId: 'x', createdAt: DateTime.utc(2026, 9, 2)),
      review(authorId: 'z', authorName: 'Zé', placeId: 'x', createdAt: DateTime.utc(2026, 9, 3)),
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

  test('segue mais de 30: repassa todos os uids (lotes no repositório)', () async {
    final ids = List.generate(65, (i) => 'u$i');
    users.followingByUser['me'] = ids.toSet();
    await vm.load();
    expect(reviews.fetchCalls.single.toSet(), ids.toSet());
  });

  test('load pedido durante uma carga não é perdido: roda de novo em seguida', () async {
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
  });

  test('ignora o próprio uid caso apareça em following', () async {
    users.followingByUser['me'] = {'me', 'a'};
    await vm.load();
    expect(reviews.fetchCalls.single, ['a']);
  });
}
