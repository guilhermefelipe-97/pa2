import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/data/services/location_service.dart';
import 'package:naarea/domain/geo.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/domain/open_status.dart';
import 'package:naarea/routing/routes.dart';
import 'package:naarea/ui/nearby/nearby_view.dart';
import 'package:naarea/ui/nearby/nearby_view_model.dart';
import 'package:naarea/ui/open/open_now_view_model.dart';

import '../support/app_harness.dart';
import '../support/fakes.dart';
import '../support/geo_helpers.dart';

/// 12/10/2030 às 20h40 em Natal.
final _now = DateTime.utc(2030, 10, 12, 23, 40);

DateTime _ago(int minutes) => _now.subtract(Duration(minutes: minutes));

/// O Mangai a 80 m de Ponta Negra.
final _mangai = placeNear('mangai', 80, name: 'Mangai');

class _Env {
  _Env({LatLng? position = pontaNegra, bool granted = true})
    : location = FakeLocationService(position: position, granted: granted) {
    users
      ..addUser('me', 'Toni')
      ..addUser('ana', 'Ana');
    reports.clock = () => _now;
  }

  final FakeLocationService location;
  final users = FakeUserRepository();
  final reports = FakeOpenReportRepository();
  final places = FakePlaceRepository([]);
  final auth = FakeAuthRepository(uid: 'me');

  OpenNowViewModel vm({String placeId = 'mangai'}) => OpenNowViewModel(
    placeId: placeId,
    openReportRepository: reports,
    authRepository: auth,
    userRepository: users,
    locationService: location,
    placeRepository: places,
    clock: () => _now,
  );
}

Future<OpenNowViewModel> _attached(_Env env, Place place) async {
  final vm = env.vm(placeId: place.id);
  vm.attach(place);
  await vm.load();
  return vm;
}

