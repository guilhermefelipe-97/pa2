import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/data/repositories/auth_repository.dart';
import 'package:naarea/data/repositories/user_repository.dart';
import 'package:naarea/domain/models/scores.dart';
import 'package:naarea/routing/routes.dart';
import 'package:naarea/ui/core/theme.dart';
import 'package:naarea/ui/settings/settings_view.dart';
import 'package:provider/provider.dart';
import '../support/app_harness.dart';
import '../support/builders.dart';
import '../support/fakes.dart';

Future<void> _fonts() async {
  for (final (family, file) in [
    ('Epilogue', 'Epilogue'),
    ('Plus Jakarta Sans', 'PlusJakartaSans'),
  ]) {
    final loader = FontLoader(family);
    for (final weight in [400, 500, 600, 700]) {
      loader.addFont(rootBundle.load('assets/fonts/$file-$weight.ttf'));
    }
    await loader.load();
  }
}

class _LogoutAuth extends FakeAuthRepository {
  _LogoutAuth() : super(uid: 'me');
  final done = Completer<void>();
  int calls = 0;
  @override
  Future<void> signOut() async {
    calls++;
    await done.future;
  }
}

void main() {
  setUpAll(_fonts);
  testWidgets(
    'Configurações: sair bloqueia toque duplicado e falha permite tentar novamente',
    (tester) async {
      final auth = _LogoutAuth();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthRepository>.value(value: auth),
            Provider<UserRepository>.value(
              value: FakeUserRepository()..addUser('me', 'Bianca'),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const SettingsView(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('settings-sign-out')),
        200,
      );
      await tester.tap(find.byKey(const Key('settings-sign-out')));
      await tester.pump();
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('settings-sign-out')))
            .onPressed,
        isNull,
      );
      expect(auth.calls, 1);
      auth.done.completeError(StateError('rede'));
      await tester.pumpAndSettle();
      expect(
        find.text('Não foi possível sair. Tente de novo.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('settings-sign-out')))
            .onPressed,
        isNotNull,
      );
      expect(auth.currentUserId, 'me');
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets('Tema real: rotas e ações em 320dp com fonte ${scale}x', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final now = DateTime.utc(2026, 10, 31, 15);
      final p = place(name: 'Café de bairro');
      final users = FakeUserRepository()
        ..addUser('me', 'Bianca Ferreira')
        ..addUser('ana', 'Ana Silva')
        ..followingByUser['me'] = {'ana'};
      final reviews = FakeReviewRepository()
        ..stored.add(
          review(
            authorId: 'ana',
            authorName: 'Ana Silva',
            placeName: p.name,
            createdAt: now.subtract(const Duration(hours: 2)),
            scores: Scores(food: 5, ambience: 4, service: 5),
            comment: 'Café e conversa entre amigos.',
          ),
        );
      final app = await pumpApp(
        tester,
        users: users,
        reviews: reviews,
        places: [p],
        theme: AppTheme.light(),
        textScale: scale,
        clock: () => now,
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.byKey(const Key('save-p1')), 200);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-p1')));
      await tester.pumpAndSettle();
      expect(app.saved.byUser['me'], contains('p1'));
      expect(app.router.routeInformationProvider.value.uri.path, Routes.feed);
      app.router.go(Routes.person('me'));
      await tester.pumpAndSettle();
      expect(find.text('Você'), findsOneWidget);
      expect(find.text('Bianca Ferreira'), findsOneWidget);
      await tester.tap(find.byKey(const Key('profile-tab-2')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Suas listas'), findsOneWidget);
      app.router.go(Routes.settings);
      await tester.pumpAndSettle();
      expect(find.text('Bianca Ferreira'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
      app.auth.restoreSession('ana');
      await tester.pumpAndSettle();
      expect(find.text('Bianca Ferreira'), findsNothing);
      expect(find.text('Ana Silva'), findsOneWidget);
      app.router.go(Routes.placeDetail(p.id), extra: p);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      app.router.go(Routes.reviewFor(p.id), extra: p);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('axis-food-4')),
        200,
      );
      await tester.tap(find.byKey(const Key('axis-food-4')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('review-submit')),
        200,
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('review-submit')), findsOneWidget);
    });
  }

  testWidgets('Capturas Flutter com fontes locais e tema real', (tester) async {
    const output = String.fromEnvironment('STITCH_CAPTURE_DIR');
    if (output.isEmpty) return;
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    final now = DateTime.utc(2026, 10, 31, 15);
    final p = place(
      name: 'Café da Praça',
      category: 'Cafeteria',
      neighborhood: 'Tirol',
    );
    final users = FakeUserRepository()
      ..addUser('me', 'Bianca Ferreira')
      ..addUser('ana', 'Ana Silva')
      ..followingByUser['me'] = {'ana'};
    final reviews = FakeReviewRepository()
      ..stored.add(
        review(
          authorId: 'ana',
          authorName: 'Ana Silva',
          placeName: p.name,
          createdAt: now.subtract(const Duration(hours: 2)),
          scores: Scores(food: 5, ambience: 4, service: 5),
          comment: 'Um café tranquilo para conversar.',
        ),
      );
    final app = await pumpApp(
      tester,
      users: users,
      reviews: reviews,
      places: [p],
      theme: AppTheme.light(),
      captureKey: key,
      clock: () => now,
    );
    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final raster = await boundary.toImage(pixelRatio: 1);
      final bytes = await raster.toByteData(format: ui.ImageByteFormat.png);
      await tester.runAsync(() async {
        await Directory(output).create(recursive: true);
        await File(
          '$output/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
      });
      raster.dispose();
    }

    await capture('feed');
    app.router.go(Routes.person('me'));
    await capture('perfil');
    app.router.go(Routes.settings);
    await capture('configuracoes');
    app.router.go(Routes.placeDetail(p.id), extra: p);
    await capture('ficha');
    app.router.go(Routes.reviewFor(p.id), extra: p);
    await capture('formulario');
    expect(tester.takeException(), isNull);
  });
}
