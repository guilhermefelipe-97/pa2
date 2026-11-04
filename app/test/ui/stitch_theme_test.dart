import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/data/repositories/auth_repository.dart';
import 'package:naarea/data/repositories/user_repository.dart';
import 'package:naarea/data/repositories/sponsorship_repository.dart';
import 'package:naarea/domain/models/scores.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/routing/routes.dart';
import 'package:naarea/ui/core/theme.dart';
import 'package:naarea/ui/privacy/silent_field.dart';
import 'package:naarea/ui/nearby/nearby_view.dart';
import 'package:naarea/ui/nearby/nearby_view_model.dart';
import 'package:naarea/ui/settings/settings_view.dart';
import 'package:naarea/ui/review/place_picker_view.dart';
import 'package:naarea/ui/review/review_view.dart';
import 'package:naarea/ui/review/place_picker_view_model.dart';
import 'package:provider/provider.dart';
import '../support/app_harness.dart';
import '../support/builders.dart';
import '../support/fakes.dart';
import '../support/place_gallery_fakes.dart';
import '../support/profile_edit_fakes.dart';
import '../support/owner_workspace_fake.dart';
import 'package:naarea/data/repositories/owner_repository.dart';
import 'package:naarea/data/repositories/owner_workspace_repository.dart';
import 'package:naarea/domain/models/user_profile.dart';
import 'package:naarea/domain/models/companion.dart';
import 'package:naarea/domain/price_band.dart';
import 'package:naarea/data/repositories/place_photo_repository.dart';
import 'package:naarea/data/repositories/queue_repository.dart';

Future<void> loadStitchFonts() async {
  final sdkRoot = File(
    Platform.resolvedExecutable,
  ).parent.parent.parent.parent.parent;
  final iconFont = File(
    '${sdkRoot.path}/cache/artifacts/material_fonts/materialicons-regular.otf',
  );
  if (await iconFont.exists()) {
    final loader = FontLoader('MaterialIcons')
      ..addFont(iconFont.readAsBytes().then(ByteData.sublistView));
    await loader.load();
  }
  for (final (family, file) in [
    ('Epilogue', 'Epilogue'),
    ('Plus Jakarta Sans', 'PlusJakartaSans'),
  ]) {
    final loader = FontLoader(family);
    for (final weight in [400, 500, 600, 700]) {
      loader.addFont(rootBundle.load('assets/fonts/$file-$weight.ttf'));
    }
    await loader.load();
  }
}

class _PreviewSponsors implements SponsorshipRepository {
  @override
  Future<List<SponsoredSlot>> current(DateTime now) async => [
    SponsoredSlot(
      'preview',
      'sponsored-preview',
      now.subtract(const Duration(days: 1)),
      now.add(const Duration(days: 6)),
    ),
  ];
}

class _LogoutAuth extends FakeAuthRepository {
  _LogoutAuth() : super(uid: 'me');
  final done = Completer<void>();
  int calls = 0;
  @override
  Future<void> signOut() async {
    calls++;
    await done.future;
  }
}

