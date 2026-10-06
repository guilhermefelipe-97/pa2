import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/data/services/location_service.dart';
import 'package:naarea/routing/routes.dart';
import 'package:naarea/ui/nearby/nearby_view.dart';
import 'package:naarea/ui/place/place_detail_view.dart';

import '../support/app_harness.dart';
import '../support/builders.dart';
import '../support/fakes.dart';
import '../support/geo_helpers.dart';

Finder _tab(String label) => find.descendant(
  of: find.byKey(const Key('app-nav')),
  matching: find.text(label),
);

final _places = [
  placeNear('perto80', 80, bearingDeg: 10, name: 'Tapiocaria 80'),
  placeNear('perto150', 150, bearingDeg: 120, name: 'Bar 150'),
  placeNear('perto240', 240, bearingDeg: 200, name: 'Camarões 240'),
  placeNear('perto290', 290, bearingDeg: 300, name: 'Pizzaria 290'),
  placeNear('fora', 301, bearingDeg: 45, name: 'Fora 301'),
];

Future<TestApp> _openNearby(
  WidgetTester tester, {
  List<dynamic> places = const [],
  FakeLocationService? location,
  FakeUserRepository? users,
  FakeReviewRepository? reviews,
}) async {
  final app = await pumpApp(
    tester,
    places: [...places.cast()],
    location: location,
    users: users,
    reviews: reviews,
  );
  await tester.tap(_tab('Perto'));
  await tester.pumpAndSettle();
  return app;
}

