import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:naarea/data/repositories/auth_repository.dart';
import 'package:naarea/data/repositories/lists_repository.dart';
import 'package:naarea/data/repositories/place_repository.dart';
import 'package:naarea/data/repositories/review_repository.dart';
import 'package:naarea/data/repositories/saved_repository.dart';
import 'package:naarea/data/repositories/user_repository.dart';
import 'package:naarea/domain/feed.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/routing/router.dart';
import 'package:naarea/ui/lists/lists_store.dart';
import 'package:naarea/ui/place/place_detail_view_model.dart';
import 'package:naarea/ui/saved/saved_places_store.dart';
import 'package:provider/provider.dart';

import 'fakes.dart';

/// App inteiro (router + providers como no main.dart) com fakes.
class TestApp {
  TestApp({
    required this.auth,
    required this.users,
    required this.reviews,
    required this.places,
    required this.saved,
    required this.lists,
    required this.router,
  });

  final FakeAuthRepository auth;
  final FakeUserRepository users;
  final FakeReviewRepository reviews;
  final FakePlaceRepository places;
  final FakeSavedRepository saved;
  final FakeListsRepository lists;
  final GoRouter router;

  SavedPlacesStore store(WidgetTester tester) => Provider.of<SavedPlacesStore>(
    tester.element(find.byType(Navigator).first),
    listen: false,
  );

  ListsStore listsStore(WidgetTester tester) => Provider.of<ListsStore>(
    tester.element(find.byType(Navigator).first),
    listen: false,
  );
}

Future<TestApp> pumpApp(
  WidgetTester tester, {
  String? uid = 'me',
  FakeUserRepository? users,
  FakeReviewRepository? reviews,
  List<Place> places = const [],
  FakePlaceRepository? placeRepository,
  FakeSavedRepository? saved,
  FakeListsRepository? lists,
  DateTime Function()? clock,
}) async {
  final u = users ?? (FakeUserRepository()..addUser('me', 'Eu'));
  final auth = FakeAuthRepository(uid: uid, users: u);
  final r = reviews ?? FakeReviewRepository();
  final p = placeRepository ?? FakePlaceRepository(places);
  final s = saved ?? FakeSavedRepository();
  final l = lists ?? FakeListsRepository(saved: s);
  final router = buildRouter(auth);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthRepository>.value(value: auth),
        Provider<UserRepository>.value(value: u),
        Provider<PlaceRepository>.value(value: p),
        Provider<ReviewRepository>.value(value: r),
        Provider<SavedRepository>.value(value: s),
        ChangeNotifierProvider<SavedPlacesStore>(
          lazy: false,
          create: (_) => SavedPlacesStore(
            authRepository: auth,
            savedRepository: s,
            clock: clock,
          ),
        ),
        Provider<ListsRepository>.value(value: l),
        ChangeNotifierProvider<ListsStore>(
          lazy: false,
          create: (context) => ListsStore(
            authRepository: auth,
            listsRepository: l,
            savedStore: context.read(),
            clock: clock,
          ),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return TestApp(
    auth: auth,
    users: u,
    reviews: r,
    places: p,
    saved: s,
    lists: l,
    router: router,
  );
}

/// ViewModel do detalhe cujos fakes têm exatamente os dados do [item]
/// (a recarga confirma o que veio do feed).
PlaceDetailViewModel detailVmFor(FeedItem item, {DateTime? now}) {
  final users = FakeUserRepository()
    ..followingByUser['me'] = {for (final r in item.reviews) r.authorId};
  final reviews = FakeReviewRepository()..stored.addAll(item.reviews);
  return PlaceDetailViewModel(
    placeId: item.placeId,
    initial: item,
    authRepository: FakeAuthRepository(uid: 'me'),
    userRepository: users,
    placeRepository: FakePlaceRepository([item.place]),
    reviewRepository: reviews,
    clock: now == null ? null : () => now,
  );
}