void main() {
  group('OpenNowViewModel (F20)', () {
    test('status: mais recente vence; longe (2 km) não relata', () async {
      final env = _Env(position: destination(pontaNegra, 2000, 180));
      env.reports
        ..add('mangai', open: false, at: _ago(120), authorName: 'Caio')
        ..add('mangai', open: true, at: _ago(20));
      final vm = await _attached(env, _mangai);
      expect(vm.statusLabel, 'Aberto · confirmado por Ana há 20 min');
      expect(vm.proximity, OpenProximity.far);
      expect(vm.canReport, isFalse);
    });

    test('a 80 m: relata "Sim" e vira "confirmado por você agora", com '
        'trava de 30 min', () async {
      final env = _Env();
      final vm = await _attached(env, _mangai);
      expect(vm.status, isNull);
      expect(vm.proximity, OpenProximity.near);
      expect(vm.canReport, isTrue);
      expect(await vm.submit(open: true), isTrue);
      final sent = env.reports.created.single;
      expect(sent.authorId, 'me');
      expect(sent.authorName, 'Toni');
      expect(sent.open, isTrue);
      expect(env.reports.createdNewPlaces.single, isNull);
      expect(vm.statusLabel, 'Aberto · confirmado por você agora');
      expect(
        vm.blockedLabel,
        'Você informou às 20h40. De novo a partir das 21h10.',
      );
      expect(vm.canReport, isFalse);
      // A releitura traz o mesmo relato: não conta duas vezes.
      await vm.load();
      expect(vm.statusLabel, 'Aberto · confirmado por você agora');
      expect(openStatusOf(env.reports.stored, _now)!.kind, OpenStatusKind.open);
    });

    test('divergente: Sim há 10 min e Não há 20 min', () async {
      final env = _Env();
      env.reports
        ..add('mangai', open: true, at: _ago(10))
        ..add('mangai', open: false, at: _ago(20), authorId: 'caio');
      final vm = await _attached(env, _mangai);
      expect(
        vm.statusLabel,
        'Informações divergentes · 2 relatos na última meia hora',
      );
    });

    test('expirado: último relato há 3 h 05 min = sem status', () async {
      final env = _Env();
      env.reports.add('mangai', open: true, at: _ago(185));
      final vm = await _attached(env, _mangai);
      expect(vm.status, isNull);
    });

    test('trava de 10 min atrás: desabilitado com a explicação', () async {
      final env = _Env();
      env.reports.lock('me', 'mangai', _ago(10));
      final vm = await _attached(env, _mangai);
      expect(vm.proximity, OpenProximity.near);
      expect(
        vm.blockedLabel,
        'Você informou às 20h30. De novo a partir das 21h.',
      );
      expect(vm.canReport, isFalse);
      expect(await vm.submit(open: false), isFalse);
      expect(env.reports.created, isEmpty);
    });

    test('sem permissão: nunca pede ao abrir; no toque pede e, negada, '
        'explica', () async {
      final env = _Env(granted: false)..location.status = LocationStatus.denied;
      final vm = await _attached(env, _mangai);
      expect(vm.proximity, OpenProximity.needsPermission);
      expect(env.location.locateCalls, 0);
      await vm.useMyLocation();
      expect(env.location.locateCalls, 1);
      expect(vm.proximity, OpenProximity.locationOff);
    });

    test('sem permissão: no toque concede e, perto, libera Sim/Não', () async {
      final env = _Env(granted: false);
      final vm = await _attached(env, _mangai);
      await vm.useMyLocation();
      expect(vm.proximity, OpenProximity.near);
      expect(vm.canReport, isTrue);
    });

    test('falha ao enviar: "Não foi possível enviar"', () async {
      final env = _Env();
      env.reports.createError = StateError('rede');
      final vm = await _attached(env, _mangai);
      expect(await vm.submit(open: true), isFalse);
      expect(vm.errorMessage, OpenNowViewModel.errorText);
      expect(vm.status, isNull);
    });

    test('falha na leitura dos relatos: status some, sem erro', () async {
      final env = _Env();
      env.reports.fetchError = StateError('rede');
      final vm = await _attached(env, _mangai);
      expect(vm.status, isNull);
      expect(vm.proximity, OpenProximity.near);
    });

    test('local descoberto (Photon): vai junto para nascer no batch', () async {
      final env = _Env();
      final discovered = Place(
        id: 'osm-n1',
        name: 'Bar do Zé',
        category: 'Bar',
        neighborhood: '',
        city: 'Natal',
        lat: _mangai.lat,
        lng: _mangai.lng,
        source: PlaceSource.osm,
        inCatalog: false,
        discovered: true,
      );
      final vm = await _attached(env, discovered);
      expect(await vm.submit(open: true), isTrue);
      expect(env.reports.createdNewPlaces.single?.id, 'osm-n1');
    });

    test('local sem coordenadas: nunca relata', () async {
      final env = _Env();
      const curated = Place(
        id: 'curado',
        name: 'Curado',
        category: 'Bar',
        neighborhood: '',
        city: 'Natal',
      );
      final vm = await _attached(env, curated);
      expect(vm.proximity, OpenProximity.none);
      expect(env.location.locateCalls, 0);
    });
  });

  group('detalhe (F20)', () {
    testWidgets('Ana confirmou: Toni a 2 km vê o status e não vê o botão', (
      tester,
    ) async {
      final reports = FakeOpenReportRepository()
        ..add('mangai', open: true, at: _ago(20));
      final app = await pumpApp(
        tester,
        places: [_mangai],
        openReports: reports,
        location: FakeLocationService(
          position: destination(pontaNegra, 2000, 180),
          granted: true,
        ),
        clock: () => _now,
      );
      app.router.go(Routes.placeDetail('mangai'));
      await tester.pumpAndSettle();
      expect(
        find.text('Aberto · confirmado por Ana há 20 min'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('open-yes')), findsNothing);
      expect(find.byKey(const Key('open-ask-location')), findsNothing);
      expect(
        find.bySemanticsLabel('Aberto agora, confirmado por Ana há 20 minutos'),
        findsOneWidget,
      );
    });

    testWidgets('a 80 m: "Sim" em 1 toque, status e trava na hora', (
      tester,
    ) async {
      final reports = FakeOpenReportRepository()..clock = () => _now;
      final app = await pumpApp(
        tester,
        places: [_mangai],
        openReports: reports,
        location: FakeLocationService(position: pontaNegra, granted: true),
        clock: () => _now,
      );
      app.router.go(Routes.placeDetail('mangai'));
      await tester.pumpAndSettle();
      expect(find.text(OpenNowViewModel.question), findsOneWidget);
      await tester.tap(find.byKey(const Key('open-yes')));
      await tester.pumpAndSettle();
      expect(reports.created.single.open, isTrue);
      expect(find.text('Aberto · confirmado por você agora'), findsOneWidget);
      expect(
        find.text('Você informou às 20h40. De novo a partir das 21h10.'),
        findsOneWidget,
      );
      final yes = tester.widget<ButtonStyleButton>(
        find.byKey(const Key('open-yes')),
      );
      expect(yes.onPressed, isNull);
    });

    testWidgets('sem permissão: convite explica e pede no toque; negada, '
        '"Ative a localização para confirmar"', (tester) async {
      final location = FakeLocationService(position: pontaNegra)
        ..status = LocationStatus.denied;
      final app = await pumpApp(
        tester,
        places: [_mangai],
        openReports: FakeOpenReportRepository(),
        location: location,
        clock: () => _now,
      );
      app.router.go(Routes.placeDetail('mangai'));
      await tester.pumpAndSettle();
      expect(location.locateCalls, 0, reason: 'nunca pede ao abrir');
      await tester.tap(find.byKey(const Key('open-ask-location')));
      await tester.pumpAndSettle();
      expect(find.text(OpenNowViewModel.explainBody), findsOneWidget);
      expect(location.locateCalls, 0, reason: 'só depois da explicação');
      await tester.tap(find.byKey(const Key('open-use-location')));
      await tester.pumpAndSettle();
      expect(location.locateCalls, 1);
      expect(find.text(OpenNowViewModel.locationOffMessage), findsOneWidget);
    });

    testWidgets('falha ao enviar: "Não foi possível enviar"', (tester) async {
      final reports = FakeOpenReportRepository()
        ..createError = StateError('rede');
      final app = await pumpApp(
        tester,
        places: [_mangai],
        openReports: reports,
        location: FakeLocationService(position: pontaNegra, granted: true),
        clock: () => _now,
      );
      app.router.go(Routes.placeDetail('mangai'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-no')));
      await tester.pumpAndSettle();
      expect(find.text(OpenNowViewModel.errorText), findsOneWidget);
    });
  });

  group('Perto (F20)', () {
    final places = [
      placeNear('aberto', 80, bearingDeg: 10, name: 'Aberto 80'),
      placeNear('fechado', 150, bearingDeg: 120, name: 'Fechado 150'),
      placeNear('diverge', 200, bearingDeg: 200, name: 'Diverge 200'),
      placeNear('nada', 250, bearingDeg: 300, name: 'Nada 250'),
    ];

    Future<TestApp> openNearby(
      WidgetTester tester,
      FakeOpenReportRepository reports,
    ) async {
      // Tela alta: todos os itens da lista construídos.
      tester.view
        ..physicalSize = const Size(800, 2400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final app = await pumpApp(
        tester,
        places: places,
        openReports: reports,
        location: FakeLocationService(position: pontaNegra, granted: true),
        clock: () => _now,
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('app-nav')),
          matching: find.text('Perto'),
        ),
      );
      await tester.pumpAndSettle();
      return app;
    }

    FakeOpenReportRepository seeded() => FakeOpenReportRepository()
      ..add('aberto', open: true, at: _ago(20))
      ..add('fechado', open: false, at: _ago(60), authorName: 'Caio')
      ..add('diverge', open: true, at: _ago(10))
      ..add('diverge', open: false, at: _ago(20), authorId: 'caio')
      ..add('fora-da-lista', open: true, at: _ago(5));

    testWidgets('status nos itens e filtro "Aberto agora (confirmado)"', (
      tester,
    ) async {
      final reports = seeded();
      await openNearby(tester, reports);
      // Só os itens da lista vão para a consulta.
      expect(reports.placesFetchCalls.single.toSet(), {
        'aberto',
        'fechado',
        'diverge',
        'nada',
      });
      expect(
        find.text('Aberto · confirmado por Ana há 20 min'),
        findsOneWidget,
      );
      expect(find.text('Fechado · informado por Caio há 1 h'), findsOneWidget);
      expect(
        find.text('Informações divergentes · 2 relatos na última meia hora'),
        findsOneWidget,
      );
      expect(find.text('Nada 250'), findsOneWidget);

      await tester.tap(find.byKey(const Key('nearby-open-filter')));
      await tester.pumpAndSettle();
      expect(find.text('Fechado 150'), findsNothing);
      expect(find.text('Diverge 200'), findsNothing);
      expect(find.text('Nada 250'), findsNothing);
      expect(find.text('Aberto 80'), findsWidgets);
    });

    testWidgets('filtro sem confirmados: mensagem e "Mostrar todos"', (
      tester,
    ) async {
      await openNearby(tester, FakeOpenReportRepository());
      await tester.tap(find.byKey(const Key('nearby-open-filter')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('nearby-open-empty')), findsOneWidget);
      await tester.tap(find.text(NearbyView.showAllLabel));
      await tester.pumpAndSettle();
      expect(find.text('Nada 250'), findsOneWidget);
    });

    testWidgets('leitura falha: lista intacta, chip desabilitado com aviso', (
      tester,
    ) async {
      final reports = seeded()..fetchError = StateError('rede');
      await openNearby(tester, reports);
      expect(find.text('Nada 250'), findsOneWidget);
      expect(find.byKey(const Key('nearby-open-status')), findsNothing);
      expect(find.byKey(const Key('nearby-open-unavailable')), findsOneWidget);
      final chip = tester.widget<FilterChip>(
        find.byKey(const Key('nearby-open-filter')),
      );
      expect(chip.onSelected, isNull);
    });

    testWidgets('Ana confirma no Mangai; Toni vê no Perto', (tester) async {
      final reports = FakeOpenReportRepository()..clock = () => _now;
      await reports.createReport(
        const NewOpenReport(
          authorId: 'ana',
          authorName: 'Ana',
          placeId: 'aberto',
          open: true,
        ),
      );
      await openNearby(tester, reports);
      expect(find.text('Aberto · confirmado por Ana agora'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Aberto agora, confirmado por Ana agora')),
        findsWidgets,
      );
    });
  });

  test('a espera do envio desabilita os botões (sem envio duplo)', () async {
    final env = _Env();
    env.reports.createGate = Completer<void>();
    final vm = await _attached(env, _mangai);
    final first = vm.submit(open: true);
    expect(vm.isSubmitting, isTrue);
    expect(vm.canReport, isFalse);
    expect(await vm.submit(open: false), isFalse);
    env.reports.createGate!.complete();
    expect(await first, isTrue);
    expect(env.reports.created, hasLength(1));
  });

  group('NearbyViewModel (F20)', () {
    NearbyViewModel nearbyVm(FakeOpenReportRepository? reports) =>
        NearbyViewModel(
          locationService: FakeLocationService(
            position: pontaNegra,
            granted: true,
          ),
          placeRepository: FakePlaceRepository([
            placeNear('a', 80, bearingDeg: 10),
            placeNear('b', 120, bearingDeg: 100),
            placeNear('c', 160, bearingDeg: 190),
          ]),
          authRepository: FakeAuthRepository(uid: 'me'),
          userRepository: FakeUserRepository(),
          reviewRepository: FakeReviewRepository(),
          visitRepository: FakeVisitRepository(),
          openReportRepository: reports,
          clock: () => _now,
        );

    test('sem repositório de relatos: sem filtro nem status', () async {
      final vm = nearbyVm(null);
      await vm.start();
      expect(vm.hasOpenFilter, isFalse);
      expect(vm.openStatusOf('a'), isNull);
      expect(vm.visibleItems, hasLength(3));
    });

    test(
      'filtro: só Aberto (não divergente); sugestão segue o filtro',
      () async {
        final reports = FakeOpenReportRepository()
          ..add('b', open: true, at: _ago(5))
          ..add('c', open: true, at: _ago(5))
          ..add('c', open: false, at: _ago(15), authorId: 'caio');
        final vm = nearbyVm(reports);
        await vm.start();
        expect(vm.openStatusOf('b')!.kind, OpenStatusKind.open);
        expect(vm.openStatusOf('c')!.kind, OpenStatusKind.divergent);
        expect(vm.suggestion!.item.place.id, 'a');
        vm.setOpenOnly(true);
        expect([for (final i in vm.visibleItems) i.place.id], ['b']);
        expect(vm.suggestion!.item.place.id, 'b');
        expect(vm.items, hasLength(3), reason: 'items continua completo');
      },
    );

    test('leitura falha: filtro desliga e não liga mais', () async {
      final reports = FakeOpenReportRepository()..fetchError = StateError('x');
      final vm = nearbyVm(reports);
      await vm.start();
      expect(vm.openReadFailed, isTrue);
      vm.setOpenOnly(true);
      expect(vm.openOnly, isFalse);
      expect(vm.visibleItems, hasLength(3));
    });
  });
}
