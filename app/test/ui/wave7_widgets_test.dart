import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/data/repositories/owner_repository.dart';
import 'package:naarea/data/repositories/place_history_repository.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/domain/models/review.dart';
import 'package:naarea/domain/models/scores.dart';
import 'package:naarea/domain/models/visit.dart';
import 'package:naarea/domain/owner_timeline.dart';
import 'package:naarea/routing/router.dart';
import 'package:naarea/routing/routes.dart';
import 'package:naarea/ui/auth/auth_view.dart';
import 'package:naarea/ui/owner/owner_timeline_view.dart';
import 'package:naarea/ui/place/place_detail_view.dart';
import 'package:naarea/ui/share/place_share_sheet.dart';
import 'package:naarea/ui/share/share_service.dart';

import '../support/app_harness.dart';
import '../support/builders.dart';
import '../support/fakes.dart';

class _History implements PlaceHistoryRepository {
  _History({this.reviews = const [], this.visits = const []});
  final List<Review> reviews;
  final List<Visit> visits;
  final calls = <(String, DateTime)>[];
  @override
  Future<List<Review>> reviewsSince(String placeId, DateTime since) async {
    calls.add((placeId, since));
    return reviews
        .where((r) => r.placeId == placeId && !r.createdAt.isBefore(since))
        .toList();
  }

  @override
  Future<List<Visit>> visitsSince(String placeId, DateTime since) async =>
      visits
          .where((v) => v.placeId == placeId && !v.createdAt.isBefore(since))
          .toList();
}

class _Share implements ShareService {
  final sent = <({Uint8List png, String text, String subject})>[];
  @override
  Future<void> shareImage({
    required Uint8List png,
    required String text,
    required String subject,
  }) async => sent.add((png: png, text: text, subject: subject));
}

