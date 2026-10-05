import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/models/companion.dart';
import 'package:naarea/domain/models/day_period.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/domain/models/scores.dart';
import 'package:naarea/ui/feed/feed_view_model.dart';
import 'package:naarea/ui/review/review_view_model.dart';

import '../support/fakes.dart';

const _place = Place(
  id: 'mangai',
  name: 'Mangai',
  category: 'Restaurante',
  neighborhood: 'Tirol',
  city: 'Natal',
);

void main() {
  late FakeUserRepository users;
  late FakeReviewRepository reviews;
  late ReviewViewModel vm;

  setUp(() {
    users = FakeUserRepository()
      ..addUser('bianca', 'Bianca')
      ..addUser('toni', 'Toni');
    reviews = FakeReviewRepository();
    vm = ReviewViewModel(
      place: _place,
      authRepository: FakeAuthRepository(uid: 'bianca'),
      userRepository: users,
      reviewRepository: reviews,
    );
  });

  test('começa sem notas e com Enviar desabilitado', () {
    expect(vm.food, isNull);
    expect(vm.canSubmit, isFalse);
  });

  test(
    '2 de 3 eixos: Enviar desabilitado e repositório não é chamado',
    () async {
      vm
        ..setFood(4)
        ..setAmbience(3);
      expect(vm.canSubmit, isFalse);
      expect(await vm.submit(), isFalse);
      expect(reviews.created, isEmpty);
    },
  );

  test('valor fora de 1–5 não conta como preenchido', () {
    vm
      ..setFood(0)
      ..setAmbience(6)
      ..setService(3);
    expect(vm.food, isNull);
    expect(vm.ambience, isNull);
    expect(vm.canSubmit, isFalse);
  });

  test('3 eixos: envia com autor = uid, nome do perfil e local', () async {
    vm
      ..setFood(5)
      ..setAmbience(4)
      ..setService(3)
      ..toggleCompanion(Companion.amigos);
    expect(vm.canSubmit, isTrue);
    expect(await vm.submit(), isTrue);

    final r = reviews.created.single;
    expect(r.authorId, 'bianca');
    expect(r.authorName, 'Bianca');
    expect(r.placeId, 'mangai');
    expect(r.placeName, 'Mangai');
    expect(r.scores, Scores(food: 5, ambience: 4, service: 3));
    expect(r.companion, Companion.amigos);
    expect(vm.errorMessage, isNull);
  });

  test('companhia é opcional e tocar de novo desmarca', () async {
    vm.toggleCompanion(Companion.casal);
    expect(vm.companion, Companion.casal);
    vm.toggleCompanion(Companion.casal);
    expect(vm.companion, isNull);

    vm
      ..setFood(1)
      ..setAmbience(1)
      ..setService(1);
    expect(await vm.submit(), isTrue);
    expect(reviews.created.single.companion, isNull);
  });

  test('escrita negada pelas Rules: "Não foi possível salvar"', () async {
    reviews.createError = Exception('permission-denied');
    vm
      ..setFood(5)
      ..setAmbience(5)
      ..setService(5);
    expect(await vm.submit(), isFalse);
    expect(vm.errorMessage, 'Não foi possível salvar');
    expect(vm.isSubmitting, isFalse);
  });

  test('sem perfil: não envia e mostra erro', () async {
    users.profiles.remove('bianca');
    vm
      ..setFood(5)
      ..setAmbience(5)
      ..setService(5);
    expect(await vm.submit(), isFalse);
    expect(reviews.created, isEmpty);
    expect(vm.errorMessage, 'Não foi possível salvar');
  });

  test(
    'AC: avaliação aparece no feed de quem segue, com nome, 3 eixos e período',
    () async {
      users.followingByUser['toni'] = {'bianca'};
      vm
        ..setFood(5)
        ..setAmbience(4)
        ..setService(3);
      await vm.submit();

      final feed = FeedViewModel(
        authRepository: FakeAuthRepository(uid: 'toni'),
        userRepository: users,
        reviewRepository: reviews,
        placeRepository: FakePlaceRepository([_place]),
      );
      await feed.load();
      final r = feed.items.single.reviews.single;
      expect(r.authorName, 'Bianca');
      expect(r.scores, Scores(food: 5, ambience: 4, service: 3));
      // clock do fake: 23:00Z = 20:00 em Natal
      expect(r.dayPeriod, DayPeriod.noite);
    },
  );

  group('comentário (opcional)', () {
    void fill() => vm
      ..setFood(5)
      ..setAmbience(4)
      ..setService(3);

    test('sem comentário envia normalmente com comment null', () async {
      fill();
      expect(vm.canSubmit, isTrue);
      expect(await vm.submit(), isTrue);
      expect(reviews.created.single.comment, isNull);
    });

    test('só espaços conta como sem comentário', () async {
      fill();
      vm.setComment('   ');
      expect(await vm.submit(), isTrue);
      expect(reviews.created.single.comment, isNull);
    });

    test('comentário é enviado aparado', () async {
      fill();
      vm.setComment('  Camarão no ponto, fila grande.  ');
      expect(await vm.submit(), isTrue);
      expect(reviews.created.single.comment, 'Camarão no ponto, fila grande.');
    });

    test(
      'acima de 280 (contagem UTF-16, igual às Rules): Enviar desabilitado',
      () async {
        fill();
        vm.setComment('😀' * 141);
        expect(vm.commentTooLong, isTrue);
        expect(vm.canSubmit, isFalse);
        expect(await vm.submit(), isFalse);
        expect(reviews.created, isEmpty);

        vm.setComment('x' * 280);
        expect(vm.commentTooLong, isFalse);
        expect(vm.canSubmit, isTrue);
      },
    );

    test('AC: comentário aparece no card de quem segue', () async {
      users.followingByUser['toni'] = {'bianca'};
      fill();
      vm.setComment('Vale cada centavo');
      await vm.submit();

      final feed = FeedViewModel(
        authRepository: FakeAuthRepository(uid: 'toni'),
        userRepository: users,
        reviewRepository: reviews,
        placeRepository: FakePlaceRepository([_place]),
      );
      await feed.load();
      expect(feed.items.single.latestComment?.comment, 'Vale cada centavo');
    });
  });
}
