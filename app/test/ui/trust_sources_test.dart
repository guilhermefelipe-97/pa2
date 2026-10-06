import 'package:flutter/material.dart' hide DayPeriod;
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/feed.dart';
import 'package:naarea/domain/models/companion.dart';
import 'package:naarea/domain/models/day_period.dart';
import 'package:naarea/domain/models/scores.dart';
import 'package:naarea/ui/feed/widgets/feed_card.dart';
import 'package:naarea/ui/feed/widgets/trust_sources.dart';

import '../support/builders.dart';

final _now = DateTime.utc(2026, 9, 28, 15); // 12h em Natal

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

/// Pílula de um eixo (mesmo widget do detalhe): "🍽️ 5".
Finder _pill(String text, {Finder? within}) => within == null
    ? find.text(text)
    : find.descendant(of: within, matching: find.text(text));

FeedItem _fourPeople() => groupReviewsIntoFeed(
  [
    review(
      authorId: 'c',
      authorName: 'Caio',
      placeId: 'x',
      createdAt: DateTime.utc(2026, 9, 20),
    ),
    review(
      authorId: 'a',
      authorName: 'Ana',
      placeId: 'x',
      createdAt: DateTime.utc(2026, 9, 28, 14), // há 1 h
    ),
    review(
      authorId: 'd',
      authorName: 'Duda',
      placeId: 'x',
      createdAt: DateTime.utc(2026, 9, 19),
    ),
    review(
      authorId: 'b',
      authorName: 'Bia',
      placeId: 'x',
      createdAt: DateTime.utc(2026, 9, 26, 15), // há 2 dias
    ),
  ],
  places: {'x': place(id: 'x', name: 'Mangai')},
).single;

