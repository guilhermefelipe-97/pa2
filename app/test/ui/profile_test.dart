import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:naarea/domain/models/scores.dart';
import 'package:naarea/routing/routes.dart';
import 'package:naarea/ui/core/follow_events.dart';
import 'package:naarea/ui/profile/profile_view.dart';
import 'package:naarea/ui/profile/profile_view_model.dart';

import '../support/builders.dart';
import '../support/fakes.dart';

final _now = DateTime.utc(2026, 9, 28, 15);

void main() {
  late FakeUserRepository users;
  late FakeReviewRepository reviews;
  late FollowEvents events;

  setUp(() {
    users = FakeUserRepository()
      ..addUser('me', 'Bianca')
      ..addUser('ana', 'Ana')
      ..followingByUser['me'] = {'ana'};
    reviews = FakeReviewRepository()
      ..stored.addAll([
        review(
          id: 'old',
          authorId: 'ana',
          authorName: 'Ana',
          placeId: 'camaroes',
          placeName: 'Camarões',
          createdAt: DateTime.utc(2026, 9, 1, 15),
        ),
        review(
          id: 'new',
          authorId: 'ana',
          authorName: 'Ana',
          placeId: 'mangai',
          placeName: 'Mangai',
          scores: Scores(food: 5, ambience: 4, service: 3),
          createdAt: DateTime.utc(2026, 9, 28, 13),
        ),
        review(id: 'other', authorId: 'bia', placeId: 'mangai'),
      ]);
    events = FollowEvents();
  });

  ProfileViewModel vmFor(String uid, {String? me = 'me'}) => ProfileViewModel(
    uid: uid,
    authRepository: FakeAuthRepository(uid: me),
    userRepository: users,
    reviewRepository: reviews,
    followEvents: events,
    clock: () => _now,
  );

  group('ProfileViewModel', () {
    test(
      'carrega nome, relação e as 50 avaliações mais recentes dela',
      () async {
        final vm = vmFor('ana');
        await vm.load();
        expect(vm.state, ProfileState.ready);
        expect(vm.title, 'Ana');
        expect(vm.isSelf, isFalse);
        expect(vm.isFollowing, isTrue);
        expect(vm.reviews.map((r) => r.id), ['new', 'old']);
        expect(reviews.fetchCalls.single, ['ana']);
        expect(reviews.fetchLimits.single, ProfileViewModel.maxReviews);
        expect(ProfileViewModel.maxReviews, 50);
      },
    );

    test('mais de 50 avaliações: mostra só as 50 mais recentes', () async {
      reviews.stored.addAll([
        for (var i = 0; i < 60; i++)
          review(
            id: 'm$i',
            authorId: 'ana',
            createdAt: DateTime.utc(2026, 5, 1).add(Duration(hours: i)),
          ),
      ]);
      final vm = vmFor('ana');
      await vm.load();
      expect(vm.reviews, hasLength(50));
      expect(vm.reviews.first.id, 'new');
    });

    test('uid inexistente: não encontrada', () async {
      final vm = vmFor('fantasma');
      await vm.load();
      expect(vm.state, ProfileState.notFound);
    });

    test('sem sessão: signedOut, sem ler nada', () async {
      final vm = vmFor('ana', me: null);
      await vm.load();
      expect(vm.state, ProfileState.signedOut);
      expect(reviews.fetchCalls, isEmpty);
    });

    test('nome vazio aparece como "Usuário"', () async {
      users.addUser('x', '   ');
      final vm = vmFor('x');
      await vm.load();
      expect(vm.title, 'Usuário');
      expect(vm.emptyText, 'Usuário ainda não avaliou nenhum lugar');
    });

    test('erro de rede: estado de erro; tentar de novo recupera', () async {
      reviews.fetchError = Exception('network');
      final vm = vmFor('ana');
      await vm.load();
      expect(vm.state, ProfileState.error);

      reviews.fetchError = null;
      await vm.load();
      expect(vm.state, ProfileState.ready);
    });

    test('sem avaliações: texto vazio com o nome', () async {
      users.addUser('caio', 'Caio');
      final vm = vmFor('caio');
      await vm.load();
      expect(vm.reviews, isEmpty);
      expect(vm.emptyText, 'Caio ainda não avaliou nenhum lugar');
      expect(vm.isFollowing, isFalse);
    });

    test('perfil próprio: "Você", sem consultar quem segue', () async {
      final vm = vmFor('me');
      await vm.load();
      expect(vm.isSelf, isTrue);
      expect(vm.title, 'Você');
      expect(users.getFollowingCalls, 0);
      await vm.toggleFollow();
      expect(users.followingByUser['me'], {'ana'}, reason: 'não segue a si');
    });

    test(
      'deixar de seguir é otimista, avisa os outros e pede o "Desfazer"',
      () async {
        final vm = vmFor('ana');
        await vm.load();
        final done = vm.toggleFollow();
        expect(vm.isFollowing, isFalse, reason: 'muda antes da resposta');
        await done;
        expect(users.followingByUser['me'], isEmpty);
        expect(events.version, 1);
        expect(vm.isStale, isFalse, reason: 'o próprio aviso não o marca');
        expect(vm.takeNotice(), ProfileNotice.unfollowed);
        expect(vm.takeNotice(), isNull, reason: 'aviso é entregue uma vez');

        await vm.undoUnfollow();
        expect(users.followingByUser['me'], {'ana'});
        expect(vm.isFollowing, isTrue);
        expect(events.version, 2);
      },
    );

    test('seguir com resposta pendente: botão já mostra Seguindo', () async {
      users.followingByUser['me'] = {};
      final vm = vmFor('ana');
      await vm.load();
      final gate = users.followGate = Completer<void>();
      final done = vm.toggleFollow();
      expect(vm.isFollowing, isTrue);
      expect(vm.isBusy, isTrue);
      gate.complete();
      await done;
      expect(users.followingByUser['me'], {'ana'});
      expect(vm.isBusy, isFalse);
      expect(events.version, 1);
      expect(vm.takeNotice(), isNull, reason: 'seguir não pede "Desfazer"');
    });

    test('falha: reverte e avisa "Não foi possível atualizar"', () async {
      final vm = vmFor('ana');
      await vm.load();
      users.failFollow = true;
      await vm.toggleFollow();
      expect(vm.isFollowing, isTrue);
      expect(vm.takeNotice(), ProfileNotice.followFailed);
      expect(events.version, 0);
    });

    test('mudança feita em outra tela: fica stale e recarrega', () async {
      final vm = vmFor('ana');
      await vm.load();
      await vm.reloadIfStale();
      expect(reviews.fetchCalls, hasLength(1), reason: 'nada mudou');

      users.followingByUser['me'] = {};
      events.changed();
      expect(vm.isStale, isTrue);
      await vm.reloadIfStale();
      expect(reviews.fetchCalls, hasLength(2));
      expect(vm.isFollowing, isFalse);
      vm.dispose();
    });
  });

  group('ProfileView', () {
    Future<ProfileViewModel> pump(WidgetTester tester, String uid) async {
      final vm = vmFor(uid);
      final router = GoRouter(
        initialLocation: '/p',
        routes: [
          GoRoute(
            path: '/p',
            builder: (_, _) => ProfileView(viewModel: vm),
          ),
          GoRoute(
            path: Routes.login,
            builder: (_, _) => const Text('tela de login'),
          ),
          GoRoute(path: Routes.feed, builder: (_, _) => const Text('feed')),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      return vm;
    }

    testWidgets('nome, Seguindo e avaliações com local e eixos', (
      tester,
    ) async {
      await pump(tester, 'ana');
      expect(find.text('Ana'), findsWidgets);
      expect(find.widgetWithText(OutlinedButton, 'Seguindo'), findsOneWidget);
      expect(find.text('Mangai'), findsOneWidget);
      expect(find.text('Camarões'), findsOneWidget);
      expect(find.text('🍽️ 5'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Mangai')).dy,
        lessThan(tester.getTopLeft(find.text('Camarões')).dy),
      );
    });

    testWidgets('rótulos acessíveis do botão e do item de avaliação', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(tester, 'ana');
      expect(
        find.bySemanticsLabel('Seguindo Ana. Toque para deixar de seguir'),
        findsOneWidget,
      );
      final tile = tester.getSemantics(
        find.bySemanticsLabel(RegExp('^Abrir Mangai')),
      );
      expect(tile, containsSemantics(isButton: true, hasTapAction: true));
      expect(tile.label, contains('Comida 5 de 5'), reason: 'item inteiro');
      handle.dispose();
    });

    testWidgets(
      'toque em Seguindo vira Seguir, com "Você deixou de seguir Ana" e Desfazer',
      (tester) async {
        await pump(tester, 'ana');
        await tester.tap(find.text('Seguindo'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(FilledButton, 'Seguir'), findsOneWidget);
        expect(find.text('Você deixou de seguir Ana'), findsOneWidget);

        await tester.tap(find.text('Desfazer'));
        await tester.pumpAndSettle();
        expect(find.text('Seguindo'), findsOneWidget);
        expect(users.followingByUser['me'], {'ana'});
      },
    );

    testWidgets('falha ao seguir: reverte e mostra o aviso', (tester) async {
      await pump(tester, 'ana');
      users.failFollow = true;
      await tester.tap(find.text('Seguindo'));
      await tester.pumpAndSettle();
      expect(find.text('Seguindo'), findsOneWidget);
      expect(find.text('Não foi possível atualizar'), findsOneWidget);
    });

    testWidgets('sem avaliações: "Ana ainda não avaliou nenhum lugar"', (
      tester,
    ) async {
      reviews.stored.clear();
      await pump(tester, 'ana');
      expect(find.text('Ana ainda não avaliou nenhum lugar'), findsOneWidget);
    });

    testWidgets('perfil próprio: título "Você" e sem botão Seguir', (
      tester,
    ) async {
      await pump(tester, 'me');
      expect(find.text('Você'), findsWidgets);
      expect(find.byKey(const Key('profile-follow')), findsNothing);
    });

    testWidgets('uid inexistente: "Pessoa não encontrada" e Voltar', (
      tester,
    ) async {
      await pump(tester, 'fantasma');
      expect(find.text('Pessoa não encontrada'), findsOneWidget);
      await tester.tap(find.text('Voltar'));
      await tester.pumpAndSettle();
      expect(find.text('feed'), findsOneWidget);
    });

    testWidgets('erro: mensagem e "Tentar de novo"', (tester) async {
      users.getFollowingOverride = (_) async => throw Exception('network');
      await pump(tester, 'ana');
      expect(find.text(ProfileViewModel.loadErrorText), findsOneWidget);

      users.getFollowingOverride = null;
      await tester.tap(find.text('Tentar de novo'));
      await tester.pumpAndSettle();
      expect(find.text('Seguindo'), findsOneWidget);
    });

    testWidgets('sem sessão: botão Entrar leva ao login', (tester) async {
      final vm = vmFor('ana', me: null);
      final router = GoRouter(
        initialLocation: '/p',
        routes: [
          GoRoute(
            path: '/p',
            builder: (_, _) => ProfileView(viewModel: vm),
          ),
          GoRoute(
            path: Routes.login,
            builder: (_, _) => const Text('tela de login'),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile-signed-out')), findsOneWidget);
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();
      expect(find.text('tela de login'), findsOneWidget);
    });
  });
}
