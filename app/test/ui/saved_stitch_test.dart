import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/data/repositories/owner_workspace_repository.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/routing/routes.dart';
import 'package:naarea/ui/core/theme.dart';
import '../support/app_harness.dart';
import '../support/fakes.dart';
import '../support/owner_workspace_fake.dart';
import '../support/preview_http.dart';
import 'stitch_theme_test.dart' show loadStitchFonts;

const places = [
  Place(
    id: 'a',
    name: 'Cobre & Grão Espresso',
    category: 'Cafeteria especial',
    neighborhood: 'Tirol',
    city: 'Natal',
    lat: -5.81,
    lng: -35.20,
    photoUrl: 'https://preview.invalid/1',
  ),
  Place(
    id: 'b',
    name: 'Bistrô Botanique',
    category: 'Bistrô contemporâneo',
    neighborhood: 'Tirol',
    city: 'Natal',
    photoUrl: 'https://preview.invalid/2',
  ),
  Place(
    id: 'c',
    name: 'Torrefação Nuvem',
    category: 'Café e padaria',
    neighborhood: 'Petrópolis',
    city: 'Natal',
    photoUrl: 'https://preview.invalid/1',
  ),
  Place(
    id: 'd',
    name: 'Natural Cave Bar',
    category: 'Bar',
    neighborhood: 'Tirol',
    city: 'Natal',
    photoUrl: 'https://preview.invalid/2',
  ),
];
void main() {
  setUpAll(loadStitchFonts);
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'Quero ir: contador discreto, botão preenchido, categoria sem emoji e criação com fonte $scale',
      (tester) async {
        const output = String.fromEnvironment('STITCH_CAPTURE_DIR');
        tester.view.physicalSize = Size(
          output.isNotEmpty && scale == 1 ? 390 : 320,
          850,
        );
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        if (output.isNotEmpty && scale == 1) {
          final photos = await tester.runAsync(
            () async => <String, List<int>>{
              '/1': await File('$output/venue-reference-1.jpg').readAsBytes(),
              '/2': await File('$output/venue-reference-2.jpg').readAsBytes(),
            },
          );
          debugNetworkImageHttpClientProvider = () =>
              PreviewPhotoClient(photos!);
          addTearDown(() {
            debugNetworkImageHttpClientProvider = null;
            imageCache.clear();
          });
        }
        final now = DateTime(2026, 11, 1, 12), saved = FakeSavedRepository();
        for (final (i, p) in places.indexed) {
          saved.seed('me', p.id, now.subtract(Duration(minutes: i)));
        }
        final lists = FakeListsRepository(saved: saved)
          ..seed(
            'me',
            'cafes',
            'Cafés para conhecer',
            emoji: '☕',
            placeIds: ['a', 'c'],
          );
        final ratings = FakeOwnerWorkspace();
        for (final (i, p) in places.indexed) {
          ratings.summaries[p.id] = OwnerPlaceSummary(
            reviews: 10 + i,
            unanswered: 0,
            rating: [4.9, 4.8, 4.7, 4.9][i],
          );
        }
        final key = GlobalKey();
        final app = await pumpApp(
          tester,
          places: places,
          saved: saved,
          lists: lists,
          ownerWorkspace: ratings,
          clock: () => now,
          theme: AppTheme.light(),
          textScale: scale,
          captureKey: key,
          location: FakeLocationService(
            position: (lat: -5.81, lng: -35.20),
            granted: true,
          ),
        );
        app.router.go(Routes.saved);
        await tester.pumpAndSettle();
        final count = tester.widget<Text>(find.byKey(const Key('saved-count')));
        expect(count.data, '(4 salvos)');
        expect(count.style!.fontSize, 12);
        expect(count.style!.fontWeight, FontWeight.w400);
        final button = tester.widget<FilledButton>(
          find.byKey(const Key('saved-new-list')),
        );
        expect(
          button.style!.backgroundColor!.resolve({}),
          isNot(Colors.transparent),
        );
        expect(find.text('☕'), findsNothing);
        expect(find.byIcon(Icons.local_cafe_outlined), findsWidgets);
        expect(find.text('★ 4,9'), findsWidgets);
        expect(tester.takeException(), isNull);
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

        await capture('quero-ir-listas-validacao');
        await tester.tap(find.byKey(const Key('saved-new-list')));
        await tester.pumpAndSettle();
        expect(find.text('Título'), findsOneWidget);
        expect(find.text('Categoria sugerida (opcional)'), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('list-name-field')),
          'Cafés no fim de semana',
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('list-emoji-☕')));
        await tester.tap(find.byKey(const Key('list-emoji-☕')));
        await tester.pumpAndSettle();
        await capture('nova-lista-modal-validacao');
        await tester.ensureVisible(find.byKey(const Key('list-name-submit')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('list-name-submit')));
        await tester.pumpAndSettle();
        expect(
          lists.byUser['me']!.values.any(
            (l) => l.name == 'Cafés no fim de semana' && l.emoji == '☕',
          ),
          true,
        );
        expect(saved.byUser['me']!.length, 4);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        app.router.dispose();
        debugNetworkImageHttpClientProvider = null;
        imageCache.clear();
      },
    );
  }
}
