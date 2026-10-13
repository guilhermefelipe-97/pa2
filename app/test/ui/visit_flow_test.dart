import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/feed.dart';
import 'package:naarea/domain/models/companion.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/domain/models/scores.dart';
import 'package:naarea/routing/routes.dart';
import 'package:naarea/ui/core/follow_events.dart';
import 'package:naarea/ui/feed/feed_view_model.dart';
import 'package:naarea/ui/feed/widgets/axis_scores.dart';
import 'package:naarea/ui/feed/widgets/trust_sources.dart';
import 'package:naarea/ui/feed/widgets/visit_tile.dart';
import 'package:naarea/ui/nearby/nearby_view_model.dart';
import 'package:naarea/ui/place/place_detail_view_model.dart';
import 'package:naarea/ui/profile/profile_view_model.dart';
import 'package:naarea/ui/visit/visit_view_model.dart';

import '../support/app_harness.dart';
import '../support/builders.dart';
import '../support/fakes.dart';
import '../support/geo_helpers.dart';

const _mangai = Place(
  id: 'mangai',
  name: 'Mangai',
  category: 'Restaurante',
  neighborhood: 'Tirol',
  city: 'Natal',
);

/// 12/10/2030 às 20h em Natal.
final _today = DateTime.utc(2030, 10, 12, 23);

