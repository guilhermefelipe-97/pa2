import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/domain/review_lock.dart';
import 'package:naarea/routing/routes.dart';
import 'package:naarea/ui/core/follow_events.dart';
import 'package:naarea/ui/place/place_detail_view.dart';
import 'package:naarea/ui/place/place_detail_view_model.dart';
import 'package:naarea/ui/review/review_view.dart';
import 'package:naarea/ui/review/review_view_model.dart';

import '../support/app_harness.dart';
import '../support/fakes.dart';

const _mangai = Place(
  id: 'mangai',
  name: 'Mangai',
  category: 'Restaurante',
  neighborhood: 'Tirol',
  city: 'Natal',
);

/// 12/10/2030 às 20h em Natal: longe do relógio real, para nenhum teste
/// passar por acaso com `DateTime.now()`.
final _today = DateTime.utc(2030, 10, 12, 23);

const _blockedText =
    'Você avaliou este lugar em 12/10. '
    'Pode avaliar de novo a partir de 11/11 às 20h.';
const _againText = 'Pode avaliar de novo a partir de 11/11 às 20h';

/// Futuro que nunca completa (leitura da trava pendurada).
Future<DateTime?> _never() => Completer<DateTime?>().future;

void main() {
  group('ReviewViewModel: trava do F03', () {
    late FakeReviewRepository reviews;
    late DateTime now;

    ReviewViewModel make({String? uid = 'toni'}) => ReviewViewModel(
      place: _mangai,
      authRepository: FakeAuthRepository(uid: uid),
      userRepository: FakeUserRepository()..addUser('toni', 'Toni'),
      reviewRepository: reviews,
      photoPicker: FakePhotoPicker(),
      compress: (b) async => b,
      clock: () => now,
    );

    setUp(() {
      now = _today;
      reviews = FakeReviewRepository()..clock = () => now;
    });

    test(
      'sem trava (1ª ou só avaliação legada): formulário liberado',
      () async {
        final vm = make();
        await vm.checkLock();
        expect(reviews.lockCalls, ['toni/mangai']);
        expect(vm.isBlocked, isFalse);
        vm.setFood(4);
        expect(vm.canSubmit, isTrue);
      },
    );

    test('avaliou há 10 dias: bloqueado com a mensagem e sem envio', () async {
      reviews.lock('toni', 'mangai', _today.subtract(const Duration(days: 10)));
      final vm = make();
      final checking = vm.checkLock();
      expect(vm.isCheckingLock, isTrue);
      expect(vm.canSubmit, isFalse);
      await checking;
      expect(vm.isCheckingLock, isFalse);
      expect(vm.isBlocked, isTrue);
      expect(
        vm.blockedMessage,
        'Você avaliou este lugar em 02/10. '
        'Pode avaliar de novo a partir de 01/11 às 20h.',
      );
      vm.setFood(4);
      expect(vm.canSubmit, isFalse);
      expect(await vm.submit(), isFalse);
      expect(reviews.created, isEmpty);
    });

    test('avaliou há 31 dias: liberado e a trava é renovada', () async {
      reviews.lock('toni', 'mangai', _today.subtract(const Duration(days: 31)));
      final vm = make();
      await vm.checkLock();
      expect(vm.isBlocked, isFalse);
      vm.setFood(4);
      expect(await vm.submit(), isTrue);
      expect(reviews.locks['toni/mangai'], _today);
    });

    test(
      'falha ao ler a trava: abre o formulário (as Rules decidem)',
      () async {
        reviews.lockError = Exception('offline');
        final vm = make();
        await vm.checkLock();
        expect(vm.isBlocked, isFalse);
        vm.setFood(4);
        expect(vm.canSubmit, isTrue);
      },
    );

    test('leitura pendurada: em 5 s desiste e abre o formulário', () {
      fakeAsync((async) {
        reviews.pendingLock = _never();
        final vm = make();
        var done = false;
        vm.checkLock().then((_) => done = true);
        async.elapse(reviewLockTimeout - const Duration(milliseconds: 1));
        expect(vm.isCheckingLock, isTrue);
        expect(done, isFalse);
        async.elapse(const Duration(milliseconds: 1));
        expect(done, isTrue);
        expect(vm.isCheckingLock, isFalse);
        expect(vm.isBlocked, isFalse);
      });
    });

    test(
      'corrida: a trava nasce entre abrir e enviar → tela de bloqueio com as '
      'datas, não erro genérico',
      () async {
        final vm = make();
        await vm.checkLock();
        reviews.lock('toni', 'mangai', _today); // outro envio passou antes
        vm.setFood(4);
        expect(await vm.submit(), isFalse);
        expect(vm.isBlocked, isTrue);
        expect(vm.errorMessage, isNull);
        expect(vm.blockedMessage, _blockedText);
        expect(reviews.created, isEmpty);
      },
    );

    test('falha que não é a trava: "Não foi possível salvar"', () async {
      final vm = make();
      await vm.checkLock();
      reviews.createError = Exception('unavailable');
      vm.setFood(4);
      expect(await vm.submit(), isFalse);
      expect(vm.isBlocked, isFalse);
      expect(vm.errorMessage, 'Não foi possível salvar');
    });

    test('sem sessão não consulta', () async {
      final vm = make(uid: null);
      await vm.checkLock();
      expect(reviews.lockCalls, isEmpty);
    });
  });

  group('PlaceDetailViewModel: trava do F03', () {
    late FakeReviewRepository reviews;
    late FakeAuthRepository auth;

    PlaceDetailViewModel make(DateTime Function() clock) =>
        PlaceDetailViewModel(
          placeId: 'mangai',
          authRepository: auth,
          userRepository: FakeUserRepository(),
          placeRepository: FakePlaceRepository([_mangai]),
          reviewRepository: reviews,
          followEvents: FollowEvents(),
          clock: clock,
        );

    setUp(() {
      reviews = FakeReviewRepository();
      auth = FakeAuthRepository(uid: 'toni');
    });

    test('bloqueado: rótulo com data e hora da liberação', () async {
      reviews.lock('toni', 'mangai', _today);
      final vm = make(() => _today.add(const Duration(days: 1)));
      await vm.load();
      expect(vm.reviewBlockedSince, _today);
      expect(vm.reviewAgainLabel, _againText);
      vm.dispose();
    });

    test('depois de 30 dias, sem trava ou com erro: sem rótulo', () async {
      reviews.lock('toni', 'mangai', _today);
      final later = make(() => _today.add(const Duration(days: 30)));
      await later.load();
      expect(later.reviewAgainLabel, isNull);

      reviews.locks.clear();
      final none = make(() => _today);
      await none.load();
      expect(none.reviewAgainLabel, isNull);

      reviews
        ..lock('toni', 'mangai', _today)
        ..lockError = Exception('offline');
      final failing = make(() => _today);
      await failing.load();
      expect(failing.reviewAgainLabel, isNull);
      expect(failing.errorMessage, isNull);
    });

    test('os dados não esperam a trava; ela chega depois e atualiza', () {
      fakeAsync((async) {
        final lock = Completer<DateTime?>();
        reviews.pendingLock = lock.future;
        final vm = make(() => _today);
        var notifications = 0;
        vm.addListener(() => notifications++);
        vm.load();
        async.flushMicrotasks();
        expect(vm.isLoading, isFalse);
        expect(vm.place, isNotNull);
        expect(vm.reviewsKnown, isTrue);
        expect(vm.reviewAgainLabel, isNull);
        final before = notifications;
        lock.complete(_today);
        async.flushMicrotasks();
        expect(vm.reviewAgainLabel, _againText);
        expect(notifications, greaterThan(before));
        vm.dispose();
      });
    });

    test('leitura pendurada: em 5 s segue sem trava', () {
      fakeAsync((async) {
        reviews.pendingLock = _never();
        final vm = make(() => _today);
        var done = false;
        vm.load().then((_) => done = true);
        async.flushMicrotasks();
        expect(vm.reviewsKnown, isTrue);
        async.elapse(reviewLockTimeout);
        expect(done, isTrue);
        expect(vm.reviewAgainLabel, isNull);
        vm.dispose();
      });
    });

    test('na hora da liberação o CTA volta sozinho (Timer)', () {
      fakeAsync((async) {
        final start = _today.add(const Duration(days: 29, hours: 23));
        DateTime clock() => start.add(async.elapsed);
        reviews.lock('toni', 'mangai', _today);
        final vm = make(clock);
        var notifications = 0;
        vm.addListener(() => notifications++);
        vm.load();
        async.flushMicrotasks();
        expect(vm.reviewAgainLabel, _againText);
        final before = notifications;
        async.elapse(const Duration(minutes: 59, seconds: 59));
        expect(notifications, before);
        async.elapse(const Duration(seconds: 1));
        expect(notifications, before + 1);
        expect(vm.reviewAgainLabel, isNull);
        expect(async.pendingTimers, isEmpty);
        vm.dispose();
      });
    });

    test('dispose cancela o Timer da liberação', () {
      fakeAsync((async) {
        reviews.lock('toni', 'mangai', _today);
        final vm = make(() => _today.add(async.elapsed));
        vm.load();
        async.flushMicrotasks();
        expect(async.pendingTimers, hasLength(1));
        vm.dispose();
        expect(async.pendingTimers, isEmpty);
      });
    });

    test(
      'sessão encerrada: a trava some (não fica a de outra conta)',
      () async {
        reviews.lock('toni', 'mangai', _today);
        final vm = make(() => _today);
        await vm.load();
        expect(vm.reviewAgainLabel, isNotNull);
        await auth.signOut();
        await vm.load();
        expect(vm.reviewAgainLabel, isNull);
        vm.dispose();
      },
    );

    test(
      'recarga em que a leitura da trava falha não mantém a trava velha',
      () async {
        reviews.lock('toni', 'mangai', _today);
        final vm = make(() => _today);
        await vm.load();
        expect(vm.reviewAgainLabel, isNotNull);
        reviews.lockError = Exception('offline');
        await vm.load();
        expect(vm.reviewAgainLabel, isNull);
        vm.dispose();
      },
    );
  });

  group('telas (F03)', () {
    ReviewViewModel formVm(FakeReviewRepository reviews, DateTime now) =>
        ReviewViewModel(
          place: _mangai,
          authRepository: FakeAuthRepository(uid: 'toni'),
          userRepository: FakeUserRepository()..addUser('toni', 'Toni'),
          reviewRepository: reviews,
          photoPicker: FakePhotoPicker(),
          compress: (b) async => b,
          clock: () => now,
        );

    Finder submitScrollable() => find
        .descendant(
          of: find.byType(ReviewView),
          matching: find.byType(Scrollable),
        )
        .first;

    testWidgets('formulário bloqueado: mensagem com datas, sem notas nem '
        'outras ações', (tester) async {
      final reviews = FakeReviewRepository()..lock('toni', 'mangai', _today);
      final vm = formVm(reviews, _today.add(const Duration(hours: 1)));
      await tester.pumpWidget(MaterialApp(home: ReviewView(viewModel: vm)));
      expect(find.byKey(const Key('review-lock-checking')), findsOneWidget);
      await tester.pump();
      expect(find.text(_blockedText), findsOneWidget);
      expect(find.byKey(const Key('axis-food-1')), findsNothing);
      expect(find.byKey(const Key('review-submit')), findsNothing);
      expect(find.byKey(const Key('review-register-visit')), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('corrida pela tela: Enviar negado vira a tela de bloqueio', (
      tester,
    ) async {
      final reviews = FakeReviewRepository()..clock = () => _today;
      final vm = formVm(reviews, _today);
      await tester.pumpWidget(MaterialApp(home: ReviewView(viewModel: vm)));
      await tester.pump();
      await tester.tap(find.byKey(const Key('axis-food-4')));
      await tester.pump();
      // Outro aparelho avaliou enquanto o formulário estava aberto.
      reviews.lock('toni', 'mangai', _today);
      await tester.scrollUntilVisible(
        find.byKey(const Key('review-submit')),
        200,
        scrollable: submitScrollable(),
      );
      await tester.tap(find.byKey(const Key('review-submit')));
      await tester.pumpAndSettle();
      expect(find.text(_blockedText), findsOneWidget);
      expect(find.text('Não foi possível salvar'), findsNothing);
      expect(find.byKey(const Key('axis-food-1')), findsNothing);
      expect(reviews.created, isEmpty);
    });

    testWidgets('detalhe sem avaliações lidas, mas com trava ativa: título '
        '"Você já avaliou" e texto no lugar do botão', (tester) async {
      final reviews = FakeReviewRepository()..lock('me', 'mangai', _today);
      final app = await pumpApp(
        tester,
        reviews: reviews,
        places: [_mangai],
        clock: () => _today.add(const Duration(hours: 2)),
      );
      app.router.go(Routes.placeDetail('mangai'));
      await tester.pumpAndSettle();
      expect(reviews.stored, isEmpty);
      expect(find.text('Você já avaliou este lugar'), findsOneWidget);
      expect(find.text('Nenhum amigo avaliou ainda'), findsNothing);
      expect(find.byKey(const Key('place-review-locked')), findsOneWidget);
      expect(find.text(_againText), findsOneWidget);
      expect(find.byKey(const Key('place-review')), findsNothing);
    });

    testWidgets(
      'trava de 31 dias antes do relógio: pela rota, o formulário aparece',
      (tester) async {
        final reviews = FakeReviewRepository()
          ..clock = (() => _today)
          ..lock('me', 'mangai', _today.subtract(const Duration(days: 31)));
        final app = await pumpApp(
          tester,
          reviews: reviews,
          places: [_mangai],
          clock: () => _today,
        );
        app.router.go(Routes.placeDetail('mangai'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('place-review-locked')), findsNothing);
        await tester.tap(find.byKey(const Key('place-review')));
        await tester.pumpAndSettle();
        expect(find.byType(ReviewView), findsOneWidget);
        expect(find.byKey(const Key('axis-food-1')), findsOneWidget);
        expect(find.byKey(const Key('review-blocked')), findsNothing);
      },
    );

    testWidgets(
      'Toni avalia o Mangai hoje e tenta de novo: vê a data de liberação e '
      'nenhum formulário',
      (tester) async {
        final users = FakeUserRepository()..addUser('me', 'Toni');
        final reviews = FakeReviewRepository()..clock = () => _today;
        final app = await pumpApp(
          tester,
          users: users,
          reviews: reviews,
          places: [_mangai],
          clock: () => _today,
        );
        app.router.go(Routes.placeDetail('mangai'));
        await tester.pumpAndSettle();

        // 1ª avaliação pelo app.
        await tester.tap(find.byKey(const Key('place-review')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('axis-food-4')));
        await tester.pump();
        await tester.scrollUntilVisible(
          find.byKey(const Key('review-submit')),
          200,
          scrollable: submitScrollable(),
        );
        await tester.tap(find.byKey(const Key('review-submit')));
        await tester.pumpAndSettle();
        expect(reviews.created, hasLength(1));

        // De volta ao detalhe: o CTA "Avaliar de novo" vira texto.
        expect(find.byType(PlaceDetailView), findsOneWidget);
        expect(find.byKey(const Key('place-review')), findsNothing);
        expect(find.text(_againText), findsOneWidget);

        // Mesmo abrindo a avaliação direto, não há formulário de notas.
        app.router.push(Routes.reviewFor('mangai'), extra: _mangai);
        await tester.pumpAndSettle();
        expect(find.byType(ReviewView), findsOneWidget);
        expect(find.text(_blockedText), findsOneWidget);
        expect(find.byKey(const Key('axis-food-1')), findsNothing);
        expect(reviews.created, hasLength(1));
      },
    );
  });
}
