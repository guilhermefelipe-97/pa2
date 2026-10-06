import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/feed.dart';
import 'package:naarea/domain/models/companion.dart';
import 'package:naarea/data/repositories/review_repository.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/domain/models/review.dart';
import 'package:naarea/domain/models/scores.dart';
import 'package:naarea/ui/feed/feed_view.dart';
import 'package:naarea/ui/feed/feed_view_model.dart';
import 'package:naarea/ui/feed/widgets/author_avatar.dart';
import 'package:naarea/ui/feed/widgets/axis_scores.dart';
import 'package:naarea/ui/feed/widgets/feed_card.dart';
import 'package:naarea/ui/feed/widgets/place_photo.dart';
import 'package:naarea/ui/feed/widgets/review_tile.dart';
import 'package:naarea/ui/place/place_detail_view.dart';
import 'package:naarea/ui/review/review_view.dart';
import 'package:naarea/ui/review/review_view_model.dart';
import 'package:naarea/ui/core/follow_events.dart';

import '../support/builders.dart';
import '../support/app_harness.dart';
import '../support/fakes.dart';

final _now = DateTime.utc(2026, 9, 28, 15); // 12h em Natal

FeedViewModel _feedVm({
  FakeUserRepository? users,
  FakeReviewRepository? reviews,
  List<Place> places = const [],
}) => FeedViewModel(
  authRepository: FakeAuthRepository(uid: 'me'),
  userRepository: users ?? FakeUserRepository(),
  reviewRepository: reviews ?? FakeReviewRepository(),
  placeRepository: FakePlaceRepository(places),
  clock: () => _now,
  followEvents: FollowEvents(),
);

