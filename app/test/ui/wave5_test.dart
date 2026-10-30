import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/food_tags.dart';
import 'package:naarea/ui/dietary/dietary_store.dart';
import 'package:naarea/ui/feed/feed_view_model.dart';
import 'package:naarea/ui/core/follow_events.dart';
import 'package:naarea/ui/review/review_view_model.dart';
import 'package:naarea/ui/visit/visit_view_model.dart';
import 'package:naarea/ui/open/open_now_view_model.dart';
import '../support/builders.dart';
import '../support/fakes.dart';

void main() {
  test(
    'feed descarta leitura da conta anterior e erro de preferências exige retry sem exibir cards',
    () async {
      final auth = FakeAuthRepository(uid: 'a');
      final users = FakeUserRepository()
        ..addUser('a', 'Ana')
        ..addUser('b', 'Beto');
      final reviews = FakeReviewRepository()
        ..stored.add(review(authorId: 'amigo'));
      final preferences = FakeDietaryRepository();
      final store = DietaryStore(auth, preferences);
      await store.load();
      final vm = FeedViewModel(
        authRepository: auth,
        userRepository: users,
        reviewRepository: reviews,
        placeRepository: FakePlaceRepository([]),
        followEvents: FollowEvents(),
        visitRepository: FakeVisitRepository(),
        dietary: store,
        foodTagRepository: FakeFoodTagRepository(
          reviews,
          FakeOwnerRepository(),
        ),
      );
      final old = Completer<Set<String>>();
      users.getFollowingOverride = (uid) async =>
          uid == 'a' ? old.future : {'amigo'};
      final loading = vm.load();
      auth.restoreSession('b');
      expect(vm.items, isEmpty);
      old.complete({'amigo'});
      await loading;
      expect(vm.currentUserId, 'b');
      expect(vm.items, hasLength(1));
      preferences.fail = true;
      await store.load();
      expect(vm.items, isEmpty);
      expect(vm.errorMessage, isNotNull);
      await vm.retry();
      expect(vm.items, isEmpty);
      expect(vm.errorMessage, isNotNull);
      preferences.fail = false;
      await vm.retry();
      expect(vm.items, hasLength(1));
      vm.dispose();
      store.dispose();
    },
  );
  test(
    'quórum: autores distintos, última sem tags retira voto, empate por id e titular excluído',
    () {
      final rows = [
        for (var i = 0; i < 3; i++) review(authorId: 'a', tags: ['vegano']),
        review(authorId: 'b', tags: ['vegano']),
      ];
      expect(confirmedFoodTags(rows), isEmpty);
      rows.add(review(authorId: 'c', tags: ['vegano']));
      expect(confirmedFoodTags(rows), {'vegano': 3});
      expect(confirmedFoodTags(rows, ownerUid: 'c'), isEmpty);
      rows.add(review(authorId: 'a', tags: [], createdAt: DateTime.utc(2030)));
      expect(confirmedFoodTags(rows), isEmpty);
      expect(
        confirmedFoodTags([
          review(authorId: 'a', id: 'z', tags: []),
          review(authorId: 'a', id: 'a', tags: ['vegano']),
          review(authorId: 'b', tags: ['vegano']),
          review(authorId: 'c', tags: ['vegano']),
        ]),
        isEmpty,
      );
      expect(matchesFoodTags(['vegano', 'integral'], {'vegano': 3}), isFalse);
      expect(matchesFoodTags([], {}), isTrue);
    },
  );

  test(
    'preferências sobrevivem à nova sessão; troca de conta descarta resposta antiga',
    () async {
      final auth = FakeAuthRepository(uid: 'a');
      final repository = FakeDietaryRepository();
      final store = DietaryStore(auth, repository);
      await store.load();
      expect(await store.save({'vegano', 'integral'}), isTrue);
      store.dispose();
      final restored = DietaryStore(auth, repository);
      await restored.load();
      expect(restored.tags, {'vegano', 'integral'});
      final old = Completer<Set<String>>();
      repository.read = (uid) async => uid == 'a' ? old.future : {'caseiro'};
      final pending = restored.load();
      auth.restoreSession('b');
      await Future<void>.delayed(Duration.zero);
      expect(restored.tags, {'caseiro'});
      old.complete({'vegano'});
      await pending;
      expect(restored.tags, {'caseiro'});
      restored.dispose();
    },
  );

  test(
    'feed AND preserva fontes e ordenação; quórum global não adiciona desconhecidos; falha oculta cards e retry recupera',
    () async {
      final auth = FakeAuthRepository(uid: 'me');
      final users = FakeUserRepository()
        ..addUser('me', 'Eu')
        ..addUser('a', 'Ana');
      users.followingByUser['me'] = {'a'};
      final reviews = FakeReviewRepository();
      for (final id in ['x', 'y', 'z']) {
        reviews.stored.add(
          review(
            placeId: id,
            authorId: 'a',
            tags: id == 'y' ? ['vegano'] : ['vegano', 'integral'],
            createdAt: DateTime.utc(2030, 1, id == 'z' ? 3 : 1),
          ),
        );
        for (final uid in ['b', 'c']) {
          reviews.stored.add(
            review(
              placeId: id,
              authorId: uid,
              tags: id == 'y' ? ['vegano'] : ['vegano', 'integral'],
            ),
          );
        }
      }
      for (final uid in ['b', 'c', 'd']) {
        reviews.stored.add(
          review(
            placeId: 'desconhecido',
            authorId: uid,
            tags: ['vegano', 'integral'],
          ),
        );
      }
      final repository = FakeDietaryRepository()
        ..stored['me'] = {'vegano', 'integral'};
      final dietary = DietaryStore(auth, repository);
      await dietary.load();
      final tags = FakeFoodTagRepository(reviews, FakeOwnerRepository());
      final vm = FeedViewModel(
        authRepository: auth,
        userRepository: users,
        reviewRepository: reviews,
        placeRepository: FakePlaceRepository([]),
        followEvents: FollowEvents(),
        visitRepository: FakeVisitRepository(),
        dietary: dietary,
        foodTagRepository: tags,
      );
      await vm.load();
      expect(vm.items.map((i) => i.placeId), ['z', 'x']);
      expect(
        vm.items.every((i) => i.activities.every((a) => a.authorId == 'a')),
        isTrue,
      );
      tags.fail = true;
      await vm.load();
      expect(vm.items, isEmpty);
      expect(vm.errorMessage, isNotNull);
      tags.fail = false;
      await vm.load();
      expect(vm.items, hasLength(2));
      await dietary.save({});
      await vm.load();
      expect(vm.items, hasLength(3));
      vm.dispose();
      dietary.dispose();
    },
  );

  test(
    'titular bloqueado nos três formulários; outro local continua disponível',
    () async {
      final owner = FakeOwnerRepository()..owners['p1'] = 'me';
      final auth = FakeAuthRepository(uid: 'me');
      final users = FakeUserRepository()..addUser('me', 'Eu');
      final reviews = FakeReviewRepository();
      final visits = FakeVisitRepository();
      final vm = ReviewViewModel(
        place: place(),
        authRepository: auth,
        userRepository: users,
        reviewRepository: reviews,
        photoPicker: FakePhotoPicker(),
        compress: (b) async => b,
        ownerRepository: owner,
      );
      vm.setFood(4);
      await vm.checkLock();
      expect(vm.isOwnBusiness, isTrue);
      expect(vm.blockedMessage, contains('titular verificado'));
      expect(await vm.submit(), isFalse);
      expect(reviews.created, isEmpty);
      final visitVm = VisitViewModel(
        place: place(),
        authRepository: auth,
        userRepository: users,
        visitRepository: visits,
        ownerRepository: owner,
      );
      await visitVm.checkLock();
      expect(visitVm.isBlocked, isTrue);
      expect(await visitVm.submit(), isFalse);
      final open = OpenNowViewModel(
        placeId: 'p1',
        authRepository: auth,
        userRepository: users,
        openReportRepository: FakeOpenReportRepository(),
        ownerRepository: owner,
      );
      await open.load();
      expect(open.canReport, isFalse);
      expect(open.blockedLabel, contains('titular verificado'));
      final other = VisitViewModel(
        place: place(id: 'other'),
        authRepository: auth,
        userRepository: users,
        visitRepository: visits,
        ownerRepository: owner,
      );
      await other.checkLock();
      expect(other.canSubmit, isTrue);
      vm.dispose();
      visitVm.dispose();
      open.dispose();
      other.dispose();
    },
  );
}
