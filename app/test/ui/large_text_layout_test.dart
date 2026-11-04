import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/routing/routes.dart';
import 'package:naarea/ui/core/theme.dart';

import '../support/app_harness.dart';
import '../support/fakes.dart';
import '../support/place_gallery_fakes.dart';
import '../support/profile_edit_fakes.dart';
import 'stitch_theme_test.dart' show loadStitchFonts;

/// Celular comum com fonte do sistema aumentada e barra de status: as telas
/// principais não podem estourar nem ter ícones da barra superior um em cima
/// do outro. Com `--dart-define=LAYOUT_CAPTURE_DIR=<pasta>` salva as imagens.
void main() {
  const place = Place(
    id: 'p1',
    name: 'Restaurante com um nome bem comprido da Ribeira',
    category: 'Restaurante',
    neighborhood: 'Ribeira',
    city: 'Natal',
    lat: -5.78,
    lng: -35.2,
  );

  final screens = <String, String>{
    'amigos': Routes.feed,
    'perto': Routes.nearby,
    'quero-ir': Routes.saved,
    'pessoas': Routes.people,
    'perfil': '/perfil',
    'editar-perfil': Routes.editProfile,
    'configuracoes': Routes.settings,
    'local': Routes.placeDetail(place.id),
    'meus-estabelecimentos': '/meus-estabelecimentos',
  };

  setUpAll(() async {
    if (const String.fromEnvironment('LAYOUT_CAPTURE_DIR').isNotEmpty) {
      await loadStitchFonts();
    }
  });

  for (final MapEntry(key: name, value: route) in screens.entries) {
    testWidgets('fonte grande + barra de status: $name sem sobreposição', (
      tester,
    ) async {
      const capture = String.fromEnvironment('LAYOUT_CAPTURE_DIR');
      tester.view
        ..physicalSize = const Size(360, 760)
        ..devicePixelRatio = 1
        ..padding = const FakeViewPadding(top: 32);
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      final users = FakeUserRepository()..addUser('me', 'Maria Eduarda');
      final media = FakeProfileMedia();
      final owners = FakeOwnerRepository()..owners['p1'] = 'outra';
      final app = await pumpApp(
        tester,
        users: users,
        places: [place],
        theme: AppTheme.light(),
        textScale: 1.3,
        captureKey: key,
        owners: owners,
        profileMedia: media,
        profileEditor: FakeProfileEditor(users, media),
        account: FakeAccountRepository(),
        gallery: FakePlacePhotoRepository(),
        galleryPicker: FakePlacePhotoPicker(),
      );
      app.router.go(route);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Botões da faixa de cima (barra do app e o que estiver logo abaixo
      // dela) nunca se cruzam.
      final top = MediaQuery.paddingOf(
        tester.element(find.byType(Scaffold).last),
      ).top;
      final buttons = [
        for (final e in find.byType(IconButton).evaluate())
          if (tester.getRect(find.byWidget(e.widget)).top < top + 80)
            tester.getRect(find.byWidget(e.widget)),
      ];
      for (var i = 0; i < buttons.length; i++) {
        for (var j = i + 1; j < buttons.length; j++) {
          final overlap = buttons[i].intersect(buttons[j]);
          expect(
            overlap.width > 1 && overlap.height > 1,
            isFalse,
            reason: '$name: ${buttons[i]} cruza ${buttons[j]}',
          );
        }
      }

      if (capture.isNotEmpty) {
        await tester.pump(const Duration(milliseconds: 800));
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final raster = await boundary.toImage(pixelRatio: 1);
          final bytes = await raster.toByteData(format: ui.ImageByteFormat.png);
          await Directory(capture).create(recursive: true);
          await File(
            '$capture/$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          raster.dispose();
        });
      }
    });
  }
}
