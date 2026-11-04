import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:naarea/routing/routes.dart';
import 'package:naarea/ui/core/theme.dart';
import '../support/app_harness.dart';
import '../support/builders.dart';
import '../support/place_gallery_fakes.dart';
import 'package:naarea/data/repositories/place_photo_repository.dart';

Future<void> pickAndProcess(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('place-photos-pick')));
  await tester.pump();
  for (
    var i = 0;
    i < 100 && find.byType(LinearProgressIndicator).evaluate().isNotEmpty;
    i++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'remove foto própria após confirmação e preserva foto de outra pessoa',
    (tester) async {
      final gallery = FakePlacePhotoRepository();
      for (final id in ['me', 'ana']) {
        gallery.photos.add(
          PlaceGalleryPhoto(
            id: id,
            authorId: id,
            authorName: id,
            createdAt: DateTime.utc(2026, 11, 1),
            jpeg: img.encodeJpg(img.Image(width: 16, height: 16)),
          ),
        );
      }
      final app = await pumpApp(
        tester,
        places: [place()],
        gallery: gallery,
        galleryPicker: FakePlacePhotoPicker(),
      );
      app.router.go(Routes.placeDetail('p1'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remover minha foto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(gallery.photos, hasLength(2));
      await tester.tap(find.byTooltip('Remover minha foto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remover'));
      await tester.pumpAndSettle();
      expect(gallery.photos.single.authorId, 'ana');
      expect(find.byTooltip('Remover minha foto'), findsNothing);
      expect(find.text('1/1'), findsOneWidget);
    },
  );
  testWidgets(
    'selecionar várias fotos, remover antes de enviar e ver contador na capa',
    (tester) async {
      final gallery = FakePlacePhotoRepository();
      final picker = FakePlacePhotoPicker()
        ..selected = [
          img.encodeJpg(img.Image(width: 16, height: 16)),
          img.encodeJpg(img.Image(width: 20, height: 20)),
        ];
      final app = await pumpApp(
        tester,
        places: [place()],
        gallery: gallery,
        galleryPicker: picker,
      );
      app.router.go(Routes.placeDetail('p1'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('place-add-photos')));
      await tester.pumpAndSettle();
      await pickAndProcess(tester);
      expect(find.text('Enviar 2 fotos'), findsOneWidget);
      await tester.tap(find.byTooltip('Remover foto 2'));
      await tester.pumpAndSettle();
      expect(find.text('Enviar 1 foto'), findsOneWidget);
      await tester.tap(find.byKey(const Key('place-photos-save')));
      await tester.pumpAndSettle();
      expect(gallery.photos, hasLength(1));
      expect(gallery.photos.single.authorId, 'me');
      expect(find.text('1/1'), findsOneWidget);
      await tester.tap(find.byKey(const Key('place-add-photos')));
      await tester.pumpAndSettle();
      await pickAndProcess(tester);
      await tester.tap(find.byKey(const Key('place-photos-save')));
      await tester.pumpAndSettle();
      expect(gallery.photos, hasLength(3));
      expect(find.text('1/3'), findsOneWidget);
      await tester.tap(find.byTooltip('Próxima foto'));
      await tester.pumpAndSettle();
      expect(find.text('2/3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('falha ao enviar mantém fotos para tentar novamente', (
    tester,
  ) async {
    final gallery = FakePlacePhotoRepository()..failWrite = true;
    final picker = FakePlacePhotoPicker()
      ..selected = [img.encodeJpg(img.Image(width: 16, height: 16))];
    final app = await pumpApp(
      tester,
      places: [place()],
      gallery: gallery,
      galleryPicker: picker,
    );
    app.router.go(Routes.placeDetail('p1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('place-add-photos')));
    await tester.pumpAndSettle();
    await pickAndProcess(tester);
    await tester.tap(find.byKey(const Key('place-photos-save')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Suas fotos continuam selecionadas'),
      findsOneWidget,
    );
    expect(find.text('Enviar 1 foto'), findsOneWidget);
    gallery.failWrite = false;
    await tester.tap(find.byKey(const Key('place-photos-save')));
    await tester.pumpAndSettle();
    expect(gallery.photos, hasLength(1));
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets('Avaliar e Quero ir cabem lado a lado em 320dp fonte $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final app = await pumpApp(
        tester,
        places: [place()],
        theme: AppTheme.light(),
        textScale: scale,
      );
      app.router.go(Routes.placeDetail('p1'));
      await tester.pumpAndSettle();
      final review = find.byKey(const Key('place-review'));
      final save = find.byKey(const Key('save-p1'));
      await tester.scrollUntilVisible(
        review,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        (tester.getCenter(review).dy - tester.getCenter(save).dy).abs(),
        lessThan(2),
      );
      expect(tester.getSize(review).width, tester.getSize(save).width);
      expect(tester.takeException(), isNull);
    });
  }
}
