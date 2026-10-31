import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:naarea/data/repositories/food_tag_repository.dart';
import 'package:naarea/data/repositories/owner_repository.dart';
import 'package:naarea/ui/core/follow_events.dart';
import 'package:naarea/ui/dietary/dietary_store.dart';
import 'package:naarea/ui/dietary/dietary_view.dart';
import 'package:naarea/ui/place/place_detail_view_model.dart';
import 'package:naarea/ui/review/review_view_model.dart';
import 'package:naarea/ui/review/review_view.dart';
import 'package:naarea/ui/visit/visit_view_model.dart';
import 'package:naarea/ui/open/open_now_view_model.dart';
import 'package:naarea/ui/open/open_now_section.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/routing/routes.dart';
import '../support/app_harness.dart';
import '../support/builders.dart';
import '../support/fakes.dart';
import '../support/geo_helpers.dart';

class _SavingDietary extends FakeDietaryRepository {
  Completer<void>? gate;
  @override
  Future<void> save(String uid, Set<String> tags) async {
    await gate?.future;
    await super.save(uid, tags);
  }
}

class _Tags implements FoodTagRepository {
  final reads = <Completer<Map<String, Map<String, int>>>>[];
  @override
  Future<Map<String, Map<String, int>>> confirmedFor(Iterable<String> ids) {
    final read = Completer<Map<String, Map<String, int>>>();
    reads.add(read);
    return read.future;
  }
}

class _Owners extends FakeOwnerRepository {
  Future<String?>? pending;
  int ownerReads = 0;
  int requestReads = 0;
  @override
  Future<String?> ownerOf(String id) {
    ownerReads++;
    return pending ?? super.ownerOf(id);
  }

  @override
  Future<List<OwnershipRequest>> requestsOf(String uid) {
    requestReads++;
    return super.requestsOf(uid);
  }
}

