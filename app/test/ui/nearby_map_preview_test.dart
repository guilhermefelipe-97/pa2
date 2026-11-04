import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/routing/routes.dart';
import 'package:naarea/ui/core/theme.dart';
import '../support/app_harness.dart';
import '../support/fakes.dart';

class _MapPreviewBinding extends LiveTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  const enabled = bool.fromEnvironment('LIVE_MAP_PREVIEW');
  if (!enabled) {
    test('prévia manual com ruas reais', () {}, skip: true);
    return;
  }
  final binding = _MapPreviewBinding();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  testWidgets('captura mapa com ruas reais', (tester) async {
    await binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => binding.setSurfaceSize(null));
    const output = String.fromEnvironment('STITCH_CAPTURE_DIR');
    await Directory('$output/map-cache').create(recursive: true);
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => Directory('$output/map-cache').absolute.path,
        );
    final sdkBin = File(
      Platform.resolvedExecutable,
    ).parent.parent.parent.parent.parent;
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        File(
          '${sdkBin.path}/cache/artifacts/material_fonts/materialicons-regular.otf',
        ).readAsBytes().then(ByteData.sublistView),
      );
    await icons.load();
    for (final pair in [
      ('Epilogue', 'Epilogue'),
      ('Plus Jakarta Sans', 'PlusJakartaSans'),
    ]) {
      final font = FontLoader(pair.$1);
      for (final weight in [400, 500, 600, 700]) {
        font.addFont(rootBundle.load('assets/fonts/${pair.$2}-$weight.ttf'));
      }
      await font.load();
    }
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    final app = await pumpApp(
      tester,
      captureKey: key,
      theme: AppTheme.light(),
      location: FakeLocationService(
        position: (lat: -5.8101, lng: -35.2001),
        granted: true,
      ),
      places: const [
        Place(
          id: 'cafe',
          name: 'Café da Praça',
          category: 'Cafeteria',
          neighborhood: 'Tirol',
          city: 'Natal',
          lat: -5.8100,
          lng: -35.2000,
        ),
      ],
    );
    app.router.go(Routes.nearby);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mapa'));
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      await tester.pump();
    }
    expect(find.text('Não foi possível carregar o mapa.'), findsNothing);
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final raster = await boundary.toImage(pixelRatio: 1);
    final bytes = await raster.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '$output/perto-mapa.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    raster.dispose();
    await tester.pumpWidget(const SizedBox());
    app.router.dispose();
  });
}
