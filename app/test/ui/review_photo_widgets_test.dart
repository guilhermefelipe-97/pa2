import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:naarea/data/repositories/review_photo_repository.dart';
import 'package:naarea/data/services/photo_picker.dart';
import 'package:naarea/domain/feed.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/routing/routes.dart';
import 'package:naarea/ui/feed/widgets/feed_card.dart';
import 'package:naarea/ui/feed/widgets/place_photo.dart';
import 'package:naarea/ui/feed/widgets/review_photo.dart';
import 'package:naarea/ui/place/place_detail_view.dart';
import 'package:naarea/ui/place/review_photo_strip.dart';
import 'package:naarea/ui/review/review_view.dart';
import 'package:naarea/ui/review/review_view_model.dart';
import 'package:provider/provider.dart';

import '../support/app_harness.dart';
import '../support/builders.dart';
import '../support/fakes.dart';

final _now = DateTime.utc(2026, 9, 28, 15);

/// PNG válido de verdade (o engine de teste decodifica).
final Uint8List _png = img.encodePng(img.Image(width: 16, height: 9));

const _mangai = Place(
  id: 'mangai',
  name: 'Mangai',
  category: 'Restaurante',
  neighborhood: 'Tirol',
  city: 'Natal',
);

void _tallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(412, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Espera, de forma determinística, o engine decodificar cada imagem montada:
/// resolve o mesmo ImageProvider do widget (mesma chave no ImageCache) e
/// aguarda o 1º quadro ou o erro; depois redesenha.
Future<void> _decode(WidgetTester tester) async {
  // Pumps até o repositório responder e o ReviewPhoto montar o Image.memory.
  for (var i = 0; i < 3; i++) {
    await tester.pump();
  }
  final providers = tester
      .widgetList<Image>(find.byType(Image))
      .map((w) => w.image)
      .toList();
  await tester.runAsync(() async {
    for (final provider in providers) {
      final done = Completer<void>();
      final stream = provider.resolve(ImageConfiguration.empty);
      final listener = ImageStreamListener(
        (_, _) => done.isCompleted ? null : done.complete(),
        onError: (_, _) => done.isCompleted ? null : done.complete(),
      );
      stream.addListener(listener);
      await done.future;
      stream.removeListener(listener);
    }
  });
  await tester.pumpAndSettle();
}

Widget _host(Widget child, ReviewPhotoRepository photos) =>
    Provider<ReviewPhotoRepository>.value(
      value: photos,
      child: MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  group('ReviewView: foto opcional', () {
    late FakePhotoPicker picker;
    late ReviewViewModel vm;

    setUp(() {
      picker = FakePhotoPicker();
      vm = ReviewViewModel(
        place: _mangai,
        authRepository: FakeAuthRepository(uid: 'me'),
        userRepository: FakeUserRepository()..addUser('me', 'Eu'),
        reviewRepository: FakeReviewRepository(),
        photoPicker: picker,
        compress: (_) async => _png,
      );
    });

    Future<void> choose(WidgetTester tester, String key) async {
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    testWidgets('anexar pela galeria mostra a prévia; trocar e remover', (
      tester,
    ) async {
      _tallPhone(tester);
      await tester.pumpWidget(MaterialApp(home: ReviewView(viewModel: vm)));
      expect(find.text('Foto (opcional)'), findsOneWidget);

      picker.next = Uint8List.fromList([1, 2, 3]);
      await choose(tester, 'photo-add');
      expect(find.text('Tirar foto'), findsOneWidget);
      expect(find.text('Escolher da galeria'), findsOneWidget);
      await choose(tester, 'photo-source-gallery');
      expect(picker.calls, [PhotoSource.gallery]);
      expect(find.byKey(const Key('photo-preview')), findsOneWidget);
      expect(find.byKey(const Key('photo-add')), findsNothing);

      // Toque na prévia: "Trocar foto" / "Remover foto".
      await choose(tester, 'photo-preview');
      expect(find.text('Trocar foto'), findsOneWidget);
      expect(find.text('Remover foto'), findsOneWidget);
      await choose(tester, 'photo-change');
      await choose(tester, 'photo-source-camera');
      expect(picker.calls, [PhotoSource.gallery, PhotoSource.camera]);
      expect(vm.photo, isNotNull);

      await choose(tester, 'photo-preview');
      await choose(tester, 'photo-remove');
      expect(vm.photo, isNull);
      expect(find.byKey(const Key('photo-add')), findsOneWidget);
    });

    testWidgets('fechar a câmera sem foto não muda nada', (tester) async {
      _tallPhone(tester);
      await tester.pumpWidget(MaterialApp(home: ReviewView(viewModel: vm)));
      picker.next = null;
      await choose(tester, 'photo-add');
      await choose(tester, 'photo-source-camera');
      expect(find.byKey(const Key('photo-add')), findsOneWidget);
      expect(find.byKey(const Key('photo-message')), findsNothing);
    });

    testWidgets('permissão negada explica como liberar', (tester) async {
      _tallPhone(tester);
      await tester.pumpWidget(MaterialApp(home: ReviewView(viewModel: vm)));
      picker.error = const PhotoPermissionDeniedException(PhotoSource.camera);
      await choose(tester, 'photo-add');
      await choose(tester, 'photo-source-camera');
      final message = tester.widget<Text>(
        find.byKey(const Key('photo-message')),
      );
      expect(message.data, contains('Configurações'));
    });

    testWidgets('compressão falha: "Não foi possível usar essa foto"', (
      tester,
    ) async {
      _tallPhone(tester);
      final failing = ReviewViewModel(
        place: _mangai,
        authRepository: FakeAuthRepository(uid: 'me'),
        userRepository: FakeUserRepository()..addUser('me', 'Eu'),
        reviewRepository: FakeReviewRepository(),
        photoPicker: picker..next = Uint8List.fromList([1]),
        compress: (_) async => throw Exception('decode'),
      );
      await tester.pumpWidget(
        MaterialApp(home: ReviewView(viewModel: failing)),
      );
      await choose(tester, 'photo-add');
      await choose(tester, 'photo-source-gallery');
      expect(find.text('Não foi possível usar essa foto'), findsOneWidget);
      expect(find.byKey(const Key('photo-add')), findsOneWidget);
    });
  });

  group('FeedCard: foto do amigo', () {
    FeedItem anaComFotoBetoSem() => groupReviewsIntoFeed(
      [
        review(
          id: 'ra',
          authorId: 'a',
          authorName: 'Ana',
          placeId: 'mangai',
          createdAt: _now.subtract(const Duration(hours: 1)),
          hasPhoto: true,
        ),
        review(
          id: 'rb',
          authorId: 'b',
          authorName: 'Beto',
          placeId: 'mangai',
          createdAt: _now,
        ),
      ],
      places: {'mangai': _mangai},
    ).single;

    testWidgets('A com foto (há 1 h) e B sem: foto de A com "Foto de Ana"', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final photos = FakeReviewPhotoRepository({'ra': _png});
      await tester.pumpWidget(
        _host(FeedCard(item: anaComFotoBetoSem(), now: _now), photos),
      );
      await _decode(tester);
      expect(photos.calls, ['ra']);
      expect(find.byKey(const Key('review-photo-ra')), findsOneWidget);
      expect(find.text('Foto de Ana'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Foto de Ana em Mangai')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('foto falha ao carregar: fallback, sem crédito nem erro', (
      tester,
    ) async {
      final photos = FakeReviewPhotoRepository()..failing.add('ra');
      await tester.pumpWidget(
        _host(FeedCard(item: anaComFotoBetoSem(), now: _now), photos),
      );
      await _decode(tester);
      expect(find.byKey(const Key('place-photo-fallback')), findsOneWidget);
      expect(find.text('Foto de Ana'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('bytes corrompidos: fallback, sem crédito nem erro', (
      tester,
    ) async {
      final photos = FakeReviewPhotoRepository({
        'ra': Uint8List.fromList([1, 2, 3, 4]),
      });
      await tester.pumpWidget(
        _host(FeedCard(item: anaComFotoBetoSem(), now: _now), photos),
      );
      await _decode(tester);
      expect(find.text('Foto de Ana'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ninguém com foto: não consulta fotos', (tester) async {
      final photos = FakeReviewPhotoRepository();
      final item = groupReviewsIntoFeed(
        [review(placeId: 'mangai')],
        places: {'mangai': _mangai},
      ).single;
      await tester.pumpWidget(_host(FeedCard(item: item, now: _now), photos));
      await _decode(tester);
      expect(photos.calls, isEmpty);
      expect(find.byKey(const Key('place-photo-fallback')), findsOneWidget);
    });
  });

  testWidgets(
    'Detalhe: 3 avaliações com foto viram faixa; toque abre tela cheia com crédito e tempo',
    (tester) async {
      _tallPhone(tester);
      final users = FakeUserRepository()
        ..addUser('me', 'Eu')
        ..followingByUser['me'] = {'a', 'b', 'c'};
      final reviews = FakeReviewRepository()
        ..stored.addAll([
          for (final (i, name) in ['Ana', 'Beto', 'Caio'].indexed)
            review(
              id: 'r$i',
              authorId: name[0].toLowerCase(),
              authorName: name,
              placeId: 'mangai',
              placeName: 'Mangai',
              createdAt: _now.subtract(Duration(hours: i + 1)),
              hasPhoto: true,
            ),
        ])
        ..photos.addAll({'r0': _png, 'r1': _png, 'r2': _png});
      final app = await pumpApp(
        tester,
        users: users,
        reviews: reviews,
        places: [_mangai],
        clock: () => _now,
      );
      app.router.go(Routes.placeDetail('mangai'));
      await tester.pumpAndSettle();
      await _decode(tester);
      expect(find.byType(PlaceDetailView), findsOneWidget);
      expect(find.byType(ReviewPhotoStrip), findsOneWidget);
      for (final id in ['r0', 'r1', 'r2']) {
        expect(find.byKey(Key('review-photo-tile-$id')), findsOneWidget);
      }
      // Capa = foto mais recente (Ana), com crédito sobre ela.
      expect(find.text('Foto de Ana'), findsWidgets);

      await tester.tap(find.byKey(const Key('review-photo-tile-r1')));
      await tester.pumpAndSettle();
      await _decode(tester);
      expect(find.byType(ReviewPhotoViewer), findsOneWidget);
      final credit = tester.widget<Text>(
        find.byKey(const Key('review-photo-viewer-credit')),
      );
      expect(credit.data, startsWith('Foto de Beto · há '));
      expect(find.text('2/3'), findsOneWidget);

      await tester.tap(find.byKey(const Key('review-photo-viewer-close')));
      await tester.pumpAndSettle();
      expect(find.byType(ReviewPhotoViewer), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  group('crédito', () {
    test('"Foto de Ana"; própria = "Sua foto" (por flag, não por texto)', () {
      expect(photoCreditText('Ana'), 'Foto de Ana');
      expect(photoCreditText('Ana', isOwn: true), 'Sua foto');
      expect(photoCreditText('Você'), 'Foto de Você');
      expect(photoSemanticLabel('Ana', 'Mangai'), 'Foto de Ana em Mangai');
      expect(
        photoSemanticLabel('Você', 'Mangai', isOwn: true),
        'Sua foto em Mangai',
      );
    });

    test('nome vazio vira "Foto de um amigo"', () {
      expect(photoCreditText(''), 'Foto de um amigo');
      expect(photoCreditText('   '), 'Foto de um amigo');
    });
  });

  testWidgets(
    'própria review com foto no detalhe: capa e faixa com "Sua foto"',
    (tester) async {
      _tallPhone(tester);
      final users = FakeUserRepository()
        ..addUser('me', 'Eu')
        ..followingByUser['me'] = {};
      final reviews = FakeReviewRepository()
        ..stored.add(
          review(
            id: 'mine',
            authorId: 'me',
            authorName: 'Eu',
            placeId: 'mangai',
            placeName: 'Mangai',
            createdAt: _now.subtract(const Duration(hours: 1)),
            hasPhoto: true,
          ),
        )
        ..photos['mine'] = _png;
      final app = await pumpApp(
        tester,
        users: users,
        reviews: reviews,
        places: [_mangai],
        clock: () => _now,
      );
      app.router.go(Routes.placeDetail('mangai'));
      await tester.pumpAndSettle();
      await _decode(tester);
      expect(find.byKey(const Key('review-photo-tile-mine')), findsOneWidget);
      // Capa + miniatura.
      expect(find.text('Sua foto'), findsNWidgets(2));
      expect(find.textContaining('Foto de'), findsNothing);
    },
  );

  group('ReviewPhoto', () {
    final r1 = review(id: 'p1', authorName: 'Ana', hasPhoto: true);
    final r2 = review(id: 'p2', authorName: 'Beto', hasPhoto: true);

    Widget frame(ReviewPhotoRepository photos, Widget child) =>
        Provider<ReviewPhotoRepository>.value(
          value: photos,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(width: 200, height: 120, child: child),
            ),
          ),
        );

    testWidgets('já em cache: monta a imagem no 1º quadro, sem nova leitura', (
      tester,
    ) async {
      final photos = FakeReviewPhotoRepository({'p1': _png});
      await tester.runAsync(() => photos.getPhoto('p1'));
      expect(photos.peek('p1'), isNotNull);
      await tester.pumpWidget(
        frame(photos, ReviewPhoto(review: r1, placeName: 'Mangai')),
      );
      expect(find.byKey(const Key('review-photo-p1')), findsOneWidget);
      expect(photos.calls, ['p1'], reason: 'só a leitura que encheu o cache');
    });

    testWidgets('trocar de review nunca mostra os bytes da anterior', (
      tester,
    ) async {
      final photos = FakeReviewPhotoRepository({'p1': _png, 'p2': _png});
      await tester.runAsync(() => photos.getPhoto('p1'));
      await tester.pumpWidget(
        frame(photos, ReviewPhoto(review: r1, placeName: 'Mangai')),
      );
      expect(find.byKey(const Key('review-photo-p1')), findsOneWidget);

      photos.gate = Completer<void>(); // p2 fica "carregando"
      await tester.pumpWidget(
        frame(photos, ReviewPhoto(review: r2, placeName: 'Mangai')),
      );
      await tester.pump();
      expect(find.byKey(const Key('review-photo-p1')), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(find.text('Foto de Ana'), findsNothing);

      photos.gate!.complete();
      await _decode(tester);
      expect(find.byKey(const Key('review-photo-p2')), findsOneWidget);
    });
  });

  testWidgets(
    'capa com foto do amigo: a foto do catálogo por baixo não é lida',
    (tester) async {
      final handle = tester.ensureSemantics();
      final photos = FakeReviewPhotoRepository({'ra': _png});
      final item = groupReviewsIntoFeed(
        [
          review(
            id: 'ra',
            authorName: 'Ana',
            placeId: 'mangai',
            hasPhoto: true,
          ),
        ],
        places: {
          'mangai': place(
            id: 'mangai',
            name: 'Mangai',
            photoUrl: 'https://upload.wikimedia.org/mangai.jpg',
          ),
        },
      ).single;
      await tester.pumpWidget(_host(FeedCard(item: item, now: _now), photos));
      await _decode(tester);
      expect(
        find.bySemanticsLabel(RegExp('Foto de Ana em Mangai')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('Foto de Mangai')), findsNothing);
      handle.dispose();
    },
  );

  group('tela cheia', () {
    Future<FakeReviewPhotoRepository> open(
      WidgetTester tester, {
      Set<String> failing = const {},
    }) async {
      _tallPhone(tester);
      final photos = FakeReviewPhotoRepository({
        'r0': _png,
        'r1': _png,
        'r2': _png,
      })..failing.addAll(failing);
      final reviews = [
        for (final (i, name) in ['Ana', 'Beto', 'Caio'].indexed)
          review(
            id: 'r$i',
            authorId: name[0].toLowerCase(),
            authorName: name,
            placeId: 'mangai',
            createdAt: _now.subtract(Duration(hours: i + 1)),
            hasPhoto: true,
          ),
      ];
      await tester.pumpWidget(
        Provider<ReviewPhotoRepository>.value(
          value: photos,
          child: MaterialApp(
            home: ReviewPhotoViewer(
              place: _mangai,
              reviews: reviews,
              initialIndex: 1,
              now: _now,
            ),
          ),
        ),
      );
      await _decode(tester);
      return photos;
    }

    PageView pages(WidgetTester tester) => tester.widget<PageView>(
      find.byKey(const Key('review-photo-viewer-pages')),
    );

    TransformationController zoomOf(WidgetTester tester, int page) => tester
        .widget<InteractiveViewer>(
          find.byKey(Key('review-photo-viewer-zoom-$page')),
        )
        .transformationController!;

    testWidgets('com zoom o swipe fica desligado; sem zoom volta', (
      tester,
    ) async {
      await open(tester);
      expect(pages(tester).physics, isNull);
      zoomOf(tester, 1).value = Matrix4.diagonal3Values(2, 2, 1);
      await tester.pump();
      expect(pages(tester).physics, isA<NeverScrollableScrollPhysics>());

      await tester.fling(
        find.byKey(const Key('review-photo-viewer-pages')),
        const Offset(-400, 0),
        2000,
      );
      await tester.pumpAndSettle();
      expect(find.text('2/3'), findsOneWidget, reason: 'não trocou de foto');

      zoomOf(tester, 1).value = Matrix4.identity();
      await tester.pump();
      expect(pages(tester).physics, isNull);
    });

    testWidgets('trocar de página zera o zoom', (tester) async {
      await open(tester);
      final zoom = zoomOf(tester, 1);
      zoom.value = Matrix4.diagonal3Values(2, 2, 1);
      await tester.pump();
      pages(tester).controller!.jumpToPage(2);
      await tester.pumpAndSettle();
      expect(find.text('3/3'), findsOneWidget);
      expect(zoom.value.getMaxScaleOnAxis(), 1);
      expect(pages(tester).physics, isNull);
      final credit = tester.widget<Text>(
        find.byKey(const Key('review-photo-viewer-credit')),
      );
      expect(credit.data, startsWith('Foto de Caio · há '));
    });

    testWidgets('foto que falha: fallback da categoria, sem erro', (
      tester,
    ) async {
      await open(tester, failing: {'r1'});
      expect(
        find.descendant(
          of: find.byKey(const Key('review-photo-viewer-zoom-1')),
          matching: find.byType(PlacePhotoFallback),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