void main() {
  test(
    'preferências ignoram cargas invertidas, falha superada e carga anterior ao save',
    () async {
      final repository = FakeDietaryRepository();
      final first = Completer<Set<String>>();
      final second = Completer<Set<String>>();
      var calls = 0;
      repository.read = (_) => ++calls == 1 ? first.future : second.future;
      final store = DietaryStore(FakeAuthRepository(uid: 'me'), repository);
      final latest = store.load();
      second.complete({'vegano'});
      await latest;
      first.completeError(StateError('resposta antiga'));
      await Future<void>.delayed(Duration.zero);
      expect(store.tags, {'vegano'});
      expect(store.error, isNull);
      final stale = Completer<Set<String>>();
      repository.read = (_) => stale.future;
      final pending = store.load();
      expect(await store.save({'integral'}), isTrue);
      stale.complete({'caseiro'});
      await pending;
      expect(store.tags, {'integral'});
      expect(repository.stored['me'], {'integral'});
      store.dispose();
    },
  );

  test(
    'detalhe ignora sucesso e falha de tags superados por carga posterior',
    () async {
      final tags = _Tags();
      final vm = PlaceDetailViewModel(
        placeId: 'p1',
        authRepository: FakeAuthRepository(uid: 'me'),
        userRepository: FakeUserRepository(),
        placeRepository: FakePlaceRepository([]),
        reviewRepository: FakeReviewRepository(),
        visitRepository: FakeVisitRepository(),
        followEvents: FollowEvents(),
        foodTagRepository: tags,
      );
      final old = vm.loadTags();
      final latest = vm.loadTags();
      tags.reads[1].complete({
        'p1': {'vegano': 3},
      });
      await latest;
      tags.reads[0].completeError(StateError('antiga'));
      await old;
      expect(vm.confirmedTags, {'vegano': 3});
      expect(vm.tagsFailed, isFalse);
      final a = vm.loadTags();
      final b = vm.loadTags();
      tags.reads[3].complete({
        'p1': {'integral': 4},
      });
      await b;
      tags.reads[2].complete({
        'p1': {'vegano': 3},
      });
      await a;
      expect(vm.confirmedTags, {'integral': 4});
      vm.dispose();
    },
  );

  testWidgets(
    'editor rolável com texto ampliado pode sair enquanto save termina',
    (tester) async {
      tester.view.physicalSize = const Size(380, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _SavingDietary()..gate = Completer<void>();
      final store = DietaryStore(FakeAuthRepository(uid: 'me'), repository);
      await store.load();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: store,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const DietaryView(),
                    ),
                  ),
                  child: const Text('Abrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Salvar preferências'), 180);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Salvar preferências'));
      await tester.pump();
      Navigator.of(tester.element(find.byType(DietaryView))).pop();
      await tester.pumpAndSettle();
      repository.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Abrir'), findsOneWidget);
      expect(tester.takeException(), isNull);
      store.dispose();
    },
  );

  testWidgets(
    'lookup pendente tem timeout recuperável em check e submit dos três fluxos',
    (tester) async {
      final owners = _Owners()..pending = Completer<String?>().future;
      final auth = FakeAuthRepository(uid: 'me');
      final users = FakeUserRepository()..addUser('me', 'Eu');
      final review = ReviewViewModel(
        place: place(),
        authRepository: auth,
        userRepository: users,
        reviewRepository: FakeReviewRepository(),
        photoPicker: FakePhotoPicker(),
        compress: (b) async => b,
        ownerRepository: owners,
      )..setFood(4);
      final visit = VisitViewModel(
        place: place(),
        authRepository: auth,
        userRepository: users,
        visitRepository: FakeVisitRepository(),
        ownerRepository: owners,
      );
      final checks = Future.wait([review.checkLock(), visit.checkLock()]);
      await tester.pump(const Duration(seconds: 6));
      await checks;
      expect(review.isCheckingLock, isFalse);
      expect(visit.isCheckingLock, isFalse);
      final sends = Future.wait([review.submit(), visit.submit()]);
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 6));
      expect(await sends, [false, false]);
      expect(review.isSubmitting, isFalse);
      expect(visit.isSubmitting, isFalse);
      owners.pending = null;
      final p = placeNear('p1', 80);
      final open = OpenNowViewModel(
        placeId: 'p1',
        authRepository: auth,
        userRepository: users,
        openReportRepository: FakeOpenReportRepository(),
        ownerRepository: owners,
        locationService: FakeLocationService(
          position: pontaNegra,
          granted: true,
        ),
      );
      open.attach(p);
      await open.load();
      expect(open.canReport, isTrue);
      owners.pending = Completer<String?>().future;
      final load = open.load();
      await tester.pump(const Duration(seconds: 6));
      await load;
      final send = open.submit(open: true);
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 6));
      expect(await send, isFalse);
      expect(open.isSubmitting, isFalse);
      review.dispose();
      visit.dispose();
      open.dispose();
    },
  );

  testWidgets(
    'titular sem permissão vê restrição antes de convite de localização',
    (tester) async {
      final p = placeNear('p1', 80);
      final owners = FakeOwnerRepository()..owners['p1'] = 'me';
      final location = FakeLocationService(
        position: pontaNegra,
        granted: false,
      );
      final vm = OpenNowViewModel(
        placeId: 'p1',
        authRepository: FakeAuthRepository(uid: 'me'),
        userRepository: FakeUserRepository(),
        openReportRepository: FakeOpenReportRepository(),
        ownerRepository: owners,
        locationService: location,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OpenNowSection(viewModel: vm, place: p),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('open-owner-blocked')), findsOneWidget);
      expect(find.byKey(const Key('open-ask-location')), findsNothing);
      expect(location.locateCalls, 0);
      vm.dispose();
    },
  );

  for (final scenario in ['sucesso', 'falha', 'troca']) {
    testWidgets('pedido de local descoberto aguarda persistência: $scenario', (
      tester,
    ) async {
      final owners = FakeOwnerRepository();
      const discovered = Place(
        id: 'osm-n42',
        name: 'Local descoberto',
        category: 'Restaurante',
        neighborhood: '',
        city: 'Natal',
        source: PlaceSource.osm,
        discovered: true,
      );
      final places = FakePlaceRepository([discovered]);
      places.discovered[discovered.id] = discovered;
      places.persistGate = Completer<void>();
      if (scenario == 'falha') places.persistError = StateError('offline');
      final app = await pumpApp(
        tester,
        owners: owners,
        placeRepository: places,
      );
      app.router.go(Routes.placeDetail(discovered.id));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Solicitar titularidade'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Este estabelecimento é seu? Solicitar titularidade'),
      );
      await tester.pump();
      expect(places.persistCalls, ['me:osm-n42']);
      expect(owners.requests, isEmpty);
      if (scenario == 'troca') {
        app.auth.restoreSession('other');
        await tester.pump();
      }
      places.persistGate!.complete();
      await tester.pumpAndSettle();
      expect(owners.requests['me']?.length ?? 0, scenario == 'sucesso' ? 1 : 0);
      if (scenario == 'falha') {
        expect(
          find.textContaining('Não foi possível solicitar.'),
          findsOneWidget,
        );
      }
    });
  }

  testWidgets(
    'selecionar/desselecionar tags no formulário envia NewReview não vazia',
    (tester) async {
      final reviews = FakeReviewRepository();
      final vm = ReviewViewModel(
        place: place(),
        authRepository: FakeAuthRepository(uid: 'me'),
        userRepository: FakeUserRepository()..addUser('me', 'Eu'),
        reviewRepository: reviews,
        photoPicker: FakePhotoPicker(),
        compress: (b) async => b,
      )..setFood(4);
      await tester.pumpWidget(MaterialApp(home: ReviewView(viewModel: vm)));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.widgetWithText(FilterChip, 'vegano'),
        200,
      );
      await tester.ensureVisible(find.widgetWithText(FilterChip, 'vegano'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'vegano'));
      await tester.pump();
      expect(vm.tags, {'vegano'});
      await tester.tap(find.widgetWithText(FilterChip, 'integral'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilterChip, 'integral'));
      await tester.pump();
      expect(await vm.submit(), isTrue);
      expect(reviews.created.single.tags, ['vegano']);
      vm.dispose();
    },
  );

  testWidgets(
    'três autores mostram tag, contagem e comunidade no card e ficha',
    (tester) async {
      final users = FakeUserRepository()
        ..addUser('me', 'Eu')
        ..addUser('a', 'Ana');
      users.followingByUser['me'] = {'a'};
      final reviews = FakeReviewRepository()
        ..stored.addAll([
          for (final uid in ['a', 'b', 'c'])
            review(authorId: uid, tags: ['vegano']),
        ]);
      final app = await pumpApp(
        tester,
        users: users,
        reviews: reviews,
        places: [place()],
      );
      expect(find.text('vegano · 3 pessoas da comunidade'), findsOneWidget);
      app.router.go(Routes.placeDetail('p1'));
      await tester.pumpAndSettle();
      expect(find.text('vegano · 3 pessoas da comunidade'), findsOneWidget);
    },
  );
  testWidgets(
    'área de estabelecimentos mantém consultas em cache durante rebuild',
    (tester) async {
      final owners = _Owners()
        ..requests['me'] = [const OwnershipRequest('p1', 'pending')];
      final app = await pumpApp(tester, owners: owners, places: [place()]);
      app.router.go('/meus-estabelecimentos');
      await tester.pumpAndSettle();
      final reads = owners.ownerReads;
      app.auth.restoreSession('me');
      await tester.pumpAndSettle();
      expect(owners.requestReads, 1);
      expect(owners.ownerReads, reads);
      app.auth.restoreSession('other');
      await tester.pumpAndSettle();
      expect(find.text('Local p1'), findsNothing);
    },
  );
}
