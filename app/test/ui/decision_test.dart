import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/decision.dart';
import 'package:naarea/domain/models/companion.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/routing/routes.dart';
import 'package:naarea/ui/decision/decision_view_model.dart';
import 'package:naarea/ui/place/place_detail_view.dart';

import '../support/app_harness.dart';
import '../support/builders.dart';
import '../support/fakes.dart';

/// Sábado, 20h em Natal (noite).
final _now = DateTime.utc(2026, 10, 17, 23);
final _night = DateTime.utc(2026, 10, 10, 23);

final _catalog = <Place>[
  place(id: 'a', name: 'Mangai', neighborhood: 'Tirol'),
  place(id: 'b', name: 'Beco da Lama', neighborhood: 'Cidade Alta'),
  place(id: 'c', name: 'Camarões', neighborhood: 'Ponta Negra'),
  place(id: 'd', name: 'Bar do Zé', neighborhood: 'Petrópolis'),
  place(id: 'e', name: 'Casa de Taipa', neighborhood: 'Ponta Negra'),
];

DecisionCandidate _c(String id, {int hoursAgo = 24}) => (
  place: _catalog.firstWhere((p) => p.id == id),
  savedAt: _now.subtract(Duration(hours: hoursAgo)),
);

/// Bianca ("me") segue Ana e Caio, que foram ao Beco com amigos à noite.
({FakeUserRepository users, FakeReviewRepository reviews}) _friends() {
  final users = FakeUserRepository()
    ..addUser('me', 'Bianca')
    ..addUser('ana', 'Ana')
    ..addUser('caio', 'Caio')
    ..followingByUser['me'] = {'ana', 'caio'};
  final reviews = FakeReviewRepository()
    ..stored.addAll([
      review(
        authorId: 'ana',
        placeId: 'b',
        companion: Companion.amigos,
        createdAt: _night,
      ),
      review(
        authorId: 'caio',
        placeId: 'b',
        companion: Companion.amigos,
        createdAt: _night,
      ),
      // Ninguém que ela segue: não conta.
      review(
        authorId: 'zé',
        placeId: 'c',
        companion: Companion.amigos,
        createdAt: _night,
      ),
    ]);
  return (users: users, reviews: reviews);
}

