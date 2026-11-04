import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:naarea/data/repositories/admin_ownership_repository.dart';
import 'package:naarea/data/firebase/firestore_admin_ownership_repository.dart';
import 'package:naarea/domain/models/admin_ownership_request.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/ui/admin/admin_access.dart';
import 'package:naarea/ui/admin/admin_ownership_view.dart';
import 'package:naarea/ui/admin/admin_ownership_view_model.dart';
import 'package:naarea/ui/core/theme.dart';
import '../support/fakes.dart';
import 'admin_ownership_test.dart' show AdminFake;
import 'stitch_theme_test.dart' show loadStitchFonts;

class PreviewAdmin extends AdminFake implements AdminHistoryRepository {
  @override
  Future<AdminRequestPage> pending({Object? cursor}) async => AdminRequestPage([
    for (final (uid, place, name) in [
      ('helena', 'Cobre & Grão Espresso', 'Helena Prado'),
      ('carlos', 'Trattoria del Porto', 'Carlos Mendes'),
    ])
      AdminOwnershipRequest(
        uid: uid,
        placeId: uid,
        createdAt: DateTime(2026, 11, 1, 9),
        applicant: name,
        place: place,
        location: Place(
          id: uid,
          name: place,
          category: 'Cafeteria e restaurante',
          neighborhood: 'Tirol',
          city: 'Natal',
        ),
      ),
  ], null);
  @override
  Future<AdminRequestPage> decided({Object? cursor}) async => AdminRequestPage([
    AdminOwnershipRequest(
      uid: 'bia',
      placeId: 'cafe',
      createdAt: DateTime(2026, 10, 30),
      applicant: 'Bianca Ferreira',
      place: 'Café da Praça',
      status: 'approved',
      reason: 'Identidade e representação confirmadas na verificação externa.',
    ),
  ], null);
}

void main() {
  setUpAll(loadStitchFonts);
  test(
    'histórico Firestore filtra decisões e preserva ordem e paginação',
    () async {
      final db = FakeFirebaseFirestore();
      for (var i = 0; i < 23; i++) {
        await db.doc('users/u$i').set({'displayName': 'Pessoa $i'});
        await db.doc('places/p$i').set({'name': 'Local $i'});
        await db.doc('users/u$i/ownershipRequests/p$i').set({
          'status': i == 22
              ? 'pending'
              : i.isEven
              ? 'approved'
              : 'rejected',
          'createdAt': Timestamp.fromMillisecondsSinceEpoch(i * 1000),
          'decidedAt': Timestamp.fromMillisecondsSinceEpoch(i * 2000),
        });
      }
      final repo = FirestoreAdminOwnershipRepository(db);
      final first = await repo.decided();
      expect(first.requests.length, 20);
      expect(first.requests.first.uid, 'u21');
      final second = await repo.decided(cursor: first.cursor);
      expect(second.requests.length, 2);
      expect(second.cursor, isNull);
      expect(
        [
          ...first.requests,
          ...second.requests,
        ].any((r) => r.status == 'pending'),
        false,
      );
    },
  );
  for (final scale in [1.0, 2.0]) {
    testWidgets('moderação: abas reais, revogação e layout com fonte $scale', (
      tester,
    ) async {
      const output = String.fromEnvironment('STITCH_CAPTURE_DIR');
      tester.view.physicalSize = Size(
        output.isEmpty || scale != 1 ? 320 : 390,
        1000,
      );
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = PreviewAdmin();
      final auth = FakeAuthRepository(uid: 'operator');
      final access = AdminAccess(auth, repo);
      final vm = AdminOwnershipViewModel(access, repo);
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: RepaintBoundary(
            key: key,
            child: AdminOwnershipView(viewModel: vm),
          ),
        ),
      );
      repo.role.add(true);
      await tester.pumpAndSettle();
      expect(find.text('Helena Prado'), findsOneWidget);
      expect(tester.takeException(), isNull);
      Future<void> capture(String name) async {
        if (output.isEmpty || scale != 1) return;
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final raster = await boundary.toImage();
          final bytes = await raster.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '$output/$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          raster.dispose();
        });
      }

      await capture('moderacao-pendentes-validacao');
      await tester.tap(find.text('Decididas'));
      await tester.pumpAndSettle();
      expect(find.text('Café da Praça'), findsOneWidget);
      expect(find.text('Helena Prado'), findsNothing);
      expect(
        find.textContaining('Identidade e representação confirmadas'),
        findsOneWidget,
      );
      await capture('moderacao-decididas-validacao');
      repo.role.add(false);
      await tester.pumpAndSettle();
      expect(find.text('Café da Praça'), findsNothing);
      expect(find.text('Acesso negado'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      vm.dispose();
      access.dispose();
      auth.dispose();
      await repo.role.close();
    });
  }
}
