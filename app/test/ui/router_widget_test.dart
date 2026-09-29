import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:naarea/data/repositories/auth_repository.dart';
import 'package:naarea/data/repositories/place_repository.dart';
import 'package:naarea/data/repositories/review_repository.dart';
import 'package:naarea/data/repositories/user_repository.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/routing/router.dart';
import 'package:naarea/routing/routes.dart';
import 'package:naarea/ui/review/place_picker_view.dart';
import 'package:naarea/ui/review/review_view.dart';
import 'package:provider/provider.dart';

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
}
