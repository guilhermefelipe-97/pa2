import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:naarea/data/repositories/auth_repository.dart';
import 'package:naarea/data/repositories/place_repository.dart';
import 'package:naarea/data/repositories/review_repository.dart';
import 'package:naarea/data/repositories/user_repository.dart';
import 'package:naarea/domain/feed.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/routing/router.dart';
import 'package:naarea/routing/routes.dart';
import 'package:naarea/ui/feed/feed_view.dart';
import 'package:naarea/ui/place/place_detail_view.dart';
import 'package:naarea/ui/review/place_picker_view.dart';
import 'package:naarea/ui/review/review_view.dart';
import 'package:provider/provider.dart';

import '../support/builders.dart';
import '../support/fakes.dart';

const _mangai = Place(id: 'mangai', name: 'Mangai', category: 'Restaurante', neighborhood: 'Tirol', city: 'Natal');

Future<GoRouter> _pumpApp(WidgetTester tester, {String? uid = 'me'}) async {
  final users = FakeUserRepository()..addUser('me', 'Eu');
  final auth = FakeAuthRepository(uid: uid, users: users);
  final router = buildRouter(auth);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthRepository>.value(value: auth),
      Provider<UserRepository>.value(value: users),
      Provider<PlaceRepository>.value(value: FakePlaceRepository([_mangai])),
      Provider<ReviewRepository>.value(value: FakeReviewRepository()),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('sub-rota de avaliação sem o Place (extra) volta para a escolha de local', (tester) async {
    final router = await _pumpApp(tester);
    router.go(Routes.reviewFor('mangai'));
    await tester.pumpAndSettle();

    expect(find.byType(PlacePickerView), findsOneWidget);
    expect(find.byType(ReviewView), findsNothing);
    expect(router.routerDelegate.currentConfiguration.uri.path, Routes.pickPlace);
  });

  testWidgets('sub-rota de avaliação com o Place abre a tela de avaliação', (tester) async {
    final router = await _pumpApp(tester);
    router.go(Routes.reviewFor('mangai'), extra: _mangai);
    await tester.pumpAndSettle();

    expect(find.byType(ReviewView), findsOneWidget);
    expect(find.text('Mangai'), findsOneWidget);
  });

  testWidgets('deslogado cai no login', (tester) async {
    final router = await _pumpApp(tester, uid: null);
    expect(router.routerDelegate.currentConfiguration.uri.path, Routes.login);
    expect(find.text('Entrar'), findsOneWidget);
  });

  testWidgets('detalhe do local aberto por URL sem dados (extra) volta ao feed', (tester) async {
    final router = await _pumpApp(tester);
    router.go(Routes.placeDetail('mangai'));
    await tester.pumpAndSettle();

    expect(find.byType(PlaceDetailView), findsNothing);
    expect(find.byType(FeedView), findsOneWidget);
    expect(router.routerDelegate.currentConfiguration.uri.path, Routes.feed);
  });

  testWidgets('detalhe do local com o FeedItem abre a tela de detalhe', (tester) async {
    final router = await _pumpApp(tester);
    final item = groupReviewsIntoFeed(
      [review(authorId: 'a', authorName: 'Ana', placeId: 'mangai', placeName: 'Mangai')],
      places: {'mangai': _mangai},
    ).single;
    router.go(Routes.placeDetail('mangai'), extra: item);
    await tester.pumpAndSettle();

    expect(find.byType(PlaceDetailView), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget);
  });

  testWidgets('tocar no card do feed abre o detalhe do local', (tester) async {
    final users = FakeUserRepository()
      ..addUser('me', 'Eu')
      ..followingByUser['me'] = {'a'};
    final reviews = FakeReviewRepository()
      ..stored.add(review(authorId: 'a', authorName: 'Ana', placeId: 'mangai', placeName: 'Mangai'));
    final auth = FakeAuthRepository(uid: 'me', users: users);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthRepository>.value(value: auth),
        Provider<UserRepository>.value(value: users),
        Provider<PlaceRepository>.value(value: FakePlaceRepository([_mangai])),
        Provider<ReviewRepository>.value(value: reviews),
      ],
      child: MaterialApp.router(routerConfig: buildRouter(auth)),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mangai'));
    await tester.pumpAndSettle();
    // push não reflete na URI do go_router (optionURLReflectsImperativeAPIs).
    expect(find.byType(PlaceDetailView), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget);
  });
}