void main() {
  final now = DateTime.utc(2026, 11, 4, 21);
  const place = Place(
    id: 'p',
    name: 'Bar da Praia',
    category: 'Bar',
    neighborhood: 'Ponta Negra',
    city: 'Natal',
  );
  FakeOwnerRepository owned() => FakeOwnerRepository()
    ..owners['p'] = 'me'
    ..requests['me'] = [const OwnershipRequest('p', 'approved')];

  group('F23 painel com série temporal', () {
    final history = _History(
      reviews: [
        // Julho, 20h em Natal: atendimento ruim à noite.
        review(
          placeId: 'p',
          scores: Scores(food: 5, service: 1),
          createdAt: DateTime.utc(2026, 7, 10, 23),
        ),
        // Julho, 12h em Natal: atendimento bom no almoço.
        review(
          placeId: 'p',
          scores: Scores(food: 5, service: 5),
          createdAt: DateTime.utc(2026, 7, 11, 15),
        ),
      ],
      visits: [visit(placeId: 'p', createdAt: DateTime.utc(2026, 7, 12, 15))],
    );

    testWidgets('titular vê médias por eixo mês a mês e recorta a noite', (
      tester,
    ) async {
      final app = await pumpApp(
        tester,
        places: [place],
        owners: owned(),
        history: history,
        clock: () => now,
      );
      app.router.go('/meus-estabelecimentos');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Painel do local'));
      await tester.pumpAndSettle();
      expect(find.byType(OwnerTimelineView), findsOneWidget);
      expect(find.text('Bar da Praia'), findsOneWidget);
      expect(history.calls.last.$2, OwnerTimeline.windowStart(now));

      final july = find.byKey(const ValueKey('timeline-2026-7'));
      await tester.scrollUntilVisible(july, 200);
      expect(
        find.descendant(
          of: july,
          matching: find.text('Comida 5 · Ambiente — · Atendimento 3'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: july,
          matching: find.text('2 avaliações · 1 "Voltei aqui"'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: july, matching: find.textContaining('Amostra')),
        findsOneWidget,
      );

      await tester.scrollUntilVisible(
        find.widgetWithText(ChoiceChip, 'Noite'),
        -200,
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'Noite'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(july, 200);
      expect(
        find.descendant(
          of: july,
          matching: find.text('Comida 5 · Ambiente — · Atendimento 1'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: july,
          matching: find.text('1 avaliação · 0 "Voltei aqui"'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('quem não é titular não vê o painel', (tester) async {
      final owners = FakeOwnerRepository()..owners['p'] = 'outra';
      final unused = _History(reviews: history.reviews);
      final app = await pumpApp(
        tester,
        places: [place],
        owners: owners,
        history: unused,
        clock: () => now,
      );
      app.router.push(Routes.ownerTimeline('p'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'O painel é exclusivo do titular atual deste estabelecimento.',
        ),
        findsOneWidget,
      );
      expect(find.text('Mês a mês'), findsNothing);
      expect(unused.calls, isEmpty);
    });

    testWidgets('sem avaliações mostra estado vazio, sem gráfico', (
      tester,
    ) async {
      final app = await pumpApp(
        tester,
        places: [place],
        owners: owned(),
        history: _History(),
        clock: () => now,
      );
      app.router.push(Routes.ownerTimeline('p'));
      await tester.pumpAndSettle();
      expect(
        find.text('Ainda não há avaliações nos últimos 12 meses.'),
        findsOneWidget,
      );
      expect(find.text('Mês a mês'), findsNothing);
    });
  });

  group('F26 status do piso para o titular', () {
    testWidgets('Divulgação mostra a regra e o status de cada local', (
      tester,
    ) async {
      final history = _History(
        reviews: [
          for (var i = 0; i < 5; i++)
            review(
              placeId: 'p',
              scores: Scores(food: 3, service: 3),
              createdAt: now.subtract(Duration(days: i)),
            ),
        ],
      );
      final app = await pumpApp(
        tester,
        places: [place],
        owners: owned(),
        history: history,
        clock: () => now,
      );
      app.router.go('/meus-estabelecimentos');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Divulgação'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Divulgação'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Regra do Destaque'), findsOneWidget);
      expect(
        find.text(
          'Bar da Praia: Destaque suspenso: média 3 em 5 avaliações nos '
          'últimos 90 dias, abaixo do piso de 3,5.',
        ),
        findsOneWidget,
      );
    });
  });

  group('F21 card compartilhável com deep link', () {
    testWidgets('ficha gera o card e envia imagem com texto e link', (
      tester,
    ) async {
      final share = _Share();
      final app = await pumpApp(
        tester,
        places: [place],
        share: share,
        clock: () => now,
      );
      app.router.push(Routes.placeDetail('p'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('place-share')));
      await tester.pumpAndSettle();
      expect(find.byType(PlaceShareCard), findsOneWidget);
      expect(find.text('Indicado por Eu'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('share-send')));
        for (var i = 0; i < 20 && share.sent.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();
      expect(share.sent, hasLength(1));
      final sent = share.sent.single;
      expect(sent.png.sublist(1, 4), 'PNG'.codeUnits);
      expect(
        sent.text,
        'Bar da Praia — Bar em Ponta Negra\n'
        'Vi no NaÁrea: https://naarea-natal.web.app/l/p',
      );
      expect(sent.text, isNot(contains('Eu')));
      expect(find.byType(PlaceShareCard), findsNothing);
    });

    testWidgets('sem serviço de compartilhamento o botão não aparece', (
      tester,
    ) async {
      final app = await pumpApp(tester, places: [place]);
      app.router.push(Routes.placeDetail('p'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('place-share')), findsNothing);
    });

    test('link codifica o id do local', () {
      expect(
        sharedPlaceLink('osm-node/1'),
        'https://naarea-natal.web.app/l/osm-node%2F1',
      );
    });

    testWidgets('link aberto com sessão vai direto para a ficha', (
      tester,
    ) async {
      final app = await pumpApp(tester, places: [place]);
      app.router.go('/l/p');
      await tester.pumpAndSettle();
      expect(find.byType(PlaceDetailView), findsOneWidget);
      expect(find.text('Bar da Praia'), findsWidgets);
    });

    testWidgets('link aberto sem sessão passa pelo login e volta à ficha', (
      tester,
    ) async {
      final app = await pumpApp(tester, uid: null, places: [place]);
      app.router.go('/l/p');
      await tester.pumpAndSettle();
      expect(find.byType(AuthView), findsOneWidget);
      app.auth.restoreSession('me');
      await tester.pumpAndSettle();
      expect(find.byType(PlaceDetailView), findsOneWidget);
      expect(app.router.state.matchedLocation, Routes.placeDetail('p'));
    });

    testWidgets('id inexistente mostra local não encontrado', (tester) async {
      final app = await pumpApp(tester, places: [place]);
      app.router.go('/l/nao-existe');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('place-not-found')), findsOneWidget);
    });

    test('authRedirect usa o link pendente só depois do login', () {
      expect(
        authRedirect(
          isInitialized: true,
          isSignedIn: false,
          location: '/l/p',
          pending: '/l/p',
        ),
        Routes.login,
      );
      expect(
        authRedirect(
          isInitialized: true,
          isSignedIn: true,
          location: Routes.login,
          pending: '/l/p',
        ),
        '/l/p',
      );
      expect(
        authRedirect(
          isInitialized: true,
          isSignedIn: true,
          location: Routes.login,
        ),
        Routes.feed,
      );
    });
  });
}
