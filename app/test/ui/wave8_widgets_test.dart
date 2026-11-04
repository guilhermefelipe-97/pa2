import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/data/firebase/firestore_review_repository.dart';
import 'package:naarea/data/firebase/firestore_visit_repository.dart';
import 'package:naarea/data/repositories/auth_repository.dart';
import 'package:naarea/data/taste_match_service.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/domain/models/scores.dart';
import 'package:naarea/ui/core/bill_extras_picker.dart';
import 'package:naarea/ui/people/taste_match_badge.dart';
import 'package:naarea/ui/review/review_view.dart';
import 'package:naarea/ui/review/review_view_model.dart';
import 'package:naarea/ui/visit/visit_view_model.dart';
import 'package:provider/provider.dart';

import '../support/builders.dart';
import '../support/fakes.dart';

const _place = Place(
  id: 'p',
  name: 'Restaurante da Vó',
  category: 'Restaurante',
  neighborhood: 'Alecrim',
  city: 'Natal',
);

ReviewViewModel _reviewVm(FakeReviewRepository reviews) => ReviewViewModel(
  place: _place,
  authRepository: FakeAuthRepository(uid: 'me'),
  userRepository: FakeUserRepository()..addUser('me', 'Eu'),
  reviewRepository: reviews,
  photoPicker: FakePhotoPicker(),
  compress: (b) async => b,
);

void main() {
  final now = DateTime.utc(2026, 11, 4, 21);

  group('F28 formulários', () {
    test(
      'avaliação envia couvert e taxa; limpar volta a sem resposta',
      () async {
        final reviews = FakeReviewRepository();
        final vm = _reviewVm(reviews)
          ..setFood(4)
          ..setCouvert(true)
          ..setServiceFee(false)
          ..setServiceFee(null)
          ..toggleTag('marmita');
        expect(await vm.submit(), isTrue);
        final sent = reviews.created.single;
        expect(sent.couvert, isTrue);
        expect(sent.serviceFee, isNull);
        expect(sent.tags, ['marmita']);
      },
    );

    test('visita envia couvert e taxa', () async {
      final visits = FakeVisitRepository()..clock = () => now;
      final vm = VisitViewModel(
        place: _place,
        authRepository: FakeAuthRepository(uid: 'me'),
        userRepository: FakeUserRepository()..addUser('me', 'Eu'),
        visitRepository: visits,
        clock: () => now,
      );
      await vm.checkLock();
      vm
        ..setCouvert(false)
        ..setServiceFee(true);
      expect(await vm.submit(), isTrue);
      expect(visits.created.single.couvert, isFalse);
      expect(visits.created.single.serviceFee, isTrue);
    });

    testWidgets('formulário mostra Comida caseira e perguntas da conta', (
      tester,
    ) async {
      final vm = _reviewVm(FakeReviewRepository());
      await tester.pumpWidget(MaterialApp(home: ReviewView(viewModel: vm)));
      await tester.pumpAndSettle();
      final chip = find.byKey(const Key('review-tag-self-service'));
      await tester.scrollUntilVisible(
        chip,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Comida caseira'), findsOneWidget);
      expect(find.text('self-service por quilo'), findsOneWidget);
      await tester.tap(chip);
      await tester.pump();
      expect(vm.tags, contains('self-service'));

      final extras = find.text('Na conta: couvert e taxa (opcional)');
      await tester.scrollUntilVisible(
        extras,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(extras);
      await tester.pumpAndSettle();
      final yes = find.byKey(const Key('couvert-true'));
      await tester.ensureVisible(yes);
      await tester.pumpAndSettle();
      await tester.tap(yes);
      await tester.pump();
      expect(vm.couvert, isTrue);
      await tester.tap(yes);
      await tester.pump();
      expect(vm.couvert, isNull);
    });

    testWidgets(
      'ficha mostra maioria do couvert e esconde taxa sem conclusão',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BillExtrasSection(
                now: now,
                activities: [
                  review(authorId: 'a', couvert: true, createdAt: now),
                  visit(
                    authorId: 'b',
                    couvert: true,
                    serviceFee: true,
                    createdAt: now,
                  ),
                ],
              ),
            ),
          ),
        );
        expect(find.text('Cobra couvert · 2 de 2 relatos'), findsOneWidget);
        expect(find.textContaining('Taxa de 10%'), findsNothing);
      },
    );
  });

  group('F28 persistência', () {
    test(
      'lê couvert/taxa gravados; valor inválido vira sem resposta',
      () async {
        final db = FakeFirebaseFirestore();
        final base = {
          'authorId': 'a',
          'authorName': 'Ana',
          'placeId': 'p',
          'placeName': 'Local',
          'food': 4,
          'ambience': null,
          'service': null,
          'companion': null,
          'createdAt': Timestamp.fromDate(now),
        };
        await db.doc('reviews/ok').set({
          ...base,
          'couvert': true,
          'serviceFee': false,
        });
        await db.doc('reviews/bad').set({...base, 'couvert': 'sim'});
        await db.doc('visits/v').set({
          'authorId': 'a',
          'authorName': 'Ana',
          'placeId': 'p',
          'placeName': 'Local',
          'companion': null,
          'couvert': false,
          'createdAt': Timestamp.fromDate(now),
        });
        final reviews = (await db.collection('reviews').get()).docs
            .map(FirestoreReviewRepository.fromDoc)
            .toList();
        final ok = reviews.firstWhere((r) => r!.id == 'ok')!;
        final bad = reviews.firstWhere((r) => r!.id == 'bad')!;
        expect((ok.couvert, ok.serviceFee), (true, false));
        expect(bad.couvert, isNull);
        final visit = FirestoreVisitRepository.parse(
          (await db.collection('visits').get()).docs.single,
        )!;
        expect(visit.couvert, isFalse);
        expect(visit.serviceFee, isNull);
      },
    );
  });

  group('F07 serviço e selo', () {
    FakeReviewRepository reviewsFor() => FakeReviewRepository()
      ..stored.addAll([
        for (final p in ['a', 'b', 'c']) ...[
          review(authorId: 'me', placeId: p, scores: Scores(food: 5)),
          review(authorId: 'ana', placeId: p, scores: Scores(food: 4)),
          review(authorId: 'bia', placeId: p, scores: Scores(food: 1)),
        ],
      ]);

    test('compara com cada pessoa num lote só e nunca consigo mesmo', () async {
      final service = TasteMatchService(reviewsFor(), clock: () => now);
      final results = await Future.wait([
        service.matchFor('me', 'ana'),
        service.matchFor('me', 'bia'),
        service.matchFor('me', 'me'),
      ]);
      expect(results[0].similar, isTrue);
      expect(results[0].commonPlaces, 3);
      expect(results[1].similar, isFalse);
      expect(results[2].commonPlaces, 0);
    });

    testWidgets('selo aparece para gosto parecido e some para o resto', (
      tester,
    ) async {
      final service = TasteMatchService(reviewsFor(), clock: () => now);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthRepository>.value(
              value: FakeAuthRepository(uid: 'me'),
            ),
            Provider<TasteMatchService>.value(value: service),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  TasteMatchBadge(uid: 'ana', detailed: true),
                  TasteMatchBadge(uid: 'bia'),
                  TasteMatchBadge(uid: 'me'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Gosto parecido · em 3 lugares em comum'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('taste-match-bia')), findsNothing);
      expect(find.byKey(const ValueKey('taste-match-me')), findsNothing);
    });
  });
}