PlaceDetailViewModel _detail({
  String? uid = 'me',
  FakeUserRepository? users,
  FakeReviewRepository? reviews,
  required FakeVisitRepository visits,
  required DateTime Function() clock,
}) => PlaceDetailViewModel(
  placeId: 'mangai',
  authRepository: FakeAuthRepository(uid: uid),
  userRepository: users ?? FakeUserRepository(),
  placeRepository: FakePlaceRepository([_mangai]),
  reviewRepository: reviews ?? FakeReviewRepository(),
  visitRepository: visits,
  followEvents: FollowEvents(),
  clock: clock,
);

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  group('item 1: o sheet não fecha durante o envio', () {
    testWidgets('toque fora, arrastar e voltar não fecham; ao concluir fecha', (
      tester,
    ) async {
      final visits = FakeVisitRepository()
        ..clock = (() => _today)
        ..createGate = Completer<void>();
      final app = await pumpApp(
        tester,
        places: [_mangai],
        visits: visits,
        clock: () => _today,
      );
      app.router.go(Routes.placeDetail('mangai'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('place-visit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('visit-confirm')));
      await tester.pump();

      final confirm = find.byKey(const Key('visit-confirm'));
      await tester.tapAt(const Offset(20, 20)); // barreira
      await tester.pump(const Duration(seconds: 1)); // spinner: sem settle
      expect(confirm, findsOneWidget);
      await tester.drag(
        find.byKey(const Key('visit-handle')),
        const Offset(0, 500),
      );
      await tester.pump(const Duration(seconds: 1)); // spinner: sem settle
      expect(confirm, findsOneWidget);
      await tester.binding.handlePopRoute(); // voltar do sistema
      await tester.pump(const Duration(seconds: 1)); // spinner: sem settle
      expect(confirm, findsOneWidget);

      visits.createGate!.complete();
      await tester.pumpAndSettle();
      expect(confirm, findsNothing);
      expect(find.text('Visita registrada'), findsOneWidget);
    });

    testWidgets('sem envio, arrastar para baixo fecha', (tester) async {
      final app = await pumpApp(
        tester,
        places: [_mangai],
        visits: FakeVisitRepository()..clock = () => _today,
        clock: () => _today,
      );
      app.router.go(Routes.placeDetail('mangai'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('place-visit')));
      await tester.pumpAndSettle();
      await tester.fling(
        find.byKey(const Key('visit-handle')),
        const Offset(0, 600),
        2000,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('visit-confirm')), findsNothing);
    });
  });

  group('item 3: corte comum entre avaliações e visitas', () {
    test(
      'feed: visita mais antiga que o corte das avaliações é descartada',
      () async {
        final reviews = FakeReviewRepository()
          // Lote cheio (2): o corte das avaliações é t(5).
          ..perBatchLimit = 2
          ..stored.addAll([
            review(
              authorId: 'ana',
              placeId: 'x',
              createdAt: DateTime.utc(2026, 9, 9),
            ),
            review(
              authorId: 'ana',
              placeId: 'x',
              createdAt: DateTime.utc(2026, 9, 5),
            ),
            review(
              authorId: 'ana',
              placeId: 'z',
              createdAt: DateTime.utc(2026, 9, 1),
            ),
          ]);
        final visits = FakeVisitRepository()
          ..stored.addAll([
            visit(
              authorId: 'ana',
              placeId: 'y',
              createdAt: DateTime.utc(2026, 9, 2),
            ),
            visit(
              authorId: 'ana',
              placeId: 'x',
              createdAt: DateTime.utc(2026, 9, 6),
            ),
          ]);
        final vm = FeedViewModel(
          authRepository: FakeAuthRepository(uid: 'me'),
          userRepository: FakeUserRepository()..followingByUser['me'] = {'ana'},
          reviewRepository: reviews,
          placeRepository: FakePlaceRepository(const []),
          visitRepository: visits,
          followEvents: FollowEvents(),
        );
        await vm.load();
        // O lote de avaliações pode estar incompleto antes de 05/09: a visita
        // de 02/09 em "y" não aparece sozinha (as avaliações dessa época não
        // vieram). Sem o corte comum, "y" viraria um card.
        expect(vm.items.map((i) => i.placeId), ['x']);
        expect(vm.items.single.trips, 3);
      },
    );

    test('Perto usa o mesmo corte', () async {
      final users = FakeUserRepository()..followingByUser['me'] = {'ana'};
      final reviews = FakeReviewRepository()
        ..perBatchLimit = 1
        ..stored.add(
          review(
            authorId: 'ana',
            placeId: 'p120',
            createdAt: DateTime.utc(2026, 9, 9),
          ),
        );
      final visits = FakeVisitRepository()
        ..stored.add(
          visit(
            authorId: 'ana',
            placeId: 'p80',
            createdAt: DateTime.utc(2026, 9, 1),
          ),
        );
      final vm = NearbyViewModel(
        locationService: FakeLocationService(
          position: pontaNegra,
          granted: true,
        ),
        placeRepository: FakePlaceRepository([
          placeNear('p80', 80, bearingDeg: 10),
          placeNear('p120', 120, bearingDeg: 100),
        ]),
        authRepository: FakeAuthRepository(uid: 'me'),
        userRepository: users,
        reviewRepository: reviews,
        visitRepository: visits,
      );
      await vm.start();
      expect(vm.items.firstWhere((i) => i.place.id == 'p80').friends, isEmpty);
      expect(vm.items.firstWhere((i) => i.place.id == 'p120').friends, ['ANA']);
    });
  });

  group('item 4: falha de visitas', () {
    test('Perto: falha nas visitas não fica em cache; a próxima carga tenta '
        'de novo', () async {
      final visits = FakeVisitRepository()
        ..fetchError = StateError('offline')
        ..stored.add(visit(authorId: 'ana', authorName: 'Ana', placeId: 'p80'));
      final vm = NearbyViewModel(
        locationService: FakeLocationService(
          position: pontaNegra,
          granted: true,
        ),
        placeRepository: FakePlaceRepository([
          placeNear('p80', 80, bearingDeg: 10),
        ]),
        authRepository: FakeAuthRepository(uid: 'me'),
        userRepository: FakeUserRepository()..followingByUser['me'] = {'ana'},
        reviewRepository: FakeReviewRepository(),
        visitRepository: visits,
      );
      await vm.start();
      expect(vm.items.single.friends, isEmpty);
      visits.fetchError = null;
      await vm.retry();
      expect(vm.items.single.friends, ['Ana']);
      expect(visits.fetchCalls, hasLength(2));
    });

    test('detalhe: carrega com as avaliações, sem erro, e mantém as visitas '
        'anteriores', () async {
      final users = FakeUserRepository()..followingByUser['me'] = {'ana'};
      final reviews = FakeReviewRepository()
        ..stored.add(review(authorId: 'ana', placeId: 'mangai'));
      final visits = FakeVisitRepository()
        ..stored.add(visit(id: 'v-ana', authorId: 'ana', placeId: 'mangai'));
      final vm = _detail(
        users: users,
        reviews: reviews,
        visits: visits,
        clock: () => _today,
      );
      await vm.load();
      expect(vm.visits.map((v) => v.id), ['v-ana']);
      visits.fetchError = StateError('offline');
      reviews.stored.add(
        review(id: 'r2', authorId: 'ana', placeId: 'mangai', createdAt: _today),
      );
      await vm.load();
      expect(vm.errorMessage, isNull);
      expect(vm.reviews.map((r) => r.id), contains('r2'));
      expect(vm.visits.map((v) => v.id), ['v-ana']);
    });
  });

  group('item 5: trava local e temporizadores', () {
    test('detalhe: depois do sucesso, trava local antes do load; uma releitura '
        'que falha não a apaga', () async {
      final visits = FakeVisitRepository();
      final vm = _detail(visits: visits, clock: () => _today);
      await vm.load();
      expect(vm.visitBlockedLabel, isNull);
      vm.markVisited();
      expect(
        vm.visitBlockedLabel,
        'Você registrou uma visita em 12/10 às 20h. '
        'De novo a partir de 13/10 às 8h.',
      );
      visits.lockError = StateError('offline');
      await vm.load();
      expect(vm.visitBlockedLabel, isNotNull);
    });

    test('detalhe: o temporizador libera o "Voltei aqui" na hora certa', () {
      fakeAsync((async) {
        final visits = FakeVisitRepository()..lock('me', 'mangai', _today);
        final vm = _detail(
          visits: visits,
          clock: () => _today.add(async.elapsed),
        );
        var notified = 0;
        vm.addListener(() => notified++);
        vm.load();
        async.flushMicrotasks();
        expect(vm.visitBlockedLabel, isNotNull);
        notified = 0;
        async.elapse(const Duration(hours: 11, minutes: 59));
        expect(vm.visitBlockedLabel, isNotNull);
        async.elapse(const Duration(minutes: 1));
        expect(vm.visitBlockedLabel, isNull);
        expect(notified, greaterThan(0));
        vm.dispose();
      });
    });

    test('sheet: o temporizador libera o Confirmar sem reabrir', () {
      fakeAsync((async) {
        final visits = FakeVisitRepository()..lock('toni', 'mangai', _today);
        final vm = VisitViewModel(
          place: _mangai,
          authRepository: FakeAuthRepository(uid: 'toni'),
          userRepository: FakeUserRepository()..addUser('toni', 'Toni'),
          visitRepository: visits,
          clock: () => _today.add(const Duration(hours: 11)).add(async.elapsed),
        );
        vm.checkLock();
        async.flushMicrotasks();
        expect(vm.isBlocked, isTrue);
        expect(vm.canSubmit, isFalse);
        async.elapse(const Duration(hours: 1));
        expect(vm.isBlocked, isFalse);
        expect(vm.canSubmit, isTrue);
        vm.dispose();
      });
    });

    test(
      'sem sessão: detalhe sem trava nem leitura; sheet não envia',
      () async {
        final visits = FakeVisitRepository()..lock('me', 'mangai', _today);
        final detail = _detail(uid: null, visits: visits, clock: () => _today);
        await detail.load();
        expect(detail.visitBlockedLabel, isNull);
        expect(visits.lockCalls, isEmpty);
        final sheet = VisitViewModel(
          place: _mangai,
          authRepository: FakeAuthRepository(uid: null),
          userRepository: FakeUserRepository(),
          visitRepository: visits,
          clock: () => _today,
        );
        await sheet.checkLock();
        expect(visits.lockCalls, isEmpty);
        expect(await sheet.submit(), isFalse);
        expect(sheet.errorMessage, VisitViewModel.errorText);
        expect(visits.created, isEmpty);
      },
    );
  });

  group('item 7: linha de fonte', () {
    final now = DateTime.utc(2026, 9, 28, 15); // 12h em Natal
    final night = DateTime.utc(2026, 9, 27, 22); // 19h de ontem
    final fiveDaysAgo = DateTime.utc(2026, 9, 23, 15);

    testWidgets('visita depois de avaliação: eixos com "(avaliou há 5 dias)"; '
        'contexto e tempo da visita', (tester) async {
      final item = groupActivitiesIntoFeed([
        review(
          authorId: 'ana',
          authorName: 'Ana',
          createdAt: fiveDaysAgo,
          scores: Scores(food: 5),
        ),
        visit(
          authorId: 'ana',
          authorName: 'Ana',
          createdAt: night,
          companion: Companion.amigos,
        ),
      ]).single;
      final s = item.sources.single;
      await tester.pumpWidget(
        _host(TrustSourceRow(source: s, now: now, following: true)),
      );
      expect(find.byType(AxisScores), findsOneWidget);
      expect(find.text('(avaliou há 5 dias)'), findsOneWidget);
      expect(
        find.text('voltou com amigos à noite · foi 2 vezes'),
        findsOneWidget,
      );
      expect(find.text('ontem'), findsOneWidget);
      expect(
        sourceSemanticsLabel(s, following: true, now: now),
        'Ana, você segue, comida 5, avaliou há 5 dias, voltou com amigos à '
        'noite, foi 2 vezes, ontem',
      );
    });

    testWidgets('só visitas: "voltou com amigos à noite", sem eixos', (
      tester,
    ) async {
      final item = groupActivitiesIntoFeed([
        visit(authorId: 'ana', authorName: 'Ana', createdAt: fiveDaysAgo),
        visit(
          authorId: 'ana',
          authorName: 'Ana',
          createdAt: night,
          companion: Companion.amigos,
        ),
      ]).single;
      final s = item.sources.single;
      await tester.pumpWidget(
        _host(TrustSourceRow(source: s, now: now, following: false)),
      );
      expect(find.byType(AxisScores), findsNothing);
      expect(
        find.text('voltou com amigos à noite · foi 2 vezes'),
        findsOneWidget,
      );
      expect(
        sourceSemanticsLabel(s, following: false, now: now),
        'Ana, voltou com amigos à noite, foi 2 vezes, ontem',
      );
    });

    test('uma única ida (visita): "foi aqui", não "voltou"', () {
      final s = groupActivitiesIntoFeed([
        visit(authorId: 'ana', authorName: 'Ana', createdAt: night),
      ]).single.sources.single;
      expect(visitPhrase(s), 'foi aqui à noite');
      expect(
        sourceSemanticsLabel(s, following: false, now: now),
        'Ana, foi aqui à noite, ontem',
      );
    });

    test('avaliação anterior com data: "avaliou em 20/09"', () {
      expect(
        reviewedAgoLabel(DateTime.utc(2026, 9, 20, 15), now),
        'avaliou em 20/09',
      );
      expect(reviewedAgoLabel(night, now), 'avaliou ontem');
    });
  });

  group('item 8: vocabulário do detalhe', () {
    test('idas próprias e de amigos: "4 idas suas e de 2 amigos"; contagem '
        'separa suas de amigos', () async {
      final users = FakeUserRepository()
        ..followingByUser['me'] = {'ana', 'bia'};
      final reviews = FakeReviewRepository()
        ..stored.addAll([
          review(authorId: 'me', placeId: 'mangai'),
          review(authorId: 'bia', placeId: 'mangai'),
        ]);
      final visits = FakeVisitRepository()
        ..stored.addAll([
          visit(authorId: 'me', placeId: 'mangai'),
          visit(authorId: 'ana', placeId: 'mangai'),
        ]);
      final vm = _detail(
        users: users,
        reviews: reviews,
        visits: visits,
        clock: () => _today,
      );
      await vm.load();
      expect(vm.recurrenceLabel, '4 idas suas e de 2 amigos');
      expect(vm.reviewCountLabel, '2 avaliações · 2 visitas');
    });

    test(
      'só de amigos: "visitas de amigos"; sem idas nunca fica vazio',
      () async {
        final users = FakeUserRepository()..followingByUser['me'] = {'ana'};
        final visits = FakeVisitRepository();
        final vm = _detail(users: users, visits: visits, clock: () => _today);
        await vm.load();
        expect(vm.reviewCountLabel, isNotEmpty);
        visits.stored.add(visit(authorId: 'ana', placeId: 'mangai'));
        await vm.load();
        expect(vm.reviewCountLabel, '1 visita de amigo');
      },
    );
  });

  group('item 10: VisitTile', () {
    testWidgets('a própria visita é "Você" e o toque é "Abrir seu perfil"', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          VisitTile(
            visit: visit(id: 'v1', authorId: 'me', authorName: 'Você'),
            now: _today,
            isOwn: true,
            onAuthorTap: () {},
          ),
        ),
      );
      expect(find.text('Você'), findsOneWidget);
      expect(find.bySemanticsLabel('Abrir seu perfil'), findsOneWidget);
      expect(find.bySemanticsLabel('Abrir perfil de Você'), findsNothing);
    });

    testWidgets('nome vazio vira "Alguém"', (tester) async {
      await tester.pumpWidget(
        _host(
          VisitTile(
            visit: visit(id: 'v2', authorId: 'x', authorName: '  '),
            now: _today,
            onAuthorTap: () {},
          ),
        ),
      );
      expect(find.text('Alguém'), findsOneWidget);
      expect(find.bySemanticsLabel('Abrir perfil de Alguém'), findsOneWidget);
    });
  });

  group('item 13: perfil', () {
    test('limites separados: 50 avaliações + 50 visitas', () async {
      final reviews = FakeReviewRepository()
        ..stored.addAll([
          for (var i = 0; i < 60; i++)
            review(
              authorId: 'ana',
              createdAt: _today.subtract(Duration(hours: i)),
            ),
        ]);
      final visits = FakeVisitRepository()
        ..stored.addAll([
          for (var i = 0; i < 60; i++)
            visit(
              authorId: 'ana',
              createdAt: _today.subtract(Duration(minutes: i)),
            ),
        ]);
      final vm = ProfileViewModel(
        uid: 'ana',
        authRepository: FakeAuthRepository(uid: 'me'),
        userRepository: FakeUserRepository()..addUser('ana', 'Ana'),
        reviewRepository: reviews,
        visitRepository: visits,
        followEvents: FollowEvents(),
      );
      await vm.load();
      expect(vm.reviews, hasLength(ProfileViewModel.maxReviews));
      expect(vm.activities, hasLength(100));
    });

    testWidgets('ProfileView com uma visita: item, texto e título', (
      tester,
    ) async {
      final users = FakeUserRepository()
        ..addUser('me', 'Eu')
        ..addUser('ana', 'Ana');
      final visits = FakeVisitRepository()
        ..stored.add(
          visit(
            id: 'v1',
            authorId: 'ana',
            authorName: 'Ana',
            placeId: 'mangai',
            placeName: 'Mangai',
            createdAt: _today.subtract(const Duration(hours: 1)),
            companion: Companion.casal,
          ),
        );
      final app = await pumpApp(
        tester,
        users: users,
        visits: visits,
        places: [_mangai],
        clock: () => _today,
      );
      app.router.push(Routes.person('ana'));
      await tester.pumpAndSettle();
      final tile = find.byKey(const ValueKey('profile-visit-v1'));
      expect(tile, findsOneWidget);
      expect(
        find.descendant(
          of: tile,
          matching: find.textContaining('Voltou aqui · '),
        ),
        findsOneWidget,
      );
      expect(find.text('Avaliações e visitas'), findsOneWidget);
    });
  });

  group('item 14: visita pela tela de bloqueio do F03', () {
    testWidgets('ao voltar, o detalhe mostra o VisitTile', (tester) async {
      final reviews = FakeReviewRepository()..clock = () => _today;
      final visits = FakeVisitRepository()..clock = () => _today;
      final app = await pumpApp(
        tester,
        reviews: reviews,
        visits: visits,
        places: [_mangai],
        clock: () => _today,
      );
      app.router.go(Routes.placeDetail('mangai'));
      await tester.pumpAndSettle();
      // Outro aparelho avaliou depois que o detalhe abriu.
      reviews.lock('me', 'mangai', _today);
      await tester.tap(find.byKey(const Key('place-review')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('review-register-visit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('visit-confirm')));
      await tester.pumpAndSettle();

      expect(find.byType(VisitTile), findsOneWidget);
      expect(find.text('Visita registrada'), findsOneWidget);
      final button = tester.widget<ButtonStyleButton>(
        find.byKey(const Key('place-visit')),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('item 15: VisitViewModel e o catálogo', () {
    const discovered = Place(
      id: 'osm-n123',
      name: 'Bar do Zé',
      category: 'Bar',
      neighborhood: '',
      city: '',
      lat: -23.55,
      lng: -46.63,
      inCatalog: false,
      discovered: true,
    );

    test('placeCreated false: invalida o local, sem markPersisted', () async {
      final places = FakePlaceRepository(const []);
      final visits = FakeVisitRepository()..placeCreated = false;
      final vm = VisitViewModel(
        place: discovered,
        authRepository: FakeAuthRepository(uid: 'toni'),
        userRepository: FakeUserRepository()..addUser('toni', 'Toni'),
        visitRepository: visits,
        placeRepository: places,
        clock: () => _today,
      );
      expect(await vm.submit(), isTrue);
      expect(places.invalidated, ['osm-n123']);
      expect(places.markedPersisted, isEmpty);
    });
  });
}
