import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/models/user_profile.dart';
import 'package:naarea/ui/feed/feed_view_model.dart';
import 'package:naarea/ui/people/people_view_model.dart';

import '../support/builders.dart';
import '../support/fakes.dart';

void main() {
  late FakeAuthRepository auth;
  late FakeUserRepository users;
  late PeopleViewModel vm;

  setUp(() {
    users = FakeUserRepository()
      ..addUser('me', 'Bia Eu Mesma')
      ..addUser('bianca', 'Bianca')
      ..addUser('biazinha', 'Biazinha')
      ..addUser('toni', 'Toni');
    auth = FakeAuthRepository(uid: 'me');
    vm = PeopleViewModel(authRepository: auth, userRepository: users);
  });

  test('busca "bia" encontra por prefixo e não lista a si mesmo', () async {
    await vm.init();
    await vm.search('bia');
    expect(vm.results.map((p) => p.uid), unorderedEquals(['bianca', 'biazinha']));
  });

  test('busca vazia limpa resultados', () async {
    await vm.search('bia');
    await vm.search('  ');
    expect(vm.results, isEmpty);
  });

  test('seguir e deixar de seguir', () async {
    await vm.init();
    await vm.search('bia');
    await vm.toggleFollow('bianca');
    expect(vm.isFollowing('bianca'), isTrue);
    expect(users.followingByUser['me'], contains('bianca'));

    await vm.toggleFollow('bianca');
    expect(vm.isFollowing('bianca'), isFalse);
    expect(users.followingByUser['me'], isNot(contains('bianca')));
  });

  test('falha ao seguir mostra erro e não marca como seguindo', () async {
    await vm.init();
    users.failFollow = true;
    await vm.toggleFollow('bianca');
    expect(vm.isFollowing('bianca'), isFalse);
    expect(vm.errorMessage, isNotNull);
    expect(vm.isBusy('bianca'), isFalse);
  });

  test('não segue a si mesmo', () async {
    await vm.init();
    await vm.toggleFollow('me');
    expect(users.followingByUser['me'], isNull);
  });

  group('init', () {
    test('antes de carregar following os botões ficam desabilitados', () async {
      final gate = Completer<Set<String>>();
      users.getFollowingOverride = (_) => gate.future;
      final pending = vm.init();
      expect(vm.initState, PeopleInitState.loading);
      expect(vm.canToggle('bianca'), isFalse);
      await vm.toggleFollow('bianca');
      expect(users.followingByUser['me'], isNull, reason: 'toggle ignorado antes do init');

      gate.complete({'toni'});
      await pending;
      expect(vm.isReady, isTrue);
      expect(vm.isFollowing('toni'), isTrue);
      expect(vm.canToggle('bianca'), isTrue);
    });

    test('falha no init: estado de erro e retry recupera', () async {
      users.failGetFollowing = true;
      await vm.init();
      expect(vm.initState, PeopleInitState.error);
      expect(vm.canToggle('bianca'), isFalse);

      users.failGetFollowing = false;
      users.followingByUser['me'] = {'toni'};
      await vm.init();
      expect(vm.isReady, isTrue);
      expect(vm.isFollowing('toni'), isTrue);
    });

    test('retry do init não apaga um seguir concluído durante a carga (merge)', () async {
      await vm.init();
      users.followGate = Completer<void>();
      final toggling = vm.toggleFollow('bianca'); // fica preso no follow

      final initGate = Completer<Set<String>>();
      users.getFollowingOverride = (_) => initGate.future;
      final reinit = vm.init(); // recarga começa antes do follow terminar

      users.followGate!.complete();
      await toggling;
      initGate.complete(<String>{}); // resposta desatualizada: ainda sem bianca
      await reinit;

      expect(vm.isFollowing('bianca'), isTrue);
      expect(users.followingByUser['me'], contains('bianca'));
    });

    test('falha ao seguir busca following de novo e reconcilia', () async {
      await vm.init();
      users.failFollow = true;
      // o servidor na verdade já tinha aplicado (resposta perdida)
      users.followingByUser['me'] = {'bianca'};
      final before = users.getFollowingCalls;
      await vm.toggleFollow('bianca'); // local achava que não seguia
      expect(users.getFollowingCalls, before + 1);
      expect(vm.isFollowing('bianca'), isTrue);
      expect(vm.errorMessage, isNotNull);
    });
  });

  test('respostas fora de ordem: vale a busca mais recente', () async {
    final a = Completer<List<UserProfile>>();
    final b = Completer<List<UserProfile>>();
    users.searchOverride = (q) => q == 'bi' ? a.future : b.future;

    final searchA = vm.search('bi');
    final searchB = vm.search('toni');
    expect(vm.isSearching, isTrue);

    b.complete([const UserProfile(uid: 'toni', displayName: 'Toni')]);
    await searchB;
    expect(vm.results.map((p) => p.uid), ['toni']);
    expect(vm.isSearching, isFalse);

    a.complete([const UserProfile(uid: 'bianca', displayName: 'Bianca')]);
    await searchA;
    expect(vm.results.map((p) => p.uid), ['toni'], reason: 'resposta velha de A é descartada');
    expect(vm.isSearching, isFalse);
    expect(vm.lastQuery, 'toni');
  });

  test('AC: busca "bia", segue Bianca, e as avaliações dela aparecem no feed', () async {
    final reviews = FakeReviewRepository()
      ..stored.add(review(authorId: 'bianca', authorName: 'Bianca', placeId: 'mangai'));
    final feed = FeedViewModel(
      authRepository: auth,
      userRepository: users,
      reviewRepository: reviews,
    );
    await feed.load();
    expect(feed.followsNobody, isTrue);

    await vm.init();
    await vm.search('bia');
    await vm.toggleFollow('bianca');

    await feed.load();
    expect(feed.items.single.placeId, 'mangai');
    expect(feed.items.single.headline, 'Bianca foi aqui');
  });
}
