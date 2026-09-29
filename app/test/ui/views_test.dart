import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/ui/feed/feed_view.dart';
import 'package:naarea/ui/feed/feed_view_model.dart';
import 'package:naarea/ui/review/review_view.dart';
import 'package:naarea/ui/review/review_view_model.dart';

import '../support/builders.dart';
import '../support/fakes.dart';

void main() {
  testWidgets('ReviewView: Enviar só habilita com os 3 eixos', (tester) async {
    final users = FakeUserRepository()..addUser('me', 'Eu');
    final vm = ReviewViewModel(
      place: const Place(id: 'x', name: 'Mangai', category: 'Restaurante', neighborhood: 'Tirol', city: 'Natal'),
      authRepository: FakeAuthRepository(uid: 'me'),
      userRepository: users,
      reviewRepository: FakeReviewRepository(),
    );
    await tester.pumpWidget(MaterialApp(home: ReviewView(viewModel: vm)));

    FilledButton submit() => tester.widget<FilledButton>(find.byKey(const Key('review-submit')));
    expect(submit().onPressed, isNull);

    vm
      ..setFood(4)
      ..setAmbience(4);
    await tester.pump();
    expect(submit().onPressed, isNull);

    vm.setService(4);
    await tester.pump();
    expect(submit().onPressed, isNotNull);
  });

  testWidgets('FeedView: sem seguir ninguém mostra CTA "Encontrar pessoas"', (tester) async {
    final vm = FeedViewModel(
      authRepository: FakeAuthRepository(uid: 'me'),
      userRepository: FakeUserRepository(),
      reviewRepository: FakeReviewRepository(),
    );
    await tester.pumpWidget(MaterialApp(home: FeedView(viewModel: vm)));
    await tester.pumpAndSettle();
    expect(find.text('Encontrar pessoas'), findsOneWidget);
  });

  testWidgets('FeedView: card mostra quem foi, os 3 eixos e o período', (tester) async {
    final users = FakeUserRepository()..followingByUser['me'] = {'a', 'b'};
    final reviews = FakeReviewRepository()
      ..stored.addAll([
        review(authorId: 'a', authorName: 'Ana', placeId: 'x', placeName: 'Mangai',
            createdAt: DateTime.utc(2026, 9, 10, 15)), // 12h Natal
        review(authorId: 'b', authorName: 'Beto', placeId: 'x', placeName: 'Mangai',
            createdAt: DateTime.utc(2026, 9, 10, 23)), // 20h Natal
      ]);
    final vm = FeedViewModel(
      authRepository: FakeAuthRepository(uid: 'me'),
      userRepository: users,
      reviewRepository: reviews,
    );
    await tester.pumpWidget(MaterialApp(home: FeedView(viewModel: vm)));
    await tester.pumpAndSettle();

    expect(find.text('Mangai'), findsOneWidget);
    expect(find.text('Beto e Ana foram aqui'), findsOneWidget);
    expect(find.text('Comida 4/5'), findsNWidgets(2));
    expect(find.text('Ambiente 3/5'), findsNWidgets(2));
    expect(find.text('Atendimento 5/5'), findsNWidgets(2));
    expect(find.text('Noite'), findsOneWidget);
    expect(find.text('Almoço'), findsOneWidget);
  });

  testWidgets('FeedView: erro de rede mostra "Tentar de novo"', (tester) async {
    final users = FakeUserRepository()..failGetFollowing = true;
    final vm = FeedViewModel(
      authRepository: FakeAuthRepository(uid: 'me'),
      userRepository: users,
      reviewRepository: FakeReviewRepository(),
    );
    await tester.pumpWidget(MaterialApp(home: FeedView(viewModel: vm)));
    await tester.pumpAndSettle();
    expect(find.text('Tentar de novo'), findsOneWidget);

    users.failGetFollowing = false;
    await tester.tap(find.text('Tentar de novo'));
    await tester.pumpAndSettle();
    expect(find.text('Encontrar pessoas'), findsOneWidget);
  });
}