/// Tela de celular alta (412x2000 dp) para as listas preguiçosas construírem
/// tudo o que o teste procura.
void _tallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(412, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Repositório cujo envio só termina quando [gate] completa.
class _GatedReviewRepository extends FakeReviewRepository {
  _GatedReviewRepository(this.gate);

  final Future<void> gate;

  @override
  Future<void> createReview(NewReview review, {Uint8List? photo}) async {
    await gate;
    return super.createReview(review, photo: photo);
  }
}

void main() {
  ReviewViewModel reviewVm({ReviewRepository? reviews}) => ReviewViewModel(
    place: const Place(
      id: 'x',
      name: 'Mangai',
      category: 'Restaurante',
      neighborhood: 'Tirol',
      city: 'Natal',
    ),
    authRepository: FakeAuthRepository(uid: 'me'),
    userRepository: FakeUserRepository()..addUser('me', 'Eu'),
    reviewRepository: reviews ?? FakeReviewRepository(),
    photoPicker: FakePhotoPicker(),
    compress: (b) async => b,
  );

  bool clearVisible(WidgetTester tester, String axis) => tester
      .widget<Visibility>(
        find.ancestor(
          of: find.byKey(Key('axis-$axis-clear')),
          matching: find.byType(Visibility),
        ),
      )
      .visible;

  Finder header(String text) => find
      .ancestor(of: find.text(text), matching: find.byType(ConstrainedBox))
      .first;

  testWidgets('ReviewView: Enviar habilita no 1º eixo tocado; Limpar e dica '
      '(F14)', (tester) async {
    _tallPhone(tester);
    final vm = reviewVm();
    await tester.pumpWidget(MaterialApp(home: ReviewView(viewModel: vm)));

    FilledButton submit() =>
        tester.widget<FilledButton>(find.byKey(const Key('review-submit')));
    expect(submit().onPressed, isNull);
    expect(noAxisHint, 'Toque numa estrela de pelo menos um eixo');
    expect(find.text(noAxisHint), findsOneWidget);
    expect(clearVisible(tester, 'food'), isFalse);
    expect(find.text('Avalie o que quiser — um eixo já basta.'), findsNothing);
    // A dica fica junto dos eixos, antes da companhia e do Enviar.
    expect(
      tester.getTopLeft(find.text(noAxisHint)).dy,
      lessThan(
        tester.getTopLeft(find.text('Com quem você foi? (opcional)')).dy,
      ),
    );
    // Eixo sem nota: o mesmo "sem notas" das médias.
    expect(find.text(noScoresLabel), findsNWidgets(3));

    final headerBefore = tester.getSize(header('🍽️ Comida'));
    await tester.tap(find.byKey(const Key('axis-food-4')));
    await tester.pump();
    expect(vm.food, 4);
    expect(vm.ambience, isNull);
    expect(submit().onPressed, isNotNull);
    expect(find.text(noAxisHint), findsNothing);
    expect(clearVisible(tester, 'food'), isTrue);
    expect(find.text('4 de 5'), findsOneWidget);
    // Limpar aparece sem o cabeçalho mudar de tamanho.
    expect(tester.getSize(header('🍽️ Comida')), headerBefore);

    // Trocar de 4 para 2.
    await tester.tap(find.byKey(const Key('axis-food-2')));
    await tester.pump();
    expect(vm.food, 2);
    expect(find.text('2 de 5'), findsOneWidget);

    await tester.tap(find.byKey(const Key('axis-food-clear')));
    await tester.pump();
    expect(vm.food, isNull);
    expect(submit().onPressed, isNull);
    expect(find.text(noAxisHint), findsOneWidget);

    await tester.tap(find.byKey(const Key('axis-ambience-5')));
    await tester.pump();
    expect(vm.ambience, 5);
    expect(submit().onPressed, isNotNull);
  });

  testWidgets('ReviewView: estrelas acessíveis — rótulo, selecionada e toque '
      'pelo leitor de tela (F14)', (tester) async {
    _tallPhone(tester);
    final handle = tester.ensureSemantics();
    final vm = reviewVm();
    await tester.pumpWidget(MaterialApp(home: ReviewView(viewModel: vm)));

    expect(
      tester.getSemantics(find.bySemanticsLabel('Comida 4 de 5')),
      containsSemantics(
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasSelectedState: true,
        isSelected: false,
        hasTapAction: true,
      ),
    );

    tester.semantics.tap(find.semantics.byLabel('Comida 4 de 5'));
    await tester.pump();
    expect(vm.food, 4);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Comida 4 de 5')),
      containsSemantics(isSelected: true),
    );

    // A dica é região viva: anunciada quando aparece.
    vm.clearFood();
    await tester.pump();
    expect(
      tester.getSemantics(find.bySemanticsLabel(noAxisHint)),
      containsSemantics(isLiveRegion: true),
    );
    handle.dispose();
  });

  testWidgets('ReviewView: durante o envio, estrelas e Limpar ficam '
      'desabilitados (F14)', (tester) async {
    _tallPhone(tester);
    final handle = tester.ensureSemantics();
    final gate = Completer<void>();
    final vm = reviewVm(reviews: _GatedReviewRepository(gate.future));
    await tester.pumpWidget(MaterialApp(home: ReviewView(viewModel: vm)));
    await tester.tap(find.byKey(const Key('axis-food-4')));
    await tester.pump();

    unawaited(vm.submit());
    await tester.pump();
    expect(vm.isSubmitting, isTrue);
    expect(
      tester.widget<IconButton>(find.byKey(const Key('axis-food-3'))).onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('axis-food-clear')))
          .onPressed,
      isNull,
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Comida 3 de 5')),
      containsSemantics(
        hasEnabledState: true,
        isEnabled: false,
        hasTapAction: false,
      ),
    );
    final opacity = tester.widget<Opacity>(
      find.descendant(
        of: find.byKey(const Key('axis-food-3')),
        matching: find.byType(Opacity),
      ),
    );
    expect(opacity.opacity, lessThan(1));

    gate.complete();
    await tester.pumpAndSettle();
    handle.dispose();
  });

  testWidgets('ReviewView: estrelas cabem em 320 dp com texto 2x (F14)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vm = reviewVm()..setFood(3);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: ReviewView(viewModel: vm),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    final size = tester
        .widget<IconButton>(find.byKey(const Key('axis-food-5')))
        .iconSize!;
    expect(size, lessThanOrEqualTo(44));
    // 5 estrelas lado a lado dentro da largura útil (320 - 2 x 16).
    final right = tester.getTopRight(find.byKey(const Key('axis-food-5'))).dx;
    expect(right, lessThanOrEqualTo(320 - 16));
  });

  testWidgets('AxisScores.scores: só os eixos avaliados, sem placeholders '
      '(F14)', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: AxisScores.scores(Scores(food: 4)))),
    );
    expect(find.text('🍽️ 4'), findsOneWidget);
    expect(find.textContaining('✨'), findsNothing);
    expect(find.textContaining('🤝'), findsNothing);
    expect(find.textContaining('sem notas'), findsNothing);
    expect(find.bySemanticsLabel('Comida 4 de 5'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Ambiente|Atendimento')), findsNothing);
    handle.dispose();
  });

  testWidgets('AxisScores.averages: contagem igual ao total só na '
      'semântica; dense com fonte mínima 12 (F14)', (tester) async {
    final handle = tester.ensureSemantics();
    final avg = AxisAverages.of([
      Scores(food: 4, ambience: 3, service: 5),
      Scores(food: 5, ambience: 3, service: 4),
    ]);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: AxisScores.averages(avg, dense: true))),
    );
    expect(find.textContaining('('), findsNothing);
    expect(
      find.bySemanticsLabel('Comida 4,5 de 5, 2 avaliações'),
      findsOneWidget,
    );
    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      expect(t.style!.fontSize, greaterThanOrEqualTo(12), reason: t.data);
    }
    handle.dispose();
  });

  testWidgets('AxisScores.averages: contagem por eixo e "sem notas" (F14)', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final avg = AxisAverages.of([
      Scores(food: 4),
      Scores(food: 5, service: 3),
      Scores(service: 3),
    ]);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: AxisScores.averages(avg))),
    );
    expect(find.text('🍽️ 4,5'), findsOneWidget);
    // 3 avaliações: comida e atendimento em 2 delas → "(2)" visível.
    expect(find.text(' (2)'), findsNWidgets(2));
    expect(find.text('✨ sem notas'), findsOneWidget);
    expect(find.textContaining('✨ 0'), findsNothing);
    expect(
      find.bySemanticsLabel('Comida 4,5 de 5, 2 avaliações'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Ambiente sem notas'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('ReviewView: campo de comentário opcional, limitado a 280', (
    tester,
  ) async {
    final vm = ReviewViewModel(
      place: const Place(
        id: 'x',
        name: 'Mangai',
        category: 'Restaurante',
        neighborhood: 'Tirol',
        city: 'Natal',
      ),
      authRepository: FakeAuthRepository(uid: 'me'),
      userRepository: FakeUserRepository()..addUser('me', 'Eu'),
      reviewRepository: FakeReviewRepository(),
      photoPicker: FakePhotoPicker(),
      compress: (b) async => b,
    );
    await tester.pumpWidget(MaterialApp(home: ReviewView(viewModel: vm)));

    final field = find.byKey(const Key('review-comment'));
    await tester.ensureVisible(field);
    expect(tester.widget<TextField>(field).maxLength, 280);

    await tester.enterText(field, 'x' * 300);
    await tester.pump();
    expect(vm.comment.length, 280, reason: 'o campo corta em 280');

    await tester.enterText(field, '  Top  ');
    await tester.pump();
    expect(vm.comment, '  Top  ');
  });

  testWidgets('FeedView: sem seguir ninguém mostra CTA "Encontrar pessoas"', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: FeedView(viewModel: _feedVm())));
    await tester.pumpAndSettle();
    expect(find.text('Encontrar pessoas'), findsOneWidget);
  });

  testWidgets(
    'FeedView: card com bairro, quem foi (eixos de cada pessoa), comentário mais recente e tempo relativo',
    (tester) async {
      final users = FakeUserRepository()..followingByUser['me'] = {'a', 'b'};
      final reviews = FakeReviewRepository()
        ..stored.addAll([
          review(
            authorId: 'a',
            authorName: 'Ana',
            placeId: 'x',
            placeName: 'Mangai',
            scores: Scores(food: 5, ambience: 2, service: 4),
            createdAt: DateTime.utc(2026, 9, 27, 15),
          ),
          review(
            authorId: 'b',
            authorName: 'Beto',
            placeId: 'x',
            placeName: 'Mangai',
            scores: Scores(food: 4, ambience: 3, service: 5),
            companion: Companion.amigos,
            comment: 'Carne de sol perfeita',
            createdAt: DateTime.utc(2026, 9, 28, 13),
          ), // 10h Natal, há 2 h
        ]);
      final vm = _feedVm(
        users: users,
        reviews: reviews,
        places: [
          place(
            id: 'x',
            name: 'Mangai',
            category: 'Restaurante',
            neighborhood: 'Tirol',
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp(home: FeedView(viewModel: vm)));
      await tester.pumpAndSettle();

      expect(find.text('Mangai'), findsOneWidget);
      expect(find.text('Tirol · Restaurante'), findsOneWidget);
      expect(find.text('Quem foi'), findsOneWidget);
      // Beto (mais recente) primeiro, com os eixos dele; depois Ana.
      expect(find.text('Beto'), findsOneWidget);
      expect(find.text('Ana'), findsOneWidget);
      expect(find.text('você segue'), findsNWidgets(2));
      Finder inRow(String uid, String text) => find.descendant(
        of: find.byKey(ValueKey('trust-source-$uid')),
        matching: find.text(text),
      );
      expect(inRow('b', '🍽️ 4'), findsOneWidget);
      expect(inRow('b', '✨ 3'), findsOneWidget);
      expect(inRow('b', '🤝 5'), findsOneWidget);
      expect(inRow('b', 'com amigos de manhã'), findsOneWidget);
      expect(inRow('a', '🍽️ 5'), findsOneWidget);
      expect(inRow('a', '✨ 2'), findsOneWidget);
      expect(inRow('a', '🤝 4'), findsOneWidget);
      expect(inRow('a', 'no almoço'), findsOneWidget);
      expect(find.text('há 2 h'), findsOneWidget);
      expect(find.text('ontem'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Beto')).dy,
        lessThan(tester.getTopLeft(find.text('Ana')).dy),
      );
      // sem média agregada no card
      expect(find.textContaining('4,5'), findsNothing);
      expect(find.textContaining('Média'), findsNothing);
      expect(find.textContaining('Carne de sol perfeita'), findsOneWidget);
      expect(
        find.text('— Beto · há 2 h'),
        findsOneWidget,
        reason: 'citação traz autor e tempo próprios',
      );
      // avatares com a inicial de quem foi
      expect(find.text('B'), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
    },
  );

  testWidgets('FeedView: local sem foto mostra o fallback da categoria', (
    tester,
  ) async {
    final users = FakeUserRepository()..followingByUser['me'] = {'a'};
    final reviews = FakeReviewRepository()
      ..stored.add(review(authorId: 'a', placeId: 'x'));
    final vm = _feedVm(
      users: users,
      reviews: reviews,
      places: [place(id: 'x', category: 'Bar')],
    );
    await tester.pumpWidget(MaterialApp(home: FeedView(viewModel: vm)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('place-photo-fallback')), findsOneWidget);
  });

  testWidgets('PlacePhoto: URL quebrada cai no fallback sem erro visível', (
    tester,
  ) async {
    // No flutter_test toda requisição HTTP responde 400: simula o 404.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlacePhoto(
            place: place(
              photoUrl: 'https://upload.wikimedia.org/nao-existe.jpg',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('place-photo-fallback')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('FeedView: erro de rede mostra "Tentar de novo"', (tester) async {
    final users = FakeUserRepository()..failGetFollowing = true;
    final vm = _feedVm(users: users);
    await tester.pumpWidget(MaterialApp(home: FeedView(viewModel: vm)));
    await tester.pumpAndSettle();
    expect(find.text('Tentar de novo'), findsOneWidget);

    users.failGetFollowing = false;
    await tester.tap(find.text('Tentar de novo'));
    await tester.pumpAndSettle();
    expect(find.text('Encontrar pessoas'), findsOneWidget);
  });

  testWidgets('FeedView: pull-to-refresh recarrega mesmo com poucos cards', (
    tester,
  ) async {
    final users = FakeUserRepository()..followingByUser['me'] = {'a'};
    final reviews = FakeReviewRepository()
      ..stored.add(review(authorId: 'a', placeId: 'x'));
    final vm = _feedVm(users: users, reviews: reviews);
    await tester.pumpWidget(MaterialApp(home: FeedView(viewModel: vm)));
    await tester.pumpAndSettle();
    final before = users.getFollowingCalls;

    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(users.getFollowingCalls, before + 1);
  });

  testWidgets(
    'PlaceDetailView: foto grande e todas as avaliações dos amigos no local',
    (tester) async {
      _tallPhone(tester);
      final item = groupReviewsIntoFeed(
        [
          review(
            authorId: 'a',
            authorName: 'Ana',
            placeId: 'x',
            scores: Scores(food: 5, ambience: 2, service: 4),
            companion: Companion.familia,
            createdAt: DateTime.utc(2026, 9, 25, 23),
          ), // 20h do dia 25 em Natal: há 3 dias
          review(
            authorId: 'b',
            authorName: 'Beto',
            placeId: 'x',
            scores: Scores(food: 3, ambience: 4, service: 1),
            comment: 'Atendimento demorou',
            createdAt: DateTime.utc(2026, 9, 28, 14, 55),
          ), // há 5 min
        ],
        places: {'x': place(id: 'x', name: 'Mangai', neighborhood: 'Tirol')},
      ).single;

      await tester.pumpWidget(
        MaterialApp(
          home: PlaceDetailView(viewModel: detailVmFor(item, now: _now)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PlacePhoto), findsOneWidget);
      expect(find.text('Mangai'), findsWidgets);
      // eixos por avaliação
      expect(find.text('🍽️ 5'), findsOneWidget);
      expect(find.text('✨ 2'), findsOneWidget);
      expect(find.text('🤝 1'), findsOneWidget);
      expect(find.text('Atendimento demorou'), findsOneWidget);
      expect(find.text('Noite · Família · há 3 dias'), findsOneWidget);
      expect(find.textContaining('há 5 min'), findsOneWidget);
      expect(find.text('Ana'), findsOneWidget);
      expect(find.text('Beto'), findsOneWidget);
      // médias dos amigos: comida (5+3)/2, ambiente (2+4)/2, atendimento (4+1)/2
      expect(find.text('🍽️ 4'), findsOneWidget);
      expect(find.text('✨ 3'), findsOneWidget);
      expect(find.text('🤝 2,5'), findsOneWidget);
      expect(find.text('2 avaliações de amigos'), findsOneWidget);
      expect(find.text('Tirol · Restaurante · Natal'), findsOneWidget);
    },
  );

  testWidgets('PlaceDetailView: médias ignoram eixos ausentes e contam '
      'avaliações por eixo (F14)', (tester) async {
    _tallPhone(tester);
    final handle = tester.ensureSemantics();
    final item = groupReviewsIntoFeed(
      [
        review(authorId: 'a', placeId: 'x', scores: Scores(food: 4)),
        review(authorId: 'b', placeId: 'x', scores: Scores(food: 5)),
        review(authorId: 'c', placeId: 'x', scores: Scores(service: 3)),
      ],
      places: {'x': place(id: 'x', name: 'Mangai')},
    ).single;
    await tester.pumpWidget(
      MaterialApp(
        home: PlaceDetailView(viewModel: detailVmFor(item, now: _now)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('🍽️ 4,5'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Comida 4,5 de 5, 2 avaliações'),
      findsOneWidget,
    );
    expect(find.text('✨ sem notas'), findsOneWidget);
    expect(find.textContaining('✨ 0'), findsNothing);
    expect(
      find.bySemanticsLabel('Atendimento 3 de 5, 1 avaliação'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Ambiente sem notas'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('PlaceDetailView: avaliação antiga completa + nova parcial '
      '(F14)', (tester) async {
    _tallPhone(tester);
    final handle = tester.ensureSemantics();
    final item = groupReviewsIntoFeed(
      [
        review(
          authorId: 'a',
          placeId: 'x',
          scores: Scores(food: 2, ambience: 4, service: 5),
          createdAt: DateTime.utc(2026, 9, 1),
        ),
        review(
          authorId: 'b',
          placeId: 'x',
          scores: Scores(food: 5),
          createdAt: DateTime.utc(2026, 9, 28, 14),
        ),
      ],
      places: {'x': place(id: 'x', name: 'Mangai')},
    ).single;
    await tester.pumpWidget(
      MaterialApp(
        home: PlaceDetailView(viewModel: detailVmFor(item, now: _now)),
      ),
    );
    await tester.pumpAndSettle();
    // Comida (2+5)/2 nas 2; ambiente e atendimento só da antiga.
    expect(find.text('🍽️ 3,5'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Comida 3,5 de 5, 2 avaliações'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Ambiente 4 de 5, 1 avaliação'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Atendimento 5 de 5, 1 avaliação'),
      findsOneWidget,
    );
    // "(n)" visível só onde a contagem difere do total (2).
    expect(find.text(' (1)'), findsNWidgets(2));
    expect(find.text(' (2)'), findsNothing);
    handle.dispose();
  });

  testWidgets('PlaceDetailView: singular com 1 avaliação', (tester) async {
    _tallPhone(tester);
    final item = groupReviewsIntoFeed([
      review(authorId: 'a', placeId: 'x'),
    ]).single;
    await tester.pumpWidget(
      MaterialApp(
        home: PlaceDetailView(viewModel: detailVmFor(item, now: _now)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 avaliação de amigo'), findsOneWidget);
  });

  testWidgets('PlaceDetailView: crédito da foto e selo "ilustrativa"', (
    tester,
  ) async {
    _tallPhone(tester);
    FeedItem itemFor(Place p) =>
        groupReviewsIntoFeed([review(placeId: p.id)], places: {p.id: p}).single;

    await tester.pumpWidget(
      MaterialApp(
        home: PlaceDetailView(
          viewModel: detailVmFor(
            itemFor(
              place(
                id: 'x',
                photoUrl: 'https://f/x.jpg',
                photoAuthor: 'Beraldo Leal',
                photoLicense: 'CC BY 2.0',
                photoIllustrative: true,
              ),
            ),
            now: _now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Foto: Beraldo Leal · CC BY 2.0'), findsOneWidget);
    expect(find.text('ilustrativa'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: PlaceDetailView(
          viewModel: detailVmFor(
            itemFor(
              place(
                id: 'y',
                photoUrl: 'https://f/y.jpg',
                photoAuthor: 'Marcos',
                photoLicense: 'CC0',
              ),
            ),
            now: _now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Foto: Marcos · CC0'), findsOneWidget);
    expect(find.text('ilustrativa'), findsNothing);

    // sem foto: sem crédito
    await tester.pumpWidget(
      MaterialApp(
        home: PlaceDetailView(
          viewModel: detailVmFor(
            itemFor(place(id: 'z', photoAuthor: 'X')),
            now: _now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('photo-credit')), findsNothing);
  });

  test(
    'PlacePhoto: rótulo de acessibilidade honesto quando a foto é ilustrativa',
    () {
      expect(
        PlacePhoto.semanticLabelFor(place(name: 'Mangai')),
        'Foto de Mangai',
      );
      expect(
        PlacePhoto.semanticLabelFor(
          place(name: 'Mangai', photoIllustrative: true),
        ),
        startsWith('Imagem ilustrativa'),
      );
    },
  );

  group('placeSubtitle', () {
    test('junta bairro e categoria pulando partes vazias', () {
      expect(placeSubtitle('Tirol', 'Restaurante'), 'Tirol · Restaurante');
      expect(placeSubtitle('', 'Bar'), 'Bar');
      expect(placeSubtitle('  ', 'Bar'), 'Bar');
      expect(placeSubtitle('Tirol', ''), 'Tirol');
      expect(placeSubtitle('', ''), '');
    });
  });

  testWidgets(
    'FeedCard: sem bairro nem categoria, a linha de local não aparece',
    (tester) async {
      final item = groupReviewsIntoFeed([
        review(placeId: 'x', placeName: 'Sumiu'),
      ]).single;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FeedCard(item: item, now: _now),
            ),
          ),
        ),
      );
      expect(find.text('Sumiu'), findsOneWidget);
      expect(find.byIcon(Icons.place_outlined), findsNothing);
    },
  );

  testWidgets('FeedCard: rótulo "Abrir <local>" como botão', (tester) async {
    final handle = tester.ensureSemantics();
    final item = groupReviewsIntoFeed(
      [review(placeId: 'x')],
      places: {'x': place(id: 'x', name: 'Mangai')},
    ).single;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FeedCard(item: item, now: _now, onTap: () {}),
          ),
        ),
      ),
    );
    final node = tester.getSemantics(
      find.bySemanticsLabel(RegExp('^Abrir Mangai')),
    );
    expect(node.label, startsWith('Abrir Mangai'));
    expect(node, containsSemantics(isButton: true, hasTapAction: true));
    handle.dispose();
  });

  testWidgets('AxisScores: dica com o nome do eixo', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AxisScores.scores(Scores(food: 5, ambience: 4, service: 3)),
        ),
      ),
    );
    expect(find.byTooltip('Comida'), findsOneWidget);
    expect(find.byTooltip('Ambiente'), findsOneWidget);
    expect(find.byTooltip('Atendimento'), findsOneWidget);
  });

  group('AuthorAvatarStack', () {
    Widget host(List<({String id, String name})> authors) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: AuthorAvatarStack(authors: authors, ringColor: Colors.white),
        ),
      ),
    );

    testWidgets('4 autores: 3 iniciais e "+1"', (tester) async {
      await tester.pumpWidget(
        host([
          (id: 'a', name: 'Ana'),
          (id: 'b', name: 'Beto'),
          (id: 'c', name: 'Caio'),
          (id: 'd', name: 'Duda'),
        ]),
      );
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('C'), findsOneWidget);
      expect(find.text('D'), findsNothing);
      expect(find.text('+1'), findsOneWidget);
    });

    testWidgets('lista vazia não desenha nada', (tester) async {
      await tester.pumpWidget(host(const []));
      expect(find.byType(CircleAvatar), findsNothing);
    });

    test('excedente limitado a "+99"', () {
      expect(AuthorAvatarStack.overflowLabel(5), '+5');
      expect(AuthorAvatarStack.overflowLabel(99), '+99');
      expect(AuthorAvatarStack.overflowLabel(250), '+99');
    });
  });

  group('ReviewTile: linha do autor', () {
    Widget host(ReviewTile tile) => MaterialApp(
      home: Scaffold(body: Center(child: tile)),
    );

    testWidgets(
      'com onAuthorTap: avatar + nome são um alvo só, ≥48 dp, "Abrir perfil de Ana"',
      (tester) async {
        final handle = tester.ensureSemantics();
        var taps = 0;
        final r = review(id: 'r-ana', authorId: 'a', authorName: 'Ana');
        await tester.pumpWidget(
          host(ReviewTile(review: r, now: _now, onAuthorTap: () => taps++)),
        );
        final target = find.byKey(const ValueKey('review-author-r-ana'));
        expect(
          tester.getSize(target).height,
          greaterThanOrEqualTo(ReviewTile.minTapTarget),
        );
        final node = tester.getSemantics(
          find.bySemanticsLabel('Abrir perfil de Ana'),
        );
        expect(node, containsSemantics(isButton: true, hasTapAction: true));

        await tester.tap(find.text('Ana'));
        await tester.tap(find.text('A')); // avatar
        expect(taps, 2);
        handle.dispose();
      },
    );

    testWidgets('sem onAuthorTap: sem sublinhado nem semântica de botão', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          ReviewTile(
            review: review(id: 'r1', authorName: 'Ana'),
            now: _now,
          ),
        ),
      );
      final name = tester.widget<Text>(find.text('Ana'));
      expect(name.style?.decoration, isNot(TextDecoration.underline));
      expect(find.bySemanticsLabel('Abrir perfil de Ana'), findsNothing);
      expect(find.byKey(const ValueKey('review-author-r1')), findsNothing);
      handle.dispose();
    });
  });
}
