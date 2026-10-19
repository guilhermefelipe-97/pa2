import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:naarea/data/repositories/auth_repository.dart';
import 'package:naarea/data/repositories/lists_repository.dart';
import 'package:naarea/data/repositories/open_report_repository.dart';
import 'package:naarea/data/repositories/place_repository.dart';
import 'package:naarea/data/repositories/review_photo_repository.dart';
import 'package:naarea/data/repositories/review_repository.dart';
import 'package:naarea/data/repositories/saved_repository.dart';
import 'package:naarea/data/repositories/user_repository.dart';
import 'package:naarea/data/repositories/visit_repository.dart';
import 'package:naarea/data/services/location_service.dart';
import 'package:naarea/data/services/photo_picker.dart';
import 'package:naarea/domain/feed.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/routing/router.dart';
import 'package:naarea/ui/core/app_clock.dart';
import 'package:naarea/ui/core/follow_events.dart';
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
    required this.photos,
    required this.picker,
    required this.location,
    required this.visits,
    this.openReports,
  });

  final FakeAuthRepository auth;
  final FakeUserRepository users;
  final FakeReviewRepository reviews;
  final FakePlaceRepository places;
  final FakeSavedRepository saved;
  final FakeListsRepository lists;
  final GoRouter router;
  final FakeReviewPhotoRepository photos;
  final FakePhotoPicker picker;
  final FakeLocationService location;
  final FakeVisitRepository visits;

  /// "Está aberto agora?" (F20): só existe quando o teste o fornece.
  final FakeOpenReportRepository? openReports;

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
  FakeReviewPhotoRepository? photos,
  FakePhotoPicker? picker,
  FakeLocationService? location,
  FakeVisitRepository? visits,
  FakeOpenReportRepository? openReports,
  DateTime Function()? clock,
}) async {
  final loc = location ?? FakeLocationService();
  final u = users ?? (FakeUserRepository()..addUser('me', 'Eu'));
  final auth = FakeAuthRepository(uid: uid, users: u);
  final r = reviews ?? FakeReviewRepository();
  final p = placeRepository ?? FakePlaceRepository(places);
  final s = saved ?? FakeSavedRepository();
  // As Rules das listas (F13) olham quem lê e quem segue quem.
  final l = (lists ?? FakeListsRepository(saved: s))
    ..users ??= u
    ..auth ??= auth;
  final ph = photos ?? FakeReviewPhotoRepository(r.photos);
  final pk = picker ?? FakePhotoPicker();
  final v = visits ?? FakeVisitRepository();
  final router = buildRouter(auth);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<AppClock>.value(value: AppClock(clock)),
        ChangeNotifierProvider<AuthRepository>.value(value: auth),
        Provider<UserRepository>.value(value: u),
        Provider<PlaceRepository>.value(value: p),
        Provider<ReviewRepository>.value(value: r),
        Provider<VisitRepository>.value(value: v),
        if (openReports != null)
          Provider<OpenReportRepository>.value(value: openReports),
        Provider<ReviewPhotoRepository>.value(value: ph),
        Provider<PhotoPicker>.value(value: pk),
        Provider<LocationService>.value(value: loc),
        ChangeNotifierProvider<FollowEvents>(create: (_) => FollowEvents()),
        Provider<SavedRepository>.value(value: s),
        ChangeNotifierProvider<SavedPlacesStore>(
          lazy: false,
          create: (_) => SavedPlacesStore(
            authRepository: auth,
            savedRepository: s,
            clock: clock,
            // Igual ao main.dart (G2): local descoberto nasce antes do salvo.
            persistPlace: (uid, placeId) =>
                ensurePlaceForSave(p, uid: uid, placeId: placeId),
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
    photos: ph,
    picker: pk,
    location: loc,
    visits: v,
    openReports: openReports,
  );
}

/// ViewModel do detalhe cujos fakes têm exatamente os dados do [item]
/// (a recarga confirma o que veio do feed).
PlaceDetailViewModel detailVmFor(FeedItem item, {DateTime? now}) {
  final users = FakeUserRepository()
    ..followingByUser['me'] = {for (final a in item.activities) a.authorId};
  final reviews = FakeReviewRepository()..stored.addAll(item.reviews);
  final visits = FakeVisitRepository()..stored.addAll(item.visits);
  return PlaceDetailViewModel(
    placeId: item.placeId,
    initial: item,
    authRepository: FakeAuthRepository(uid: 'me'),
    userRepository: users,
    placeRepository: FakePlaceRepository([item.place]),
    reviewRepository: reviews,
    followEvents: FollowEvents(),
    visitRepository: visits,
    clock: now == null ? null : () => now,
  );
}
