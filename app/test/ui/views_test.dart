import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/feed.dart';
import 'package:naarea/domain/models/companion.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/domain/models/scores.dart';
import 'package:naarea/ui/feed/feed_view.dart';
import 'package:naarea/ui/feed/feed_view_model.dart';
import 'package:naarea/ui/feed/widgets/author_avatar.dart';
import 'package:naarea/ui/feed/widgets/feed_card.dart';
import 'package:naarea/ui/feed/widgets/place_photo.dart';
import 'package:naarea/ui/place/place_detail_view.dart';
import 'package:naarea/ui/review/review_view.dart';
import 'package:naarea/ui/review/review_view_model.dart';

import '../support/builders.dart';
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
);

/// Tela de celular alta (412x2000 dp) para as listas preguiçosas construírem
/// tudo o que o teste procura.
void _tallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(412, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('ReviewView: Enviar só habilita com os 3 eixos', (tester) async {
    _tallPhone(tester);
    final users = FakeUserRepository()..addUser('me', 'Eu');
    final vm = ReviewViewModel(
      place: const Place(
        id: 'x',
        name: 'Mangai',
        category: 'Restaurante',
        neighborhood: 'Tirol',
        city: 'Natal',
      ),
      authRepository: FakeAuthRepository(uid: 'me'),
      userRepository: users,
      reviewRepository: FakeReviewRepository(),
    );
    await tester.pumpWidget(MaterialApp(home: ReviewView(viewModel: vm)));

    FilledButton submit() =>
        tester.widget<FilledButton>(find.byKey(const Key('review-submit')));
    expect(submit().onPressed, isNull);

    vm
      ..setFood(4)
      ..setAmbience(4);
    await tester.pump();
    expect(submit().onPressed, isNull);

    vm.setService(4);
    await tester.pump();
    expect(submit().onPressed, isNotNull);
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
    'FeedView: card com bairro, quem foi, média dos eixos, comentário mais recente e tempo relativo',
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
      expect(find.text('Beto e Ana foram aqui'), findsOneWidget);
      expect(find.text('🍽️ 4,5'), findsOneWidget);
      expect(find.text('✨ 2,5'), findsOneWidget);
      expect(find.text('🤝 4,5'), findsOneWidget);
      expect(find.textContaining('Carne de sol perfeita'), findsOneWidget);
      expect(
        find.text('— Beto · há 2 h'),
        findsOneWidget,
        reason: 'citação traz autor e tempo próprios',
      );
      expect(find.text('Manhã · há 2 h'), findsOneWidget);
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
          home: PlaceDetailView(item: item, now: () => _now),
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

  testWidgets('PlaceDetailView: singular com 1 avaliação', (tester) async {
    _tallPhone(tester);
    final item = groupReviewsIntoFeed([
      review(authorId: 'a', placeId: 'x'),
    ]).single;
    await tester.pumpWidget(
      MaterialApp(
        home: PlaceDetailView(item: item, now: () => _now),
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
          item: itemFor(
            place(
              id: 'x',
              photoUrl: 'https://f/x.jpg',
              photoAuthor: 'Beraldo Leal',
              photoLicense: 'CC BY 2.0',
              photoIllustrative: true,
            ),
          ),
          now: () => _now,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Foto: Beraldo Leal · CC BY 2.0'), findsOneWidget);
    expect(find.text('ilustrativa'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: PlaceDetailView(
          item: itemFor(
            place(
              id: 'y',
              photoUrl: 'https://f/y.jpg',
              photoAuthor: 'Marcos',
              photoLicense: 'CC0',
            ),
          ),
          now: () => _now,
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
          item: itemFor(place(id: 'z', photoAuthor: 'X')),
          now: () => _now,
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

  testWidgets(
    'FeedCard: rótulo "Abrir <local>" como botão e dica com o nome do eixo',
    (tester) async {
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
      expect(find.byTooltip('Comida'), findsOneWidget);
      expect(find.byTooltip('Ambiente'), findsOneWidget);
      expect(find.byTooltip('Atendimento'), findsOneWidget);
      handle.dispose();
    },
  );

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
}