void main() {
  group('textos', () {
    test('companhia + período como frase', () {
      // 22h UTC = 19h em Natal: noite
      final night = DateTime.utc(2026, 9, 27, 22);
      expect(
        visitContext(review(companion: Companion.amigos, createdAt: night)),
        'com amigos à noite',
      );
      expect(visitContext(review(createdAt: night)), 'à noite');
      expect(periodPhrase(DayPeriod.almoco), 'no almoço');
      expect(companionPhrase(Companion.familia), 'com a família');
      expect(companionPhrase(Companion.sozinho), 'sem companhia');
    });

    test('visitas: só aparece a partir de 2', () {
      expect(visitsLabel(1), isNull);
      expect(visitsLabel(2), 'foi 2 vezes');
    });

    test('"+N pessoas" e o rótulo acessível, com singular', () {
      expect(morePeopleLabel(1), '+1 pessoa');
      expect(morePeopleLabel(2), '+2 pessoas');
      expect(morePeopleSemantics(1), 'Ver a outra pessoa');
      expect(morePeopleSemantics(2), 'Ver as 2 outras pessoas');
    });

    test('nome vazio vira "Alguém"', () {
      expect(displayAuthorName(''), 'Alguém');
      expect(displayAuthorName('   '), 'Alguém');
      expect(displayAuthorName(' Ana '), 'Ana');
    });

    test('rótulo de acessibilidade completo de uma fonte', () {
      final item = groupReviewsIntoFeed([
        review(
          authorId: 'a',
          authorName: 'Ana',
          placeId: 'x',
          scores: Scores(food: 5, ambience: 4, service: 5),
          companion: Companion.amigos,
          createdAt: DateTime.utc(2026, 9, 28, 13), // 10h Natal, há 2 h
        ),
        review(
          authorId: 'a',
          authorName: 'Ana',
          placeId: 'x',
          createdAt: DateTime.utc(2026, 9, 1),
        ),
      ]).single;
      expect(
        sourceSemanticsLabel(item.sources.single, following: true, now: _now),
        'Ana, você segue, comida 5, ambiente 4, atendimento 5, '
        'com amigos de manhã, foi 2 vezes, há 2 horas',
      );
      expect(
        sourceSemanticsLabel(item.sources.single, following: false, now: _now),
        startsWith('Ana, comida 5'),
      );
    });
  });

  group('TrustSources', () {
    testWidgets(
      '1 pessoa: linha dela com os eixos dela (AxisScores), sem "+N"',
      (tester) async {
        final item = groupReviewsIntoFeed([
          review(
            authorId: 'a',
            authorName: 'Ana',
            placeId: 'x',
            scores: Scores(food: 5, ambience: 4, service: 3),
            createdAt: DateTime.utc(2026, 9, 28, 13),
          ),
        ]).single;
        await tester.pumpWidget(
          _host(TrustSources(item: item, now: _now, isFollowing: (_) => true)),
        );
        expect(find.text('Ana'), findsOneWidget);
        expect(find.text('você segue'), findsOneWidget);
        expect(_pill('🍽️ 5'), findsOneWidget);
        expect(_pill('✨ 4'), findsOneWidget);
        expect(_pill('🤝 3'), findsOneWidget);
        expect(find.text('de manhã'), findsOneWidget);
        expect(find.text('há 2 h'), findsOneWidget);
        // mesmo widget do detalhe: dica com o nome de cada eixo
        expect(find.byTooltip('Comida'), findsOneWidget);
        expect(find.byTooltip('Ambiente'), findsOneWidget);
        expect(find.byTooltip('Atendimento'), findsOneWidget);
        expect(find.byKey(const Key('trust-sources-more')), findsNothing);
      },
    );

    testWidgets('4 pessoas: Ana e Bia em destaque e botão "+2 pessoas"', (
      tester,
    ) async {
      var showAll = 0;
      await tester.pumpWidget(
        _host(
          TrustSources(
            item: _fourPeople(),
            now: _now,
            onShowAll: () => showAll++,
          ),
        ),
      );
      expect(find.text('Ana'), findsOneWidget);
      expect(find.text('Bia'), findsOneWidget);
      expect(find.text('Caio'), findsNothing);
      expect(find.text('Duda'), findsNothing);
      expect(
        find.widgetWithText(TextButton, '+2 pessoas'),
        findsOneWidget,
        reason: 'botão de verdade',
      );
      expect(
        tester.getTopLeft(find.text('Ana')).dy,
        lessThan(tester.getTopLeft(find.text('Bia')).dy),
      );
      expect(find.text('há 1 h'), findsOneWidget);
      expect(find.text('há 2 dias'), findsOneWidget);

      await tester.tap(find.text('+2 pessoas'));
      expect(showAll, 1);
    });

    testWidgets('"+N" para o leitor de tela: "Ver as 2 outras pessoas"', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(FeedCard(item: _fourPeople(), now: _now, onTap: () {})),
      );
      final node = tester.getSemantics(
        find.bySemanticsLabel('Ver as 2 outras pessoas'),
      );
      expect(node, containsSemantics(isButton: true, hasTapAction: true));
      handle.dispose();
    });

    testWidgets('"+N" no card abre o detalhe (o mesmo toque do card)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(412, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var opened = 0;
      await tester.pumpWidget(
        _host(FeedCard(item: _fourPeople(), now: _now, onTap: () => opened++)),
      );
      await tester.tap(find.text('+2 pessoas'));
      expect(opened, 1);
    });

    testWidgets('mesma pessoa 3 vezes: 1 linha, eixos da mais recente', (
      tester,
    ) async {
      final item = groupReviewsIntoFeed([
        for (final (day, food) in [(1, 1), (10, 2), (27, 5)])
          review(
            authorId: 'a',
            authorName: 'Ana',
            placeId: 'x',
            scores: Scores(food: food, ambience: 4, service: 4),
            createdAt: DateTime.utc(2026, 9, day, 15),
          ),
      ]).single;
      await tester.pumpWidget(_host(TrustSources(item: item, now: _now)));
      expect(find.text('Ana'), findsOneWidget);
      expect(_pill('🍽️ 5'), findsOneWidget);
      expect(find.text('no almoço · foi 3 vezes'), findsOneWidget);
    });

    testWidgets('sem seguir: sem selo "você segue"', (tester) async {
      final item = groupReviewsIntoFeed([review(placeId: 'x')]).single;
      await tester.pumpWidget(
        _host(TrustSources(item: item, now: _now, isFollowing: (_) => false)),
      );
      expect(find.text('você segue'), findsNothing);
    });

    testWidgets('autor sem nome aparece como "Alguém"', (tester) async {
      final item = groupReviewsIntoFeed([
        review(authorId: 'a', authorName: '  ', placeId: 'x'),
      ]).single;
      await tester.pumpWidget(_host(TrustSources(item: item, now: _now)));
      expect(find.text('Alguém'), findsOneWidget);
    });

    testWidgets('toque na pessoa chama onOpenPerson com ela', (tester) async {
      final item = groupReviewsIntoFeed([
        review(authorId: 'a', authorName: 'Ana', placeId: 'x'),
      ]).single;
      final opened = <String>[];
      await tester.pumpWidget(
        _host(
          TrustSources(
            item: item,
            now: _now,
            onOpenPerson: (s) => opened.add(s.authorId),
          ),
        ),
      );
      await tester.tap(find.text('Ana'));
      expect(opened, ['a']);
    });

    testWidgets('320 dp e fonte 2.0: nome longo não estoura a linha', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final item = groupReviewsIntoFeed(
        [
          review(
            authorId: 'a',
            authorName: 'Maria Aparecida dos Santos Albuquerque',
            placeId: 'x',
            companion: Companion.familia,
            createdAt: DateTime.utc(2026, 9, 1, 15),
          ),
          review(
            authorId: 'a',
            authorName: 'Maria Aparecida dos Santos Albuquerque',
            placeId: 'x',
            createdAt: DateTime.utc(2025, 12, 25, 15),
          ),
          for (final id in ['b', 'c', 'd'])
            review(authorId: id, authorName: 'Pessoa $id', placeId: 'x'),
        ],
        places: {'x': place(id: 'x', name: 'Mangai')},
      ).single;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 1200),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: FeedCard(
                  item: item,
                  now: _now,
                  isFollowing: (_) => true,
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull, reason: 'sem RenderFlex overflow');
    });

    testWidgets(
      'leitor de tela: cada linha é um botão com a frase completa, dentro do card',
      (tester) async {
        final handle = tester.ensureSemantics();
        final item = groupReviewsIntoFeed(
          [
            review(
              authorId: 'a',
              authorName: 'Ana',
              placeId: 'x',
              scores: Scores(food: 5, ambience: 4, service: 5),
              companion: Companion.amigos,
              createdAt: DateTime.utc(2026, 9, 28, 13),
            ),
          ],
          places: {'x': place(id: 'x', name: 'Mangai')},
        ).single;
        await tester.pumpWidget(
          _host(
            FeedCard(
              item: item,
              now: _now,
              onTap: () {},
              isFollowing: (_) => true,
              onOpenPerson: (_) {},
            ),
          ),
        );
        final node = tester.getSemantics(
          find.bySemanticsLabel(
            'Ana, você segue, comida 5, ambiente 4, atendimento 5, '
            'com amigos de manhã, há 2 horas',
          ),
        );
        expect(node, containsSemantics(isButton: true, hasTapAction: true));
        // O card continua um botão "Abrir Mangai" à parte.
        expect(find.bySemanticsLabel(RegExp('^Abrir Mangai')), findsOneWidget);
        handle.dispose();
      },
    );
  });

  testWidgets('F14: Ana só com comida 4 mostra "🍽️ 4" e fala "comida 4"', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final item = groupReviewsIntoFeed(
      [
        review(
          authorId: 'ana',
          authorName: 'Ana',
          placeId: 'mangai',
          scores: Scores(food: 4),
          createdAt: DateTime.utc(2026, 9, 28, 13),
        ),
      ],
      places: {'mangai': place(id: 'mangai', name: 'Mangai')},
    ).single;
    expect(
      sourceSemanticsLabel(item.sources.single, following: false, now: _now),
      'Ana, comida 4, de manhã, há 2 horas',
    );
    await tester.pumpWidget(_host(FeedCard(item: item, now: _now)));
    final row = find.byKey(const ValueKey('trust-source-ana'));
    expect(_pill('🍽️ 4', within: row), findsOneWidget);
    expect(find.textContaining('✨'), findsNothing);
    expect(find.textContaining('🤝'), findsNothing);
    handle.dispose();
  });

  testWidgets('AC F14: Bianca só com ambiente 5 aparece no card com "✨ 5" e '
      'nenhum outro eixo', (tester) async {
    final item = groupReviewsIntoFeed(
      [
        review(
          authorId: 'bianca',
          authorName: 'Bianca',
          placeId: 'mangai',
          scores: Scores(ambience: 5),
          createdAt: DateTime.utc(2026, 9, 28, 13),
        ),
      ],
      places: {'mangai': place(id: 'mangai', name: 'Mangai')},
    ).single;
    await tester.pumpWidget(_host(FeedCard(item: item, now: _now)));
    expect(_pill('✨ 5'), findsOneWidget);
    expect(find.textContaining('🍽️'), findsNothing);
    expect(find.textContaining('🤝'), findsNothing);
  });

  testWidgets('AC: Bianca segue Ana; o card mostra "Ana" + "você segue" e '
      '🍽️ 5 de Ana, sem número sem nome', (tester) async {
    final item = groupReviewsIntoFeed(
      [
        review(
          authorId: 'ana',
          authorName: 'Ana',
          placeId: 'mangai',
          scores: Scores(food: 5, ambience: 4, service: 4),
          createdAt: DateTime.utc(2026, 9, 28, 13),
        ),
      ],
      places: {'mangai': place(id: 'mangai', name: 'Mangai')},
    ).single;
    await tester.pumpWidget(
      _host(
        FeedCard(item: item, now: _now, isFollowing: (uid) => uid == 'ana'),
      ),
    );
    final row = find.byKey(const ValueKey('trust-source-ana'));
    expect(
      find.descendant(of: row, matching: find.text('Ana')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('você segue')),
      findsOneWidget,
    );
    expect(_pill('🍽️ 5', within: row), findsOneWidget);
    // Todas as notas do card estão na linha de alguém.
    expect(find.textContaining('🍽️'), findsOneWidget);
  });
}
