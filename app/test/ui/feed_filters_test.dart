import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/routing/routes.dart';
import 'package:naarea/ui/core/theme.dart';
import 'package:naarea/ui/dietary/dietary_filter_panel.dart';
import 'package:naarea/ui/feed/feed_view.dart';
import '../support/app_harness.dart';
import '../support/builders.dart';
import '../support/fakes.dart';
import '../support/preview_http.dart';
import 'stitch_theme_test.dart' show loadStitchFonts;

void main() {
  setUpAll(loadStitchFonts);
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'filtros no feed aplicam tags reais e cancelamento mantém preferências; fonte $scale',
      (tester) async {
        const output = String.fromEnvironment('STITCH_CAPTURE_DIR');
        tester.view.physicalSize = Size(
          scale == 1 && output.isNotEmpty ? 390 : 320,
          850,
        );
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        if (output.isNotEmpty && scale == 1) {
          final bytes = await tester.runAsync(
            () => File('$output/venue-reference-1.jpg').readAsBytes(),
          );
          debugNetworkImageHttpClientProvider = () =>
              PreviewPhotoClient({'/photo': bytes!});
          addTearDown(() => debugNetworkImageHttpClientProvider = null);
        }
        final users = FakeUserRepository()
          ..addUser('me', 'Bianca')
          ..addUser('ana', 'Ana Silva')
          ..addUser('b', 'Bruno')
          ..addUser('c', 'Camila')
          ..followingByUser['me'] = {'ana'};
        final reviews = FakeReviewRepository();
        final now = DateTime(2026, 11, 1, 12);
        for (final id in ['ana', 'b', 'c']) {
          reviews.stored.add(
            review(
              authorId: id,
              authorName: users.profiles[id]!.displayName,
              placeId: 'p1',
              placeName: 'Café da Praça',
              tags: ['vegetariano', 'integral'],
              createdAt: now,
              comment: id == 'ana'
                  ? 'Café tranquilo e boas opções para o almoço.'
                  : null,
            ),
          );
        }
        reviews.stored.add(
          review(
            authorId: 'ana',
            authorName: 'Ana Silva',
            placeId: 'p2',
            placeName: 'Bistrô do Bairro',
            createdAt: now,
          ),
        );
        final preferences = FakeDietaryRepository();
        final key = GlobalKey();
        final app = await pumpApp(
          tester,
          users: users,
          reviews: reviews,
          dietary: preferences,
          places: [
            place(
              id: 'p1',
              name: 'Café da Praça',
              neighborhood: 'Tirol',
              photoUrl: output.isEmpty ? null : 'https://preview.invalid/photo',
            ),
            place(id: 'p2', name: 'Bistrô do Bairro'),
          ],
          theme: AppTheme.light(),
          textScale: scale,
          captureKey: key,
          clock: () => now,
        );
        expect(find.text('Café da Praça'), findsOneWidget);
        expect(
          tester
              .widget<FeedView>(find.byType(FeedView))
              .viewModel
              .items
              .map((item) => item.placeId),
          containsAll(['p1', 'p2']),
        );
        final filter = find.byKey(const Key('feed-filters'));
        expect(filter.hitTestable(), findsOneWidget);
        await tester.tap(filter);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.byKey(const Key('food-filter-vegetariano')), 150,
          scrollable: find.descendant(of: find.byType(DietaryFilterPanel), matching: find.byType(Scrollable)).first);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('food-filter-vegetariano')));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const Key('food-filter-integral')),
          150,
          scrollable: find
              .descendant(
                of: find.byType(DietaryFilterPanel),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.ensureVisible(find.byKey(const Key('food-filter-integral')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('food-filter-integral')));
        await tester.pumpAndSettle();
        await tester.drag(
          find.descendant(
            of: find.byType(DietaryFilterPanel),
            matching: find.byType(ListView),
          ),
          const Offset(0, 2000),
        );
        await tester.pumpAndSettle();
        expect(find.text('2 tags selecionadas'), findsOneWidget);
        expect(preferences.stored['me'], isNull);
        Future<void> capture(String name) async {
          if (output.isEmpty || scale != 1) return;
          for (var i = 0; i < 3; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 100)),
            );
            await tester.pumpAndSettle();
          }
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final raster = await boundary.toImage();
            final bytes = await raster.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '$output/$name.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            raster.dispose();
          });
        }

        await capture('feed-filtros-painel-validacao');
        await tester.tap(find.byKey(const Key('food-filter-apply')));
        await tester.pumpAndSettle();
        expect(preferences.stored['me'], {'vegetariano', 'integral'});
        expect(find.byType(DietaryFilterPanel), findsNothing);
        expect(find.text('Café da Praça'), findsOneWidget);
        expect(find.text('Bistrô do Bairro'), findsNothing);
        await capture('feed-tags-aplicadas-validacao');
        await tester.tap(filter);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('food-filter-clear')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('food-filter-close')));
        await tester.pumpAndSettle();
        expect(preferences.stored['me'], {'vegetariano', 'integral'});
        app.router.go(Routes.settings);
        await tester.pumpAndSettle();
        expect(find.text('Perfil alimentar'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        app.router.dispose();
        debugNetworkImageHttpClientProvider = null;
        imageCache.clear();
      },
    );
  }
  testWidgets('erro de gravação mantém seleção e permite tentar novamente', (
    tester,
  ) async {
    final preferences = FakeDietaryRepository();
    final app = await pumpApp(tester, dietary: preferences);
    await tester.tap(find.byKey(const Key('feed-filters')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('food-filter-vegano')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('food-filter-vegano')));
    await tester.pumpAndSettle();
    preferences.fail = true;
    await tester.tap(find.byKey(const Key('food-filter-apply')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(DietaryFilterPanel),
        matching: find.text('Não foi possível salvar. Tente novamente.'),
      ),
      findsOneWidget,
    );
    preferences.fail = false;
    await tester.tap(find.byKey(const Key('food-filter-apply')));
    await tester.pumpAndSettle();
    expect(preferences.stored['me'], {'vegano'});
    expect(find.byType(DietaryFilterPanel), findsNothing);
    await tester.pumpWidget(const SizedBox());
    app.router.dispose();
  });
}