void main() {
  group('DecisionViewModel', () {
    late FakeUserRepository users;
    late FakeReviewRepository reviews;
    late FakeOpenReportRepository reports;
    late FakeLocationService location;

    setUp(() {
      final f = _friends();
      users = f.users;
      reviews = f.reviews;
      reports = FakeOpenReportRepository();
      location = FakeLocationService();
    });

    DecisionViewModel vm(List<DecisionCandidate> candidates) =>
        DecisionViewModel(
          candidates: candidates,
          authRepository: FakeAuthRepository(uid: 'me'),
          userRepository: users,
          reviewRepository: reviews,
          openReportRepository: reports,
          locationService: location,
          clock: () => _now,
        );

    test('toque 2 (Amigos): 1 lugar com o motivo de quem foi', () async {
      final v = vm([_c('a', hoursAgo: 1), _c('b'), _c('c')]);
      expect(v.phase, DecisionPhase.choosing);
      await v.prepare();
      await v.choose(Companion.amigos);
      expect(v.phase, DecisionPhase.result);
      expect(v.current!.place.id, 'b');
      expect(v.reason, '2 pessoas que você segue foram com amigos à noite');
      expect(reviews.fetchCalls.single.toSet(), {'ana', 'caio'});
    });

    test('nunca pede localização: só a última posição já permitida', () async {
      location
        ..granted = false
        ..position = (lat: -5.79, lng: -35.21);
      final v = vm([_c('a'), _c('b')]);
      await v.choose(null);
      expect(location.locateCalls, 0);
      expect(location.lastKnownCalls, 1);
      expect(v.current!.distanceMeters, isNull);
    });

    test(
      'falha nas avaliações, nos seguidos ou nos relatos não bloqueia',
      () async {
        reviews.fetchError = Exception('network');
        reports.fetchError = Exception('network');
        final v = vm([_c('a', hoursAgo: 1), _c('b')]);
        await v.choose(Companion.amigos);
        expect(v.phase, DecisionPhase.result);
        expect(v.current!.place.id, 'a', reason: 'salvo mais recente');

        users.failGetFollowing = true;
        final v2 = vm([_c('a', hoursAgo: 1), _c('b')]);
        await v2.choose(Companion.amigos);
        expect(v2.current!.place.id, 'a');
      },
    );

    test('"Fechado" relatado sai; todos fechados: nenhum aberto', () async {
      reports.add(
        'b',
        open: false,
        at: _now.subtract(const Duration(minutes: 5)),
      );
      final v = vm([_c('a'), _c('b')]);
      await v.choose(Companion.amigos);
      expect(v.options.map((o) => o.place.id), ['a']);

      reports.add(
        'a',
        open: false,
        at: _now.subtract(const Duration(minutes: 5)),
      );
      final v2 = vm([_c('a'), _c('b')]);
      await v2.choose(Companion.amigos);
      expect(v2.phase, DecisionPhase.noneOpen);
      expect(v2.current, isNull);
    });

    test(
      '"Outra opção" percorre e, depois do último, volta ao 1º avisando',
      () async {
        final v = vm([_c('a', hoursAgo: 1), _c('b'), _c('c', hoursAgo: 30)]);
        await v.choose(Companion.amigos);
        final order = [v.current!.place.id];
        v.next();
        order.add(v.current!.place.id);
        v.next();
        order.add(v.current!.place.id);
        expect(order, ['b', 'a', 'c']);
        expect(v.wrapped, isFalse);
        v.next();
        expect(v.current!.place.id, 'b');
        expect(v.wrapped, isTrue);
        v.next();
        expect(v.wrapped, isFalse);
      },
    );

    test('voltar para a companhia e escolher de novo', () async {
      final v = vm([_c('a', hoursAgo: 1), _c('b')]);
      await v.choose(Companion.casal);
      v.back();
      expect(v.phase, DecisionPhase.choosing);
      await v.choose(Companion.amigos);
      expect(v.current!.place.id, 'b');
    });
  });

  group('sheet "Decidir por mim" no Quero ir', () {
    Future<TestApp> pump(WidgetTester tester, {bool listEmpty = false}) async {
      final f = _friends();
      final saved = FakeSavedRepository();
      for (final p in _catalog) {
        saved.seed('me', p.id, DateTime.utc(2026, 10, 1, 15));
      }
      final lists = FakeListsRepository(saved: saved)
        ..seed(
          'me',
          'sab',
          'Sábado',
          placeIds: listEmpty ? const [] : ['a', 'b', 'c'],
        );
      final app = await pumpApp(
        tester,
        users: f.users,
        reviews: f.reviews,
        saved: saved,
        lists: lists,
        places: _catalog,
        openReports: FakeOpenReportRepository(),
        clock: () => _now,
      );
      app.router.go(Routes.saved);
      await tester.pumpAndSettle();
      return app;
    }

    testWidgets(
      'chip "Sábado" ativo: "Decidir por mim" + "Amigos" mostram exatamente '
      '1 lugar da lista em 2 toques',
      (tester) async {
        await pump(tester);
        await tester.tap(find.byKey(const Key('list-chip-sab')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('saved-decide'))); // toque 1
        await tester.pumpAndSettle();
        expect(find.text('Com quem você vai?'), findsOneWidget);
        await tester.tap(find.byKey(const Key('decide-amigos'))); // toque 2
        await tester.pumpAndSettle();

        final shown = find.byKey(const Key('decide-place'));
        expect(shown, findsOneWidget);
        expect(tester.widget<Text>(shown).data, 'Beco da Lama');
        expect(
          find.text('2 pessoas que você segue foram com amigos à noite'),
          findsOneWidget,
        );
        expect(find.text('Ver local'), findsOneWidget);
        expect(find.text('Outra opção'), findsOneWidget);
      },
    );

    testWidgets('"Outra opção" fica na lista e avisa no fim', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('list-chip-sab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('saved-decide')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('decide-any')));
      await tester.pumpAndSettle();

      final seen = <String>{};
      for (var i = 0; i < 3; i++) {
        seen.add(
          tester.widget<Text>(find.byKey(const Key('decide-place'))).data!,
        );
        await tester.tap(find.byKey(const Key('decide-next')));
        await tester.pumpAndSettle();
      }
      expect(seen, {'Mangai', 'Beco da Lama', 'Camarões'});
      expect(find.text(DecisionViewModel.wrappedText), findsOneWidget);
    });

    testWidgets('"Ver local" fecha o sheet e abre o detalhe', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('saved-decide')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('decide-amigos')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('decide-open')));
      await tester.pumpAndSettle();
      expect(find.byType(PlaceDetailView), findsOneWidget);
      expect(find.byKey(const Key('decide-result')), findsNothing);
    });

    testWidgets('chip sem salvos: botão desabilitado', (tester) async {
      await pump(tester, listEmpty: true);
      await tester.tap(find.byKey(const Key('list-chip-sab')));
      await tester.pumpAndSettle();
      final button = tester.widget<ButtonStyleButton>(
        find.byKey(const Key('saved-decide')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets(
      'todos fechados: "Nenhum lugar desta lista está aberto agora"',
      (tester) async {
        final app = await pump(tester);
        for (final id in ['a', 'b', 'c', 'd', 'e']) {
          app.openReports!.add(
            id,
            open: false,
            at: _now.subtract(const Duration(minutes: 5)),
          );
        }
        await tester.tap(find.byKey(const Key('saved-decide')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('decide-any')));
        await tester.pumpAndSettle();
        expect(find.text(DecisionViewModel.noneOpenText), findsOneWidget);
      },
    );
  });
}