void main() {
  setUpAll(loadStitchFonts);
  testWidgets(
    'Configurações: sair bloqueia toque duplicado e falha permite tentar novamente',
    (tester) async {
      final auth = _LogoutAuth();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthRepository>.value(value: auth),
            Provider<UserRepository>.value(
              value: FakeUserRepository()..addUser('me', 'Bianca'),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const SettingsView(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('settings-sign-out')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byKey(const Key('settings-sign-out')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-sign-out')));
      await tester.pump();
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('settings-sign-out')))
            .onPressed,
        isNull,
      );
      expect(auth.calls, 1);
      auth.done.completeError(StateError('rede'));
      await tester.pumpAndSettle();
      expect(
        find.text('Não foi possível sair. Tente de novo.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('settings-sign-out')))
            .onPressed,
        isNotNull,
      );
      expect(auth.currentUserId, 'me');
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets('Tema real: rotas e ações em 320dp com fonte ${scale}x', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final now = DateTime.utc(2026, 10, 31, 15);
      final p = place(name: 'Café de bairro');
      final users = FakeUserRepository()
        ..addUser('me', 'Bianca Ferreira')
        ..addUser('ana', 'Ana Silva')
        ..followingByUser['me'] = {'ana'};
      final reviews = FakeReviewRepository()
        ..stored.add(
          review(
            authorId: 'ana',
            authorName: 'Ana Silva',
            placeName: p.name,
            createdAt: now.subtract(const Duration(hours: 2)),
            scores: Scores(food: 5, ambience: 4, service: 5),
            comment: 'Café e conversa entre amigos.',
          ),
        );
      final app = await pumpApp(
        tester,
        users: users,
        reviews: reviews,
        places: [p],
        theme: AppTheme.light(),
        textScale: scale,
        clock: () => now,
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.byKey(const Key('save-p1')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-p1')));
      await tester.pumpAndSettle();
      expect(app.saved.byUser['me'], contains('p1'));
      expect(app.router.routeInformationProvider.value.uri.path, Routes.feed);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      app.router.go(Routes.person('me'));
      await tester.pumpAndSettle();
      ScaffoldMessenger.of(
        tester.element(find.text('Adicionar @usuário')),
      ).removeCurrentSnackBar();
      await tester.pumpAndSettle();
      expect(find.text('Adicionar @usuário'), findsOneWidget);
      expect(find.text('Bianca Ferreira'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('profile-tab-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profile-tab-2')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Suas listas'), findsOneWidget);
      app.router.go(Routes.settings);
      await tester.pumpAndSettle();
      expect(find.text('Bianca Ferreira'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
      app.auth.restoreSession('ana');
      await tester.pumpAndSettle();
      expect(find.text('Bianca Ferreira'), findsNothing);
      expect(find.text('Ana Silva'), findsOneWidget);
      app.router.go(Routes.placeDetail(p.id), extra: p);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      app.router.go(Routes.reviewFor(p.id), extra: p);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('axis-food-4')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('axis-food-4')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('review-submit')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('review-submit')), findsOneWidget);
    });
  }

  testWidgets('Capturas Flutter com fontes locais e tema real', (tester) async {
    const output = String.fromEnvironment('STITCH_CAPTURE_DIR');
    if (output.isEmpty) return;
    tester.view.physicalSize =
        [
          'details',
          'profiles',
        ].contains(const String.fromEnvironment('STITCH_CAPTURE_SCREEN'))
        ? const Size(390, 1500)
        : const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    final now = DateTime.utc(2026, 10, 31, 15);
    const p = Place(
      id: 'p1',
      name: 'Café da Praça',
      category: 'Cafeteria',
      neighborhood: 'Tirol',
      city: 'Natal',
      lat: -5.8100,
      lng: -35.2000,
    );
    final users = FakeUserRepository()
      ..addUser('me', 'Bianca Ferreira')
      ..addUser('ana', 'Ana Silva')
      ..followingByUser['me'] = {'ana'};
    final reviews = FakeReviewRepository()
      ..stored.add(
        review(
          authorId: 'ana',
          authorName: 'Ana Silva',
          placeName: p.name,
          createdAt: now.subtract(const Duration(hours: 2)),
          scores: Scores(food: 5, ambience: 4, service: 5),
          comment: 'Um café tranquilo para conversar.',
        ),
      );
    final captureSaved = FakeSavedRepository()..byUser['me'] = {'p1': now};
    final profileMedia = FakeProfileMedia();
    if (const String.fromEnvironment('STITCH_CAPTURE_SCREEN') == 'profiles') {
      final cover = await tester.runAsync(
        () => File('$output/profile-reference-cover.jpg').readAsBytes(),
      );
      final avatar = await tester.runAsync(
        () => File('$output/profile-reference-avatar.jpg').readAsBytes(),
      );
      users.profiles['me'] = const UserProfile(
        uid: 'me',
        displayName: 'Bianca Ferreira',
        username: 'bianca.sabores',
        bio: 'Cafés especiais, boas conversas e descobertas pela cidade.',
        city: 'Natal, RN',
      );
      profileMedia.bytes['me/cover'] = cover!;
      profileMedia.bytes['me/avatar'] = avatar!;
      reviews.stored.add(
        review(
          id: 'profile-preview',
          authorId: 'me',
          authorName: 'Bianca Ferreira',
          placeName: p.name,
          createdAt: now.subtract(const Duration(days: 2)),
          scores: Scores(food: 5, ambience: 4, service: 5),
          companion: Companion.casal,
          priceBand: PriceBand.from30To60,
          comment:
              'Café bem preparado e ambiente acolhedor. Um lugar tranquilo para conversar e voltar com os amigos.',
          hasPhoto: true,
        ),
      );
      reviews.photos['profile-preview'] = cover;
    }
    final previewGallery = FakePlacePhotoRepository();
    final previewQueue = FakeGalleryQueue(now);
    final ownerPreview = FakeOwnerRepository()
      ..owners['p1'] = 'me'
      ..requests['me'] = [
        const OwnershipRequest('p1', 'approved'),
        const OwnershipRequest('sponsored-preview', 'pending'),
      ];
    final ownerWorkspace = FakeOwnerWorkspace()
      ..summaries['p1'] = const OwnerPlaceSummary(
        reviews: 27,
        unanswered: 3,
        rating: 4.8,
      )
      ..values['p1'] = const PlacePresentation(
        description:
            'Cafés especiais e pratos preparados com ingredientes locais, em um espaço acolhedor no Tirol.',
        hours: 'Terça a domingo, das 12h às 22h.',
      );
    if ([
      'details',
      'owners',
    ].contains(const String.fromEnvironment('STITCH_CAPTURE_SCREEN'))) {
      captureSaved.byUser['me'] = {};
      for (var i = 1; i <= 2; i++) {
        final bytes = await tester.runAsync(
          () => File('$output/venue-reference-$i.jpg').readAsBytes(),
        );
        previewGallery.photos.add(
          PlaceGalleryPhoto(
            id: 'photo-$i',
            authorId: 'ana',
            authorName: 'Ana Silva',
            createdAt: now,
            jpeg: bytes!,
          ),
        );
      }
      for (var i = 0; i < 4; i++) {
        previewQueue.reports.add(
          QueueReport(
            id: 'queue-$i',
            authorId: 'q-$i',
            authorName: 'Pessoa ${i + 1}',
            placeId: 'p1',
            minutes: i < 2 ? 15 : 20,
            createdAt: now.subtract(const Duration(minutes: 4)),
          ),
        );
      }
      for (final (id, name) in [('bruno', 'Bruno'), ('camila', 'Camila')]) {
        users.addUser(id, name);
        users.followingByUser['me']!.add(id);
        reviews.stored.add(
          review(
            id: 'preview-$id',
            authorId: id,
            authorName: name,
            placeName: p.name,
            createdAt: now.subtract(const Duration(days: 1)),
          ),
        );
      }
    }
    if (const String.fromEnvironment('STITCH_CAPTURE_SCREEN') == 'all') {
      reviews.stored.add(
        review(
          authorId: 'me',
          authorName: 'Bianca Ferreira',
          placeName: p.name,
          createdAt: now.subtract(const Duration(days: 3)),
          comment: 'Um lugar acolhedor para uma pausa no bairro.',
        ),
      );
    }
    final app = await pumpApp(
      tester,
      users: users,
      reviews: reviews,
      places: [p],
      location: FakeLocationService(
        position: (lat: -5.8101, lng: -35.2001),
        granted: true,
      ),
      theme: AppTheme.light(),
      captureKey: key,
      saved: captureSaved,
      owners: const String.fromEnvironment('STITCH_CAPTURE_SCREEN') == 'owners'
          ? ownerPreview
          : null,
      ownerWorkspace:
          const String.fromEnvironment('STITCH_CAPTURE_SCREEN') == 'owners'
          ? ownerWorkspace
          : null,
      reputation:
          const String.fromEnvironment('STITCH_CAPTURE_SCREEN') == 'profiles'
          ? PreviewProfileReplies()
          : null,
      profileMedia:
          const String.fromEnvironment('STITCH_CAPTURE_SCREEN') == 'profiles'
          ? profileMedia
          : null,
      profileEditor:
          const String.fromEnvironment('STITCH_CAPTURE_SCREEN') == 'profiles'
          ? FakeProfileEditor(users, profileMedia)
          : null,
      account:
          const String.fromEnvironment('STITCH_CAPTURE_SCREEN') == 'profiles'
          ? FakeAccountRepository()
          : null,
      profileStats:
          const String.fromEnvironment('STITCH_CAPTURE_SCREEN') == 'profiles'
          ? FakeProfileStats(users, reviews)
          : null,
      gallery:
          [
            'details',
            'owners',
          ].contains(const String.fromEnvironment('STITCH_CAPTURE_SCREEN'))
          ? previewGallery
          : null,
      galleryPicker:
          [
            'details',
            'owners',
          ].contains(const String.fromEnvironment('STITCH_CAPTURE_SCREEN'))
          ? FakePlacePhotoPicker()
          : null,
      queue: const String.fromEnvironment('STITCH_CAPTURE_SCREEN') == 'details'
          ? previewQueue
          : null,
      sponsors:
          const String.fromEnvironment('STITCH_CAPTURE_SCREEN') == 'nearby'
          ? _PreviewSponsors()
          : null,
      placeRepository: FakePlaceRepository([
        p,
        const Place(
          id: 'sponsored-preview',
          name: 'Casa Cobre & Brasa',
          category: 'Bistrô contemporâneo',
          neighborhood: 'Tirol',
          city: 'Natal',
          lat: -5.8045,
          lng: -35.2,
        ),
      ]),
      openReports: FakeOpenReportRepository(),
      clock: () => now,
    );
    Future<void> capture(String name) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final raster = await boundary.toImage(pixelRatio: 1);
        final bytes = await raster.toByteData(format: ui.ImageByteFormat.png);
        await Directory(output).create(recursive: true);
        await File(
          '$output/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        raster.dispose();
      });
    }

    if (const String.fromEnvironment('STITCH_CAPTURE_SCREEN') == 'owners') {
      app.router.go('/meus-estabelecimentos');
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
      }
      await capture('meus-estabelecimentos-validacao');
      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
      }
      await capture('editar-estabelecimento-validacao');
      Navigator.of(tester.element(find.text('Editar estabelecimento'))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Acompanhar pedido'));
      await tester.pumpAndSettle();
      await capture('acompanhar-titularidade-validacao');
      expect(tester.takeException(), isNull);
      return;
    }
    if (const String.fromEnvironment('STITCH_CAPTURE_SCREEN') == 'profiles') {
      app.router.go('/perfil');
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
      }
      await capture('perfil-novo-validacao');
      tester.view.physicalSize = const Size(390, 1200);
      app.router.push(Routes.editProfile);
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
      }
      await capture('editar-perfil-validacao');
      await tester.scrollUntilVisible(
        find.byKey(const Key('profile-change-password')),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('profile-change-password')));
      tester.view.physicalSize = const Size(390, 850);
      await tester.pumpAndSettle();
      await capture('alterar-senha-modal-validacao');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Cancelar'),
        ),
      );
      await tester.pumpAndSettle();
      app.router.push(Routes.accountSecurity);
      await tester.pumpAndSettle();
      await capture('conta-seguranca-validacao');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.router.dispose();
      return;
    }
    if (const String.fromEnvironment('STITCH_CAPTURE_SCREEN') == 'details') {
      app.router.go(Routes.placeDetail(p.id), extra: p);
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
      }
      await capture('detalhes-local-completo');
      await tester.tap(find.byKey(const Key('place-add-photos')));
      await tester.pumpAndSettle();
      await capture('detalhes-adicionar-fotos');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.router.dispose();
      return;
    }
    if (const String.fromEnvironment('STITCH_CAPTURE_SCREEN') == 'ownership') {
      app.router.go(Routes.placeDetail(p.id), extra: p);
      await tester.pumpAndSettle();
      await capture('detalhes-local-validacao');
      await tester.tap(find.byTooltip('Solicitar titularidade'));
      await tester.pumpAndSettle();
      await capture('detalhes-estabelecimento-dialogo');
      await tester.tap(find.byKey(const Key('ownership-request-submit')));
      await tester.pumpAndSettle();
      await capture('detalhes-estabelecimento-pendente');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.router.dispose();
      return;
    }
    if (const String.fromEnvironment('STITCH_CAPTURE_SCREEN') == 'all') {
      await capture('final-feed');
      app.router.go(Routes.saved);
      await tester.pumpAndSettle();
      await capture('final-salvos');
      app.router.go(Routes.people);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('people-search')), 'Ana');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await capture('final-pessoas');
      app.router.go(Routes.person('me'));
      await tester.pumpAndSettle();
      await capture('final-perfil');
      app.router.go(Routes.settings);
      await tester.pumpAndSettle();
      await capture('final-configuracoes');
      app.router.go(Routes.placeDetail(p.id), extra: p);
      await tester.pumpAndSettle();
      await capture('final-ficha');
      app.router.go('/meus-estabelecimentos');
      await tester.pumpAndSettle();
      await capture('final-titularidade');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.router.dispose();
      return;
    }
    if (const String.fromEnvironment('STITCH_CAPTURE_SCREEN') == 'review') {
      app.router.push(Routes.reviewFor(p.id), extra: p);
      await tester.pumpAndSettle();
      await capture('avaliacao');
      final reviewScroll = find
          .descendant(
            of: find.byType(ReviewView),
            matching: find.byType(Scrollable),
          )
          .first;
      for (final axis in ['food', 'ambience', 'service']) {
        final star = find.byKey(Key('axis-$axis-4'));
        await tester.scrollUntilVisible(star, 200, scrollable: reviewScroll);
        await tester.tap(star);
        await tester.pumpAndSettle();
      }
      await tester.scrollUntilVisible(
        find.byKey(const Key('review-comment')),
        200,
        scrollable: reviewScroll,
      );
      await tester.enterText(
        find.byKey(const Key('review-comment')),
        'Um café tranquilo, com bom atendimento e ambiente acolhedor.',
      );
      await tester.pumpAndSettle();
      await capture('avaliacao-comentario');
      await tester.scrollUntilVisible(
        find.byType(SilentField),
        200,
        scrollable: reviewScroll,
      );
      await tester.pumpAndSettle();
      await capture('avaliacao-final');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.router.dispose();
      return;
    }
    if (const String.fromEnvironment('STITCH_CAPTURE_SCREEN') == 'nearby') {
      app.router.go(Routes.nearby);
      await tester.pumpAndSettle();
      await capture('perto');
      await tester.enterText(
        find.byKey(const Key('nearby-search')),
        'Ramen no Itaim',
      );
      await tester.pumpAndSettle();
      await capture('perto-vazio');
      await tester.tap(find.text('Limpar filtros aplicados'));
      await tester.pumpAndSettle();
      app.places.fail = true;
      final vm = tester.widget<NearbyView>(find.byType(NearbyView)).viewModel;
      await vm.selectRadius(NearbyRadius.km1);
      await tester.pumpAndSettle();
      expect(find.text('Sem conexão no momento'), findsOneWidget);
      await capture('perto-offline');
      app.places.fail = false;
      final gate = Completer<void>();
      app.places.nearbyGate = gate;
      final loading = vm.selectRadius(NearbyRadius.km3);
      await tester.pump();
      expect(find.byKey(const Key('nearby-skeleton')), findsOneWidget);
      await capture('perto-carregando');
      gate.complete();
      await loading;
      await tester.pumpWidget(const SizedBox());
      app.router.dispose();
      return;
    }
    await capture('feed');
    app.router.go(Routes.person('me'));
    await capture('perfil');
    app.router.go(Routes.settings);
    await capture('configuracoes');
    app.router.go(Routes.placeDetail(p.id), extra: p);
    await capture('ficha');
    app.router.go(Routes.reviewFor(p.id), extra: p);
    await capture('formulario');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Captura Onde Você Foi', (tester) async {
    const output = String.fromEnvironment('STITCH_CAPTURE_DIR');
    if (output.isEmpty) return;
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    final vm = PlacePickerViewModel(
      placeRepository: FakePlaceRepository([
        place(
          name: 'Café da Praça',
          category: 'Cafeteria',
          neighborhood: 'Tirol',
          photoUrl: 'https://example.invalid/cafe.jpg',
        ),
        place(
          id: 'bistro-preview',
          name: 'Bistrô Botânico',
          category: 'Restaurante',
          neighborhood: 'Jardins',
          photoUrl: 'https://example.invalid/bistro.jpg',
        ),
        place(
          id: 'izakaya-preview',
          name: 'Izakaya Matsu',
          category: 'Bar',
          neighborhood: 'Pinheiros',
          photoUrl: 'https://example.invalid/izakaya.jpg',
        ),
        place(
          id: 'padaria-preview',
          name: 'Padaria da Esquina',
          category: 'Padaria',
          neighborhood: 'Jardins',
          photoUrl: 'https://example.invalid/padaria.jpg',
        ),
      ]),
      locationService: FakeLocationService(
        position: (lat: -5.81, lng: -35.2),
        granted: true,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: RepaintBoundary(
          key: key,
          child: Column(
            children: [Expanded(child: PlacePickerView(viewModel: vm))],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final raster = await boundary.toImage(pixelRatio: 1);
      final bytes = await raster.toByteData(format: ui.ImageByteFormat.png);
      await Directory(output).create(recursive: true);
      await File(
        '$output/onde-voce-foi.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      raster.dispose();
    });
    vm.dispose();
  });
}
