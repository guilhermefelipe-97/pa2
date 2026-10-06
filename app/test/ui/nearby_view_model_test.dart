import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/data/services/location_service.dart';
import 'package:naarea/domain/geo.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/ui/core/follow_events.dart';
import 'package:naarea/ui/nearby/nearby_view_model.dart';
import 'package:naarea/ui/saved/saved_places_store.dart';

import '../support/builders.dart';
import '../support/fakes.dart';
import '../support/geo_helpers.dart';

/// 6 locais em 300 m de Ponta Negra (em direções diferentes) + 1 a 301 m +
/// 1 a 800 m + 1 curado sem coordenada.
final _sixIn300 = [
  placeNear('p80', 80, bearingDeg: 10),
  placeNear('p120', 120, bearingDeg: 100),
  placeNear('p160', 160, bearingDeg: 190),
  placeNear('p200', 200, bearingDeg: 280),
  placeNear('p250', 250, bearingDeg: 45),
  placeNear('p290', 290, bearingDeg: 135),
  placeNear('p301', 301, bearingDeg: 225),
  placeNear('p800', 800, bearingDeg: 315),
  const Place(
    id: 'curado',
    name: 'Curado',
    category: 'Bar',
    neighborhood: 'Ponta Negra',
    city: 'Natal',
  ),
];

class _Env {
  _Env({
    List<Place>? places,
    LatLng? position = pontaNegra,
    bool granted = false,
    bool withSavedStore = false,
    List<String> savedIds = const [],
  }) : places = FakePlaceRepository(places ?? _sixIn300),
       location = FakeLocationService(position: position, granted: granted) {
    users
      ..addUser('me', 'Eu')
      ..addUser('ana', 'Ana')
      ..addUser('bia', 'Bia');
    for (final id in savedIds) {
      saved.seed('me', id, DateTime.utc(2026, 9, 1));
    }
    if (withSavedStore) {
      store = SavedPlacesStore(authRepository: auth, savedRepository: saved);
    }
  }

  final FakePlaceRepository places;
  final FakeLocationService location;
  final users = FakeUserRepository();
  final reviews = FakeReviewRepository();
  final auth = FakeAuthRepository(uid: 'me');
  final saved = FakeSavedRepository();
  final follow = FollowEvents();
  SavedPlacesStore? store;

  NearbyViewModel vm() => NearbyViewModel(
    locationService: location,
    placeRepository: places,
    authRepository: auth,
    userRepository: users,
    reviewRepository: reviews,
    followEvents: follow,
    savedStore: store,
  );
}

List<String> _ids(NearbyViewModel vm) => [for (final i in vm.items) i.place.id];

