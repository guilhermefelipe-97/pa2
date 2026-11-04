import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:naarea/domain/models/user_profile.dart';
import 'package:naarea/domain/photo_compression.dart';
import 'package:naarea/routing/routes.dart';
import 'package:naarea/ui/core/photo_crop_view.dart';

import '../support/app_harness.dart';
import '../support/fakes.dart';
import '../support/profile_edit_fakes.dart';

/// 200x100: metade esquerda vermelha, direita azul.
Uint8List halfAndHalf() {
  final image = img.Image(width: 200, height: 100);
  for (final p in image) {
    p
      ..r = p.x < 100 ? 255 : 0
      ..g = 0
      ..b = p.x < 100 ? 0 : 255;
  }
  return img.encodePng(image);
}

/// Espera trabalho real (decodificar imagem, `compute`) e redesenha.
Future<void> settleReal(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  group('PhotoCrop', () {
    test('recorta a parte escolhida da imagem', () {
      final out = img.decodeJpg(
        compressPhoto(
          halfAndHalf(),
          crop: const PhotoCrop(left: .5, top: 0, width: .5, height: 1),
        ),
      )!;
      expect((out.width, out.height), (100, 100));
      final center = out.getPixel(50, 50);
      expect(center.b, greaterThan(200));
      expect(center.r, lessThan(60));
    });

    test('valores fora da imagem ficam nas bordas', () {
      final image = img.Image(width: 10, height: 10);
      final out = const PhotoCrop(
        left: .8,
        top: -1,
        width: 5,
        height: 2,
      ).apply(image);
      expect((out.width, out.height), (2, 10));
    });

    test('parte visível: imagem larga, centralizada e com zoom', () {
      const viewport = Size(100, 100);
      const content = Size(200, 100);
      final centered = PhotoCropView.visibleCrop(
        transform: Matrix4.identity()..translateByDouble(-50, 0, 0, 1),
        viewport: viewport,
        content: content,
      );
      expect(
        centered,
        const PhotoCrop(left: .25, top: 0, width: .5, height: 1),
      );

      final zoomed = PhotoCropView.visibleCrop(
        transform: Matrix4.identity()
          ..translateByDouble(-200, -50, 0, 1)
          ..scaleByDouble(2, 2, 1, 1),
        viewport: viewport,
        content: content,
      );
      expect(
        zoomed,
        const PhotoCrop(left: .5, top: .25, width: .25, height: .5),
      );
    });
  });

  testWidgets('tela de ajuste: começa centralizada; cancelar devolve nulo', (
    tester,
  ) async {
    PhotoCrop? result;
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showPhotoCropView(
                context,
                bytes: halfAndHalf(),
                aspectRatio: 1,
                circle: true,
              );
              closed = true;
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await settleReal(tester);
    expect(find.text('Ajustar foto'), findsOneWidget);
    await tester.tap(find.byKey(const Key('photo-crop-confirm')));
    await tester.pumpAndSettle();
    expect(result!.left, closeTo(.25, 1e-6));
    expect(result!.width, closeTo(.5, 1e-6));
    expect(result!.height, closeTo(1, 1e-6));

    closed = false;
    await tester.tap(find.text('abrir'));
    await settleReal(tester);
    await tester.tap(find.byKey(const Key('photo-crop-cancel')));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, isNull);
  });

  group('editar perfil: foto e @usuário', () {
    Future<(FakeProfileEditor, FakeUserRepository)> openEditor(
      WidgetTester tester, {
      String username = '',
    }) async {
      final users = FakeUserRepository()..addUser('me', 'Bianca');
      if (username.isNotEmpty) {
        users.profiles['me'] = UserProfile(
          uid: 'me',
          displayName: 'Bianca',
          username: username,
        );
      }
      final media = FakeProfileMedia();
      final editor = FakeProfileEditor(users, media);
      final app = await pumpApp(
        tester,
        users: users,
        picker: FakePhotoPicker()..next = halfAndHalf(),
        profileEditor: editor,
        profileMedia: media,
        account: FakeAccountRepository(),
      );
      app.router.go(Routes.editProfile);
      await tester.pumpAndSettle();
      return (editor, users);
    }

    Future<void> pickAvatar(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('profile-pick-avatar')));
      await settleReal(tester);
      expect(find.text('Ajustar foto'), findsOneWidget);
      await tester.tap(find.byKey(const Key('photo-crop-confirm')));
      await settleReal(tester);
    }

    testWidgets('sem @usuário: aviso explica que a foto precisa de um @', (
      tester,
    ) async {
      final (editor, _) = await openEditor(tester);
      await pickAvatar(tester);
      await tester.tap(find.byKey(const Key('profile-edit-save')));
      await tester.pump();
      expect(find.byKey(const Key('profile-username-needed')), findsOneWidget);
      expect(
        find.textContaining('é necessário ter um @usuário'),
        findsOneWidget,
      );
      expect(editor.writes, 0);
    });

    testWidgets('com @usuário: salva a foto recortada normalmente', (
      tester,
    ) async {
      final (editor, _) = await openEditor(tester, username: 'bianca');
      await pickAvatar(tester);
      await tester.tap(find.byKey(const Key('profile-edit-save')));
      await settleReal(tester);
      expect(editor.writes, 1);
      final saved = img.decodeJpg(editor.media.bytes['me/avatar']!)!;
      expect(saved.width, saved.height, reason: 'avatar recortado quadrado');
      expect(find.byKey(const Key('profile-username-needed')), findsNothing);
    });

    testWidgets('cancelar o ajuste não troca a foto', (tester) async {
      final (editor, _) = await openEditor(tester, username: 'bianca');
      await tester.tap(find.byKey(const Key('profile-pick-avatar')));
      await settleReal(tester);
      await tester.tap(find.byKey(const Key('photo-crop-cancel')));
      await settleReal(tester);
      await tester.tap(find.byKey(const Key('profile-edit-save')));
      await settleReal(tester);
      expect(editor.writes, 1);
      expect(editor.media.bytes['me/avatar'], isNull);
    });
  });
}
