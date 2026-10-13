import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/models/companion.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/domain/models/scores.dart';
import 'package:naarea/domain/visit_lock.dart';
import 'package:naarea/routing/routes.dart';
import 'package:naarea/ui/core/follow_events.dart';
import 'package:naarea/ui/feed/feed_view_model.dart';
import 'package:naarea/ui/feed/widgets/axis_scores.dart';
import 'package:naarea/ui/feed/widgets/visit_tile.dart';
import 'package:naarea/ui/profile/profile_view_model.dart';
import 'package:naarea/ui/review/review_view.dart';
import 'package:naarea/ui/visit/visit_view_model.dart';

import '../support/app_harness.dart';
import '../support/builders.dart';
import '../support/fakes.dart';

const _mangai = Place(
  id: 'mangai',
  name: 'Mangai',
  category: 'Restaurante',
  neighborhood: 'Tirol',
  city: 'Natal',
);

/// 12/10/2030 às 20h em Natal (longe do relógio real).
final _today = DateTime.utc(2030, 10, 12, 23);

const _blockedVisitText =
    'Você registrou uma visita em 12/10 às 20h. '
    'De novo a partir de 13/10 às 8h.';

Future<DateTime?> _never() => Completer<DateTime?>().future;

void main() {
  group('VisitViewModel', () {
    late FakeVisitRepository visits;
    late FakePlaceRepository places;
    late DateTime now;

    VisitViewModel make({Place place = _mangai, String? uid = 'toni'}) =>
        VisitViewModel(
          place: place,
          authRepository: FakeAuthRepository(uid: uid),
          userRepository: FakeUserRepository()..addUser('toni', 'Toni'),
          visitRepository: visits,
          placeRepository: places,
          clock: () => now,
        );

    setUp(() {
      now = _today;
      visits = FakeVisitRepository()..clock = () => now;
      places = FakePlaceRepository([_mangai]);
    });

    test('registra com o nome do perfil e a companhia (opcional)', () async {
      final vm = make();
      await vm.checkLock();
      expect(vm.canSubmit, isTrue);
      vm.toggleCompanion(Companion.amigos);
      vm.toggleCompanion(Companion.casal);
      expect(await vm.submit(), isTrue);
      final v = visits.created.single;
      expect(v.authorId, 'toni');
      expect(v.authorName, 'Toni');
      expect(v.placeId, 'mangai');
      expect(v.placeName, 'Mangai');
      expect(v.companion, Companion.casal);
      expect(visits.locks['toni/mangai'], _today);
    });

    test('tocar na companhia selecionada desmarca (sem companhia)', () async {
      final vm = make();
      vm.toggleCompanion(Companion.amigos);
      vm.toggleCompanion(Companion.amigos);
      expect(vm.companion, isNull);
      expect(await vm.submit(), isTrue);
      expect(visits.created.single.companion, isNull);
    });

    test('visita há 3 h: bloqueado com a mensagem, sem envio', () async {
      visits.lock('toni', 'mangai', _today);
      now = _today.add(const Duration(hours: 3));
      final vm = make();
      await vm.checkLock();
      expect(vm.isBlocked, isTrue);
      expect(vm.blockedMessage, _blockedVisitText);
      expect(vm.canSubmit, isFalse);
      expect(await vm.submit(), isFalse);
      expect(visits.created, isEmpty);
    });

    test('após 12 h: liberado de novo', () async {
      visits.lock('toni', 'mangai', _today);
      now = _today.add(const Duration(hours: 12));
      final vm = make();
      await vm.checkLock();
      expect(vm.isBlocked, isFalse);
      expect(await vm.submit(), isTrue);
    });

    test('falha no envio: "Não foi possível registrar"', () async {
      visits.createError = StateError('offline');
      final vm = make();
      await vm.checkLock();
      expect(await vm.submit(), isFalse);
      expect(vm.errorMessage, VisitViewModel.errorText);
      expect(vm.errorMessage, 'Não foi possível registrar');
      expect(vm.canSubmit, isTrue);
    });

    test('corrida: outro aparelho registrou antes; Rules negam e a tela '
        'explica o bloqueio', () async {
      final vm = make();
      await vm.checkLock();
      visits.lock('toni', 'mangai', _today);
      expect(await vm.submit(), isFalse);
      expect(vm.isBlocked, isTrue);
      expect(vm.errorMessage, isNull);
      expect(vm.blockedMessage, _blockedVisitText);
    });

    test('leitura da trava pendurada: segue liberado após o timeout', () {
      fakeAsync((async) {
        visits.pendingLock = _never();
        final vm = make();
        vm.checkLock();
        async.flushMicrotasks();
        expect(vm.isCheckingLock, isTrue);
        expect(vm.canSubmit, isFalse);
        async.elapse(visitLockTimeout);
        expect(vm.isCheckingLock, isFalse);
        expect(vm.canSubmit, isTrue);
      });
    });

    test('local descoberto (Photon) vai junto como newPlace', () async {
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
      final vm = make(place: discovered);
      expect(await vm.submit(), isTrue);
      expect(visits.createdNewPlaces.single, discovered);
      expect(places.markedPersisted, ['osm-n123']);
    });
  });

  group('detalhe: "Voltei aqui"', () {
    testWidgets('registra pelo sheet, avisa, mostra a visita sem nota e '
        'desabilita o botão com o horário', (tester) async {
      final visits = FakeVisitRepository()..clock = () => _today;
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
      expect(find.text('Com quem você foi? (opcional)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('visit-companion-amigos')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('visit-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('Visita registrada'), findsOneWidget);
      expect(visits.created.single.authorName, 'Eu');
      expect(visits.created.single.companion, Companion.amigos);
      // A visita aparece no detalhe, como "Você", sem notas.
      expect(find.byType(VisitTile), findsOneWidget);
      expect(find.textContaining('$visitTileLabel · Noite · Amigos'), findsOne);
      expect(find.text('🍽️'), findsNothing);
      // Antes de 12 h: botão desabilitado, com o horário.
      final button = tester.widget<ButtonStyleButton>(
        find.byKey(const Key('place-visit')),
      );
      expect(button.onPressed, isNull);
      expect(find.text(_blockedVisitText), findsOneWidget);
    });

    testWidgets('falha no envio: mensagem no sheet, que continua aberto', (
      tester,
    ) async {
      final visits = FakeVisitRepository()
        ..clock = (() => _today)
        ..createError = StateError('offline');
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
      await tester.pumpAndSettle();
      expect(find.text('Não foi possível registrar'), findsOneWidget);
      expect(find.byKey(const Key('visit-confirm')), findsOneWidget);
      expect(find.text('Visita registrada'), findsNothing);
    });

    testWidgets('3 amigos, 5 idas: "🔁 5 idas de 3 amigos" acima das médias '
        'e visitas como itens sem nota', (tester) async {
      final users = FakeUserRepository()
        ..addUser('me', 'Eu')
        ..followingByUser['me'] = {'a', 'b', 'c'};
      final at = _today.subtract(const Duration(days: 1));
      final reviews = FakeReviewRepository()
        ..stored.addAll([
          review(authorId: 'a', authorName: 'Ana', placeId: 'mangai'),
          review(authorId: 'b', authorName: 'Bia', placeId: 'mangai'),
        ]);
      final visits = FakeVisitRepository()
        ..stored.addAll([
          visit(
            authorId: 'a',
            authorName: 'Ana',
            placeId: 'mangai',
            createdAt: at,
          ),
          visit(
            authorId: 'a',
            authorName: 'Ana',
            placeId: 'mangai',
            createdAt: at.add(const Duration(hours: 13)),
          ),
          visit(
            id: 'vc1',
            authorId: 'c',
            authorName: 'Caio',
            placeId: 'mangai',
            createdAt: at,
          ),
        ]);
      final app = await pumpApp(
        tester,
        users: users,
        reviews: reviews,
        visits: visits,
        places: [_mangai],
        clock: () => _today,
      );
      app.router.go(Routes.placeDetail('mangai'));
      await tester.pumpAndSettle();
      // O selo mostra o ícone 🔁 (decorativo) + o texto.
      final badge = find.byKey(const Key('place-recurrence'));
      expect(
        find.descendant(of: badge, matching: find.text('5 idas de 3 amigos')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: badge, matching: find.text('🔁')),
        findsOneWidget,
      );
      // O ícone fica fora da semântica: o leitor de tela fala só o texto.
      expect(find.bySemanticsLabel('5 idas de 3 amigos'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('🔁')), findsNothing);
      final averages = find.text('Média dos amigos');
      expect(
        tester.getTopLeft(badge).dy,
        lessThan(tester.getTopLeft(averages).dy),
      );
      expect(
        find.text('2 avaliações de amigos · 3 visitas de amigos'),
        findsOneWidget,
      );
      final caio = find.byKey(const ValueKey('visit-tile-vc1'));
      await tester.scrollUntilVisible(
        caio,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.descendant(of: caio, matching: find.byType(AxisScores)),
        findsNothing,
      );
      expect(find.byType(VisitTile), findsWidgets);
    });

    testWidgets('só visitas de amigos: sem médias, com a lista de visitas', (
      tester,
    ) async {
      final users = FakeUserRepository()
        ..addUser('me', 'Eu')
        ..followingByUser['me'] = {'a'};
      final visits = FakeVisitRepository()
        ..stored.add(
          visit(authorId: 'a', authorName: 'Ana', placeId: 'mangai'),
        );
      final app = await pumpApp(
        tester,
        users: users,
        visits: visits,
        places: [_mangai],
        clock: () => _today,
      );
      app.router.go(Routes.placeDetail('mangai'));
      await tester.pumpAndSettle();
      expect(find.text('Ana foi aqui'), findsOneWidget);
      expect(find.text('Média dos amigos'), findsNothing);
      expect(find.text('1 visita de amigo'), findsOneWidget);
      expect(find.byType(VisitTile), findsOneWidget);
      // Ninguém voltou (1 ida): sem selo.
      expect(find.text('🔁'), findsNothing);
    });
  });

  group('bloqueio do F03 oferece "Registrar visita"', () {
    testWidgets('abre o mesmo fluxo e registra', (tester) async {
      final reviews = FakeReviewRepository()..lock('me', 'mangai', _today);
      final visits = FakeVisitRepository()
        ..clock = () => _today.add(const Duration(hours: 1));
      final app = await pumpApp(
        tester,
        reviews: reviews,
        visits: visits,
        places: [_mangai],
        clock: () => _today.add(const Duration(hours: 1)),
      );
      app.router.go(Routes.placeDetail('mangai'));
      await tester.pumpAndSettle();
      app.router.push(Routes.reviewFor('mangai'), extra: _mangai);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('review-blocked')), findsOneWidget);

      await tester.tap(find.byKey(const Key('review-register-visit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('visit-confirm')));
      await tester.pumpAndSettle();

      expect(visits.created, hasLength(1));
      expect(reviews.created, isEmpty);
      expect(find.byType(ReviewView), findsNothing);
      expect(find.text('Visita registrada'), findsOneWidget);
    });

    testWidgets('visita também travada: o sheet explica e o Confirmar fica '
        'desligado', (tester) async {
      final later = _today.add(const Duration(hours: 1));
      final reviews = FakeReviewRepository()..lock('me', 'mangai', _today);
      final visits = FakeVisitRepository()
        ..clock = (() => later)
        ..lock('me', 'mangai', _today);
      final app = await pumpApp(
        tester,
        reviews: reviews,
        visits: visits,
        places: [_mangai],
        clock: () => later,
      );
      app.router.go(Routes.reviewFor('mangai'), extra: _mangai);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('review-register-visit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('visit-blocked')), findsOneWidget);
      expect(find.text(_blockedVisitText), findsOneWidget);
      final confirm = tester.widget<ButtonStyleButton>(
        find.byKey(const Key('visit-confirm')),
      );
      expect(confirm.onPressed, isNull);
      expect(visits.created, isEmpty);
      // Sem envio, o toque fora fecha (e o temporizador de liberação vai
      // junto com o ViewModel).
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('visit-confirm')), findsNothing);
    });
  });

  group('feed', () {
    testWidgets('Ana só visitou X uma vez: "foi aqui" com o contexto, sem '
        'eixos', (tester) async {
      final users = FakeUserRepository()
        ..addUser('me', 'Eu')
        ..followingByUser['me'] = {'ana'};
      final visits = FakeVisitRepository()
        ..stored.add(
          visit(
            authorId: 'ana',
            authorName: 'Ana',
            placeId: 'mangai',
            createdAt: _today.subtract(const Duration(hours: 2)),
          ),
        );
      await pumpApp(
        tester,
        users: users,
        visits: visits,
        places: [_mangai],
        clock: () => _today,
      );
      await tester.pumpAndSettle();
      expect(find.text('Mangai'), findsOneWidget);
      final row = find.byKey(const ValueKey('trust-source-ana'));
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text('foi aqui à noite')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.byType(AxisScores)),
        findsNothing,
      );
      // O feed usa o relógio real: o tempo relativo varia.
      expect(
        tester.getSemantics(row).label,
        startsWith('Ana, você segue, foi aqui à noite, '),
      );
    });

    testWidgets('aceite: Toni avaliou há 5 dias, volta hoje e registra; quem '
        'o segue vê "🔁 Toni voltou 2 vezes"', (tester) async {
      final users = FakeUserRepository()
        ..addUser('me', 'Bianca')
        ..addUser('toni', 'Toni')
        ..followingByUser['me'] = {'toni'};
      final reviews = FakeReviewRepository()
        ..stored.add(
          review(
            authorId: 'toni',
            authorName: 'Toni',
            placeId: 'mangai',
            placeName: 'Mangai',
            createdAt: _today.subtract(const Duration(days: 5)),
            scores: Scores(food: 5, ambience: 4, service: 5),
          ),
        );
      final visits = FakeVisitRepository()..clock = () => _today;
      // Toni, no aparelho dele, toca "Voltei aqui".
      final toni = VisitViewModel(
        place: _mangai,
        authRepository: FakeAuthRepository(uid: 'toni'),
        userRepository: users,
        visitRepository: visits,
        clock: () => _today,
      );
      await toni.checkLock();
      expect(await toni.submit(), isTrue);

      await pumpApp(
        tester,
        users: users,
        reviews: reviews,
        visits: visits,
        places: [_mangai],
        clock: () => _today.add(const Duration(minutes: 5)),
      );
      await tester.pumpAndSettle();
      final badge = find.byKey(const Key('trust-recurrence'));
      expect(
        find.descendant(of: badge, matching: find.text('Toni voltou 2 vezes')),
        findsOneWidget,
      );
      expect(find.descendant(of: badge, matching: find.text('🔁')), findsOne);
      final row = find.byKey(const ValueKey('trust-source-toni'));
      // Eixos da avaliação dele e "foi 2 vezes".
      expect(
        find.descendant(of: row, matching: find.textContaining('foi 2 vezes')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.byType(AxisScores)),
        findsOneWidget,
      );
    });

    testWidgets('aceite: visita há 2 h, tenta de novo: vê até quando está '
        'bloqueado', (tester) async {
      final visits = FakeVisitRepository()
        ..clock = (() => _today.add(const Duration(hours: 2)))
        ..lock('me', 'mangai', _today);
      final app = await pumpApp(
        tester,
        visits: visits,
        places: [_mangai],
        clock: () => _today.add(const Duration(hours: 2)),
      );
      app.router.go(Routes.placeDetail('mangai'));
      await tester.pumpAndSettle();
      expect(find.text(_blockedVisitText), findsOneWidget);
      final button = tester.widget<ButtonStyleButton>(
        find.byKey(const Key('place-visit')),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('FeedViewModel', () {
    FeedViewModel make(FakeVisitRepository visits, FakeReviewRepository r) =>
        FeedViewModel(
          authRepository: FakeAuthRepository(uid: 'me'),
          userRepository: FakeUserRepository()..followingByUser['me'] = {'ana'},
          reviewRepository: r,
          placeRepository: FakePlaceRepository([_mangai]),
          visitRepository: visits,
          followEvents: FollowEvents(),
        );

    test(
      'visitas dos seguidos entram nos cards (mesmo lote de autores)',
      () async {
        final visits = FakeVisitRepository()
          ..stored.addAll([
            visit(authorId: 'ana', placeId: 'mangai'),
            visit(authorId: 'zé', placeId: 'outro'),
          ]);
        final vm = make(visits, FakeReviewRepository());
        await vm.load();
        expect(vm.items.single.placeName, 'Mangai');
        expect(vm.items.single.visits, hasLength(1));
        expect(visits.fetchCalls.single, ['ana']);
      },
    );

    test('falha só das visitas não derruba o feed', () async {
      final reviews = FakeReviewRepository()
        ..stored.add(review(authorId: 'ana', placeId: 'mangai'));
      final vm = make(
        FakeVisitRepository()..fetchError = StateError('offline'),
        reviews,
      );
      await vm.load();
      expect(vm.errorMessage, isNull);
      expect(vm.items.single.reviews, hasLength(1));
    });
  });

  group('perfil', () {
    test('avaliações e visitas juntas, mais recentes primeiro', () async {
      final reviews = FakeReviewRepository()
        ..stored.add(
          review(
            id: 'r1',
            authorId: 'ana',
            createdAt: DateTime.utc(2030, 1, 1),
          ),
        );
      final visits = FakeVisitRepository()
        ..stored.add(
          visit(id: 'v1', authorId: 'ana', createdAt: DateTime.utc(2030, 1, 2)),
        );
      final vm = ProfileViewModel(
        uid: 'ana',
        authRepository: FakeAuthRepository(uid: 'me'),
        userRepository: FakeUserRepository()..addUser('ana', 'Ana'),
        reviewRepository: reviews,
        visitRepository: visits,
        followEvents: FollowEvents(),
      );
      await vm.load();
      expect(vm.activities.map((a) => a.id), ['v1', 'r1']);
      expect(vm.reviews.map((r) => r.id), ['r1']);
      expect(visits.fetchCalls.single, ['ana']);
    });

    test('falha só das visitas: perfil com as avaliações', () async {
      final reviews = FakeReviewRepository()
        ..stored.add(review(id: 'r1', authorId: 'ana'));
      final vm = ProfileViewModel(
        uid: 'ana',
        authRepository: FakeAuthRepository(uid: 'me'),
        userRepository: FakeUserRepository()..addUser('ana', 'Ana'),
        reviewRepository: reviews,
        visitRepository: FakeVisitRepository()..fetchError = StateError('x'),
        followEvents: FollowEvents(),
      );
      await vm.load();
      expect(vm.state, ProfileState.ready);
      expect(vm.activities.map((a) => a.id), ['r1']);
    });
  });
}