void main() {
  group('permissão', () {
    test(
      'primeira vez: explica antes de pedir (sem pedido do sistema)',
      () async {
        final env = _Env();
        final vm = env.vm();
        await vm.start();
        expect(vm.phase, NearbyPhase.explain);
        expect(env.location.locateCalls, 0);
        expect(env.places.nearbyCalls, isEmpty);

        await vm.useMyLocation();
        expect(env.location.locateCalls, 1);
        expect(vm.phase, NearbyPhase.ready);
      },
    );

    test('já concedida: vai direto para a lista', () async {
      final env = _Env(granted: true);
      final vm = env.vm();
      await vm.start();
      expect(env.location.locateCalls, 1);
      expect(vm.phase, NearbyPhase.ready);
      // start() só vale uma vez.
      await vm.start();
      expect(env.location.locateCalls, 1);
    });

    for (final (status, phase) in [
      (LocationStatus.denied, NearbyPhase.denied),
      (LocationStatus.deniedForever, NearbyPhase.deniedForever),
      (LocationStatus.serviceOff, NearbyPhase.serviceOff),
      (LocationStatus.unavailable, NearbyPhase.locationError),
    ]) {
      test('$status → $phase, sem consultar locais', () async {
        final env = _Env()..location.status = status;
        final vm = env.vm();
        await vm.start();
        await vm.useMyLocation();
        expect(vm.phase, phase);
        expect(vm.position, isNull);
        expect(env.places.nearbyCalls, isEmpty);

        // "Tentar de novo" depois de liberar.
        env.location.status = LocationStatus.ok;
        await vm.useMyLocation();
        expect(vm.phase, NearbyPhase.ready);
      });
    }

    test('"Abrir configurações" delega ao serviço', () async {
      final env = _Env();
      final vm = env.vm();
      await vm.openAppSettings();
      await vm.openLocationSettings();
      expect(env.location.openAppSettingsCalls, 1);
      expect(env.location.openLocationSettingsCalls, 1);
    });
  });

  group('lista', () {
    test(
      '6 locais em 300 m por distância; 301 m e sem coordenada fora',
      () async {
        final env = _Env(granted: true);
        final vm = env.vm();
        await vm.start();
        expect(_ids(vm), ['p80', 'p120', 'p160', 'p200', 'p250', 'p290']);
        expect(vm.items.first.distanceMeters, closeTo(80, 0.01));
        expect(formatDistance(vm.items.first.distanceMeters), '80 m');
        expect(formatDistance(vm.items[4].distanceMeters), '250 m');
      },
    );

    test('chip 1 km refaz a consulta e inclui o que estava fora', () async {
      final env = _Env(granted: true);
      final vm = env.vm();
      await vm.start();
      await vm.selectRadius(NearbyRadius.km1);
      expect(vm.radius, NearbyRadius.km1);
      expect(_ids(vm), [
        'p80',
        'p120',
        'p160',
        'p200',
        'p250',
        'p290',
        'p301',
        'p800',
      ]);
      expect(env.places.nearbyCalls, hasLength(2));
    });

    test('nada em 300 m: vazio; "Ampliar para 1 km" mostra até 1 km', () async {
      final env = _Env(granted: true, places: [placeNear('longe', 700)]);
      final vm = env.vm();
      await vm.start();
      expect(vm.phase, NearbyPhase.ready);
      expect(vm.items, isEmpty);
      expect(vm.outOfArea, isFalse);
      expect(vm.suggestion, isNull);
      expect(vm.radius.wider, NearbyRadius.km1);

      await vm.selectRadius(vm.radius.wider!);
      expect(_ids(vm), ['longe']);
      expect(vm.suggestion!.item.place.id, 'longe');
      expect(NearbyRadius.km3.wider, isNull);
    });

    test('fora de Natal (50 km): fora da área, sem itens', () async {
      final env = _Env(granted: true, position: (lat: -6.24, lng: -35.211));
      final vm = env.vm();
      await vm.start();
      expect(vm.phase, NearbyPhase.ready);
      expect(vm.items, isEmpty);
      expect(vm.outOfArea, isTrue);
    });

    test('falha de rede: loadError; "Tentar de novo" recupera', () async {
      final env = _Env(granted: true);
      env.places.fail = true;
      final vm = env.vm();
      await vm.start();
      expect(vm.phase, NearbyPhase.loadError);
      expect(vm.items, isEmpty);

      env.places.fail = false;
      await vm.retry();
      expect(vm.phase, NearbyPhase.ready);
      expect(vm.items, hasLength(6));
      // Mesma posição: não pediu de novo.
      expect(env.location.locateCalls, 1);
    });

    test('resposta antiga é descartada (troca de raio no meio)', () async {
      final env = _Env(granted: true);
      final vm = env.vm();
      final gate = env.places.nearbyGate = Completer<void>();
      unawaited(vm.start());
      await pumpEventQueue();
      expect(vm.phase, NearbyPhase.loading);
      final wider = vm.selectRadius(NearbyRadius.km1);
      gate.complete();
      await wider;
      await pumpEventQueue();
      expect(vm.radius, NearbyRadius.km1);
      expect(_ids(vm), contains('p800'));
    });
  });

  group('cache por (geohash 7, raio)', () {
    test('mesma célula e raio: uma consulta só', () async {
      final env = _Env(granted: true);
      final vm = env.vm();
      await vm.start();
      await vm.refresh(); // nova posição (a mesma) → cache
      expect(env.location.locateCalls, 2);
      expect(env.places.nearbyCalls, hasLength(1));

      // Consulta parte do centro da célula, com folga.
      final call = env.places.nearbyCalls.single;
      final cell = geohashEncode(pontaNegra.lat, pontaNegra.lng, precision: 7);
      final center = geohashCenter(cell);
      expect((call.lat, call.lng), (center.lat, center.lng));
      expect(call.radius, 300 + NearbyViewModel.cacheCellSlackMeters);
    });

    test('voltar a um raio já consultado usa o cache', () async {
      final env = _Env(granted: true);
      final vm = env.vm();
      await vm.start();
      await vm.selectRadius(NearbyRadius.km1);
      await vm.selectRadius(NearbyRadius.m300);
      expect(env.places.nearbyCalls, hasLength(2));
      expect(_ids(vm), hasLength(6));
    });

    test(
      'mudou de célula: nova consulta, distâncias da posição nova',
      () async {
        final env = _Env(granted: true);
        final vm = env.vm();
        await vm.start();
        env.location.position = destination(pontaNegra, 600, 0);
        await vm.refresh();
        expect(env.places.nearbyCalls, hasLength(2));
        expect(_ids(vm), isNot(contains('p290')));
      },
    );

    test('dentro da mesma célula, distância vem da posição exata', () async {
      final env = _Env(granted: true);
      final vm = env.vm();
      await vm.start();
      final cell = geohashEncode(pontaNegra.lat, pontaNegra.lng, precision: 7);
      // Outro ponto da mesma célula (o centro dela).
      final c = geohashCenter(cell);
      env.location.position = c;
      await vm.refresh();
      expect(env.places.nearbyCalls, hasLength(1));
      for (final i in vm.items) {
        expect(
          i.distanceMeters,
          closeTo(
            distanceMeters(c, (lat: i.place.lat!, lng: i.place.lng!)),
            1e-6,
          ),
        );
        expect(i.distanceMeters, lessThanOrEqualTo(300));
      }
    });
  });

  group('sugestão', () {
    test(
      'Ana avaliou o 3º mais perto: Sugestão = 3º, "Ana foi aqui"',
      () async {
        final env = _Env(granted: true);
        env.users.followingByUser['me'] = {'ana'};
        env.reviews.stored.addAll([
          review(authorId: 'ana', authorName: 'Ana', placeId: 'p160'),
          // Quem não sigo não conta.
          review(authorId: 'bia', authorName: 'Bia', placeId: 'p80'),
        ]);
        final vm = env.vm();
        await vm.start();
        final s = vm.suggestion!;
        expect(s.item.place.id, 'p160');
        expect(s.reason, SuggestionReason.friend);
        expect(s.item.friendsLabel, 'Ana foi aqui');
        expect(vm.items.first.friends, isEmpty);
        // Sinal vem das avaliações de quem sigo (mesma fonte do feed).
        expect(env.reviews.fetchCalls.single, ['ana']);
      },
    );

    test('sem amigo: o mais perto salvo no Quero ir', () async {
      final env = _Env(granted: true, withSavedStore: true, savedIds: ['p200']);
      await env.store!.reload();
      final vm = env.vm();
      await vm.start();
      expect(vm.suggestion!.item.place.id, 'p200');
      expect(vm.suggestion!.reason, SuggestionReason.saved);
      expect(vm.isSaved('p200'), isTrue);
    });

    test('sem amigo nem salvo: o mais perto', () async {
      final env = _Env(granted: true, withSavedStore: true);
      final vm = env.vm();
      await vm.start();
      expect(vm.suggestion!.item.place.id, 'p80');
      expect(vm.suggestion!.reason, SuggestionReason.nearest);
    });

    test('salvar um local muda a sugestão na hora', () async {
      final env = _Env(granted: true, withSavedStore: true);
      await env.store!.reload();
      final vm = env.vm();
      await vm.start();
      var notified = 0;
      vm.addListener(() => notified++);
      await env.store!.setSaved('p250', true);
      expect(notified, greaterThan(0));
      expect(vm.suggestion!.item.place.id, 'p250');
    });

    test('ampliar recalcula: amigo só a 800 m vira sugestão em 1 km', () async {
      final env = _Env(granted: true);
      env.users.followingByUser['me'] = {'ana'};
      env.reviews.stored.add(
        review(authorId: 'ana', authorName: 'Ana', placeId: 'p800'),
      );
      final vm = env.vm();
      await vm.start();
      expect(vm.suggestion!.reason, SuggestionReason.nearest);
      await vm.selectRadius(NearbyRadius.km1);
      expect(vm.suggestion!.item.place.id, 'p800');
      expect(vm.suggestion!.reason, SuggestionReason.friend);
    });

    test('rótulo com mais de um amigo', () {
      expect(friendsWentLabel(const []), isNull);
      expect(friendsWentLabel(const ['Ana']), 'Ana foi aqui');
      expect(friendsWentLabel(const ['Ana', 'Bia']), 'Ana e Bia foram aqui');
      expect(
        friendsWentLabel(const ['Ana', 'Bia', 'Caio']),
        'Ana e mais 2 foram aqui',
      );
    });

    test(
      'vários amigos no mesmo local: mais recente primeiro, sem repetir',
      () async {
        final env = _Env(granted: true);
        env.users.followingByUser['me'] = {'ana', 'bia'};
        env.reviews.stored.addAll([
          review(
            authorId: 'ana',
            authorName: 'Ana',
            placeId: 'p120',
            createdAt: DateTime.utc(2026, 9, 1),
          ),
          review(
            authorId: 'bia',
            authorName: 'Bia',
            placeId: 'p120',
            createdAt: DateTime.utc(2026, 9, 3),
          ),
          review(
            authorId: 'ana',
            authorName: 'Ana',
            placeId: 'p120',
            createdAt: DateTime.utc(2026, 9, 2),
          ),
        ]);
        final vm = env.vm();
        await vm.start();
        expect(vm.items[1].friends, ['Bia', 'Ana']);
      },
    );

    test('falha ao ler o sinal de amigos não derruba a lista', () async {
      final env = _Env(granted: true);
      env.users.failGetFollowing = true;
      final vm = env.vm();
      await vm.start();
      expect(vm.phase, NearbyPhase.ready);
      expect(vm.items, hasLength(6));
      expect(vm.suggestion!.reason, SuggestionReason.nearest);

      // Tenta de novo na próxima carga.
      env.users.failGetFollowing = false;
      env.users.followingByUser['me'] = {'ana'};
      env.reviews.stored.add(
        review(authorId: 'ana', authorName: 'Ana', placeId: 'p250'),
      );
      await vm.selectRadius(NearbyRadius.km1);
      expect(vm.suggestion!.item.place.id, 'p250');
    });
  });

  group('atualizar', () {
    test(
      'puxar para atualizar: nova posição e sinal de amigos relido',
      () async {
        final env = _Env(granted: true);
        final vm = env.vm();
        await vm.start();
        expect(env.users.getFollowingCalls, 1);
        await vm.selectRadius(NearbyRadius.km1);
        // Troca de raio reaproveita o sinal.
        expect(env.users.getFollowingCalls, 1);
        await vm.refresh();
        expect(env.location.locateCalls, 2);
        expect(env.users.getFollowingCalls, 2);
      },
    );

    test('seguir alguém em outra tela: recarrega ao voltar à aba', () async {
      final env = _Env(granted: true);
      final vm = env.vm();
      await vm.start();
      await vm.reloadIfStale();
      expect(env.users.getFollowingCalls, 1);

      env.users.followingByUser['me'] = {'ana'};
      env.reviews.stored.add(
        review(authorId: 'ana', authorName: 'Ana', placeId: 'p290'),
      );
      env.follow.changed();
      await vm.reloadIfStale();
      expect(env.users.getFollowingCalls, 2);
      expect(vm.suggestion!.item.place.id, 'p290');
      // Sem pedir a posição de novo.
      expect(env.location.locateCalls, 1);
    });
  });
}