void main() {
  testWidgets('abas Amigos · Perto · Quero ir · Pessoas; Perto em 2º', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    final labels = tester
        .widgetList<NavigationDestination>(find.byType(NavigationDestination))
        .map((d) => d.label)
        .toList();
    expect(labels, ['Amigos', 'Perto', 'Quero ir', 'Pessoas']);
    // A aba só é montada (e a permissão só é vista) quando visitada.
    expect(app.location.hasPermissionCalls, 0);

    await tester.tap(_tab('Perto'));
    await tester.pumpAndSettle();
    expect(find.byType(NearbyView), findsOneWidget);
    expect(
      app.router.routerDelegate.currentConfiguration.uri.path,
      Routes.nearby,
    );
    expect(app.location.hasPermissionCalls, 1);
  });

  testWidgets(
    'primeira vez: explica, e só "Usar minha localização" pede a posição',
    (tester) async {
      final app = await _openNearby(
        tester,
        places: _places,
        location: FakeLocationService(position: pontaNegra),
      );
      expect(find.text(NearbyView.explainTitle), findsOneWidget);
      expect(app.location.locateCalls, 0);

      await tester.tap(find.text(NearbyView.useLocationLabel));
      await tester.pumpAndSettle();
      expect(app.location.locateCalls, 1);
      expect(find.text('Tapiocaria 80'), findsWidgets);
      expect(find.text('80 m · Restaurante'), findsWidgets);
      expect(find.text('Fora 301'), findsNothing);
    },
  );

  testWidgets(
    'AC: Bianca em Ponta Negra, 1 toque na Sugestão abre o lugar que a Ana avaliou',
    (tester) async {
      final users = FakeUserRepository()
        ..addUser('me', 'Bianca')
        ..addUser('ana', 'Ana')
        ..followingByUser['me'] = {'ana'};
      final reviews = FakeReviewRepository()
        ..stored.add(
          review(
            authorId: 'ana',
            authorName: 'Ana',
            placeId: 'perto240',
            placeName: 'Camarões 240',
          ),
        );
      final app = await _openNearby(
        tester,
        places: _places,
        users: users,
        reviews: reviews,
        location: FakeLocationService(position: pontaNegra, granted: true),
      );
      final card = find.byKey(const Key('nearby-suggestion'));
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text('Camarões 240')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('Ana foi aqui')),
        findsOneWidget,
      );
      // Na lista, o item também mostra quem foi.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('nearby-perto240')),
          matching: find.text('Ana foi aqui'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('nearby-suggestion-open')));
      await tester.pumpAndSettle();
      expect(find.byType(PlaceDetailView), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(PlaceDetailView),
          matching: find.text('Camarões 240'),
        ),
        findsWidgets,
      );
      expect(app.places.nearbyCalls, hasLength(1));
    },
  );

  testWidgets('AC: nada em 300 m → "Ampliar para 1 km" mostra até 1 km', (
    tester,
  ) async {
    final app = await _openNearby(
      tester,
      places: [placeNear('longe', 700, name: 'Longe 700')],
      location: FakeLocationService(position: pontaNegra, granted: true),
    );
    expect(find.text('Nada a 300 m'), findsOneWidget);
    await tester.tap(find.text('Ampliar para 1 km'));
    await tester.pumpAndSettle();
    expect(find.text('Longe 700'), findsWidgets);
    expect(find.text('700 m · Restaurante'), findsWidgets);
    expect(app.places.nearbyCalls, hasLength(2));
    // A sugestão foi recalculada (o único local).
    expect(find.byKey(const Key('nearby-suggestion')), findsOneWidget);
  });

  testWidgets('chips de raio refazem a consulta', (tester) async {
    await _openNearby(
      tester,
      places: _places,
      location: FakeLocationService(position: pontaNegra, granted: true),
    );
    expect(find.text('Fora 301'), findsNothing);
    await tester.tap(find.byKey(const Key('radius-1000')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Fora 301'),
      200,
      scrollable: find.descendant(
        of: find.byKey(const Key('nearby-list')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Fora 301'), findsWidgets);
  });

  testWidgets('item: marcador "Quero ir" e distância falada', (tester) async {
    final handle = tester.ensureSemantics();
    await _openNearby(
      tester,
      places: [placeNear('a', 120, name: 'Mangai')],
      location: FakeLocationService(position: pontaNegra, granted: true),
    );
    expect(find.byKey(const Key('save-a')), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'^Mangai, a 120 metros, Restaurante')),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('fora de Natal: "Ainda não temos lugares por aqui"', (
    tester,
  ) async {
    await _openNearby(
      tester,
      places: _places,
      location: FakeLocationService(
        position: (lat: -6.24, lng: -35.211),
        granted: true,
      ),
    );
    expect(find.text(NearbyView.outOfAreaMessage), findsOneWidget);
    expect(find.textContaining('Ampliar'), findsNothing);
  });

  testWidgets('rede falha: mensagem + "Tentar de novo"', (tester) async {
    final app = await pumpApp(
      tester,
      places: _places,
      location: FakeLocationService(position: pontaNegra, granted: true),
    );
    app.places.fail = true;
    await tester.tap(_tab('Perto'));
    await tester.pumpAndSettle();
    expect(find.text(NearbyView.loadErrorMessage), findsOneWidget);
    app.places.fail = false;
    await tester.tap(find.text(NearbyView.retryLabel));
    await tester.pumpAndSettle();
    expect(find.text('Tapiocaria 80'), findsWidgets);
  });

  group('permissão negada / GPS', () {
    testWidgets('negada: "Tentar de novo"', (tester) async {
      final location = FakeLocationService(position: pontaNegra)
        ..status = LocationStatus.denied;
      await _openNearby(tester, places: _places, location: location);
      await tester.tap(find.text(NearbyView.useLocationLabel));
      await tester.pumpAndSettle();
      expect(find.text(NearbyView.deniedMessage), findsOneWidget);

      location.status = LocationStatus.ok;
      await tester.tap(find.text(NearbyView.retryLabel));
      await tester.pumpAndSettle();
      expect(find.text('Tapiocaria 80'), findsWidgets);
    });

    testWidgets('negada para sempre: "Abrir configurações"', (tester) async {
      final location = FakeLocationService(position: pontaNegra)
        ..status = LocationStatus.deniedForever;
      await _openNearby(tester, places: _places, location: location);
      await tester.tap(find.text(NearbyView.useLocationLabel));
      await tester.pumpAndSettle();
      expect(find.text(NearbyView.deniedForeverMessage), findsOneWidget);
      await tester.tap(find.text(NearbyView.openSettingsLabel));
      await tester.pumpAndSettle();
      expect(location.openAppSettingsCalls, 1);
    });

    testWidgets('GPS desligado: "Ative a localização do aparelho"', (
      tester,
    ) async {
      final location = FakeLocationService(position: pontaNegra, granted: true)
        ..status = LocationStatus.serviceOff;
      await _openNearby(tester, places: _places, location: location);
      expect(find.text(NearbyView.serviceOffMessage), findsOneWidget);
      location.status = LocationStatus.ok;
      await tester.tap(find.text(NearbyView.retryLabel));
      await tester.pumpAndSettle();
      expect(find.text('Tapiocaria 80'), findsWidgets);
    });
  });

  group('plataformas', () {
    test('Android declara localização só em primeiro plano', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(manifest, contains('android.permission.ACCESS_COARSE_LOCATION'));
      expect(manifest, contains('android.permission.ACCESS_FINE_LOCATION'));
      expect(
        manifest,
        isNot(contains('android.permission.ACCESS_BACKGROUND_LOCATION')),
      );
    });

    test('iOS explica o uso em pt-BR, só "When In Use"', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      expect(plist, contains('NSLocationWhenInUseUsageDescription'));
      expect(plist, contains('não é guardada'));
      expect(
        plist,
        isNot(contains('NSLocationAlwaysAndWhenInUseUsageDescription')),
      );
    });
  });
}
