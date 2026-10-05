import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:naarea/data/services/photo_picker.dart';
import 'package:naarea/domain/photo_compression.dart';
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
      photoPicker: FakePhotoPicker(),
      compress: (b) async => b,
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

  group('foto (opcional)', () {
    late FakePhotoPicker picker;
    late List<Uint8List> compressed;
    Future<Uint8List> Function(Uint8List) compress = (b) async => b;
    final original = Uint8List.fromList(List.filled(10, 1));
    final jpeg = Uint8List.fromList([0xFF, 0xD8, 2]);

    ReviewViewModel build() => ReviewViewModel(
      place: _place,
      authRepository: FakeAuthRepository(uid: 'bianca'),
      userRepository: users,
      reviewRepository: reviews,
      photoPicker: picker,
      compress: (b) {
        compressed.add(b);
        return compress(b);
      },
    );

    void fill(ReviewViewModel vm) => vm
      ..setFood(5)
      ..setAmbience(4)
      ..setService(3);

    setUp(() {
      picker = FakePhotoPicker();
      compressed = [];
      compress = (b) async => jpeg;
    });

    test('sem foto: envia como antes (photo null)', () async {
      final vm = build();
      fill(vm);
      expect(await vm.submit(), isTrue);
      expect(reviews.createdPhotos.single, isNull);
      expect(reviews.stored.single.hasPhoto, isFalse);
    });

    test(
      'anexar: recodifica o original e envia só o JPEG recodificado',
      () async {
        final vm = build();
        picker.next = original;
        await vm.pickPhoto(PhotoSource.gallery);
        expect(picker.calls, [PhotoSource.gallery]);
        expect(compressed.single, original);
        expect(vm.photo, jpeg);
        expect(vm.photoMessage, isNull);

        fill(vm);
        expect(await vm.submit(), isTrue);
        expect(reviews.createdPhotos.single, jpeg);
        expect(reviews.stored.single.hasPhoto, isTrue);
      },
    );

    test('comprimindo: Enviar desabilitado até terminar', () async {
      final gate = Completer<Uint8List>();
      compress = (_) => gate.future;
      final vm = build();
      fill(vm);
      picker.next = original;
      final picking = vm.pickPhoto(PhotoSource.camera);
      await Future<void>.delayed(Duration.zero);
      expect(vm.isProcessingPhoto, isTrue);
      expect(vm.canSubmit, isFalse);
      gate.complete(jpeg);
      await picking;
      expect(vm.isProcessingPhoto, isFalse);
      expect(vm.canSubmit, isTrue);
    });

    test(
      'compressor de produção: JPEG com EXIF GPS sai sem EXIF e ≤1080 px',
      () async {
        final source = img.Image(width: 1600, height: 1200);
        for (final p in source) {
          p
            ..r = p.x % 256
            ..g = p.y % 256
            ..b = 90;
        }
        source.exif.gpsIfd['GPSLatitudeRef'] = img.IfdValueAscii('S');
        source.exif.gpsIfd['GPSLatitude'] = img.IfdValueRational(5, 1);
        final withGps = img.encodeJpg(source, quality: 95);
        expect(String.fromCharCodes(withGps).contains('Exif'), isTrue);

        final vm = ReviewViewModel(
          place: _place,
          authRepository: FakeAuthRepository(uid: 'bianca'),
          userRepository: users,
          reviewRepository: reviews,
          photoPicker: picker..next = withGps,
          compress: compressPhotoInBackground,
        );
        await vm.pickPhoto(PhotoSource.gallery);
        final out = vm.photo!;
        expect(out.length, lessThanOrEqualTo(maxPhotoBytes));
        expect(String.fromCharCodes(out).contains('Exif'), isFalse);
        final decoded = img.decodeJpg(out)!;
        expect(decoded.width, 1080);
        expect(decoded.height, 810);

        // O erro tipado atravessa o isolate: formato não suportado.
        picker.next = Uint8List.fromList(List.filled(64, 7));
        await vm.pickPhoto(PhotoSource.gallery);
        expect(vm.photoMessage, ReviewViewModel.photoUnsupportedMessage);
        expect(vm.photo, out, reason: 'mantém a anterior');
      },
    );

    test('compressão falha: avisa e segue sem foto', () async {
      compress = (_) async => throw Exception('decode');
      final vm = build();
      picker.next = original;
      await vm.pickPhoto(PhotoSource.gallery);
      expect(vm.photo, isNull);
      expect(vm.photoMessage, 'Não foi possível usar essa foto');
      fill(vm);
      expect(await vm.submit(), isTrue);
      expect(reviews.createdPhotos.single, isNull);
    });

    test('resultado acima de 150.000 bytes é recusado', () async {
      compress = (_) async => Uint8List(150001);
      final vm = build();
      picker.next = original;
      await vm.pickPhoto(PhotoSource.gallery);
      expect(vm.photo, isNull);
      expect(vm.photoMessage, ReviewViewModel.photoUnusableMessage);
    });

    test('cancelar a seleção não muda nada (nem a foto atual)', () async {
      final vm = build();
      picker.next = original;
      await vm.pickPhoto(PhotoSource.gallery);
      picker.next = null;
      await vm.pickPhoto(PhotoSource.camera);
      expect(vm.photo, jpeg);
      expect(vm.photoMessage, isNull);
      expect(compressed, hasLength(1));
    });

    test('trocar foto substitui; remover volta a sem foto', () async {
      final vm = build();
      picker.next = original;
      await vm.pickPhoto(PhotoSource.gallery);
      final other = Uint8List.fromList([0xFF, 0xD8, 9]);
      compress = (_) async => other;
      await vm.pickPhoto(PhotoSource.camera);
      expect(vm.photo, other);
      vm.removePhoto();
      expect(vm.photo, isNull);
      fill(vm);
      await vm.submit();
      expect(reviews.createdPhotos.single, isNull);
    });

    test('troca que falha mantém a foto anterior', () async {
      final vm = build();
      picker.next = original;
      await vm.pickPhoto(PhotoSource.gallery);
      expect(vm.photo, jpeg);
      compress = (_) async => throw Exception('decode');
      await vm.pickPhoto(PhotoSource.camera);
      expect(vm.photo, jpeg);
      expect(vm.photoMessage, ReviewViewModel.photoUnusableMessage);
    });

    test('formato não suportado tem mensagem própria', () async {
      compress = (_) async => throw const PhotoCompressionException(
        PhotoCompressionFailure.unsupportedFormat,
      );
      final vm = build();
      picker.next = original;
      await vm.pickPhoto(PhotoSource.gallery);
      expect(vm.photoMessage, 'Formato de foto não suportado');
    });

    test('não abre dois seletores ao mesmo tempo', () async {
      final vm = build();
      fill(vm);
      picker
        ..gate = Completer<void>()
        ..next = original;
      final first = vm.pickPhoto(PhotoSource.gallery);
      await Future<void>.delayed(Duration.zero);
      expect(vm.isPicking, isTrue);
      expect(vm.photoBusy, isTrue);
      expect(vm.canSubmit, isFalse);
      await vm.pickPhoto(PhotoSource.camera);
      expect(picker.calls, [PhotoSource.gallery]);
      picker.gate!.complete();
      await first;
      expect(vm.isPicking, isFalse);
      expect(vm.photo, jpeg);
    });

    test('sem câmera no aparelho: mensagem própria', () async {
      final vm = build();
      picker.error = const PhotoUnavailableException();
      await vm.pickPhoto(PhotoSource.camera);
      expect(vm.photoMessage, 'Este aparelho não tem câmera disponível');
    });

    test('erro inesperado do seletor: mensagem genérica', () async {
      final vm = build();
      picker.error = StateError('already_active');
      await vm.pickPhoto(PhotoSource.camera);
      expect(vm.photoMessage, ReviewViewModel.photoUnusableMessage);
      expect(vm.isPicking, isFalse);
    });

    test('recupera a foto pendente (Android) e recodifica', () async {
      final vm = build();
      picker.lost = original;
      await vm.recoverLostPhoto();
      expect(compressed.single, original);
      expect(vm.photo, jpeg);
      await vm.recoverLostPhoto();
      expect(compressed, hasLength(1), reason: 'nada pendente');
    });

    test('mensagem de permissão por plataforma', () {
      expect(
        ReviewViewModel.permissionDeniedMessage(
          PhotoSource.camera,
          TargetPlatform.iOS,
        ),
        contains('Ajustes › NaÁrea'),
      );
      expect(
        ReviewViewModel.permissionDeniedMessage(
          PhotoSource.gallery,
          TargetPlatform.android,
        ),
        contains('Configurações › Apps › NaÁrea › Permissões'),
      );
    });

    test('permissão negada: mensagem explicando como liberar', () async {
      final vm = build();
      picker.error = const PhotoPermissionDeniedException(PhotoSource.camera);
      await vm.pickPhoto(PhotoSource.camera);
      expect(vm.photo, isNull);
      expect(vm.photoMessage, contains('câmera'));
      expect(vm.photoMessage, contains('Configurações'));
      picker.error = const PhotoPermissionDeniedException(PhotoSource.gallery);
      await vm.pickPhoto(PhotoSource.gallery);
      expect(vm.photoMessage, contains('fotos'));
    });

    test(
      'falha ao salvar com foto: nada gravado e "Não foi possível salvar"',
      () async {
        reviews.createError = Exception('permission-denied');
        final vm = build();
        picker.next = original;
        await vm.pickPhoto(PhotoSource.gallery);
        fill(vm);
        expect(await vm.submit(), isFalse);
        expect(vm.errorMessage, 'Não foi possível salvar');
        expect(reviews.photos, isEmpty);
        expect(vm.photo, jpeg, reason: 'mantém a foto para tentar de novo');
      },
    );

    test(
      'AC: Ana avalia com foto; no feed de Bianca a capa é a foto de Ana',
      () async {
        users
          ..addUser('ana', 'Ana')
          ..followingByUser['bianca'] = {'ana'};
        final vm = ReviewViewModel(
          place: _place,
          authRepository: FakeAuthRepository(uid: 'ana'),
          userRepository: users,
          reviewRepository: reviews,
          photoPicker: picker..next = original,
          compress: (_) async => jpeg,
        );
        await vm.pickPhoto(PhotoSource.camera);
        fill(vm);
        expect(await vm.submit(), isTrue);

        final feed = FeedViewModel(
          authRepository: FakeAuthRepository(uid: 'bianca'),
          userRepository: users,
          reviewRepository: reviews,
          placeRepository: FakePlaceRepository([_place]),
        );
        await feed.load();
        final cover = feed.items.single.latestPhoto!;
        expect(cover.authorName, 'Ana');
        expect(reviews.photos[cover.id], jpeg);
      },
    );
  });
}
