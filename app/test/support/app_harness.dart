import 'package:naarea/data/repositories/owner_repository.dart';
import 'package:naarea/data/repositories/owner_workspace_repository.dart';
import 'package:naarea/data/repositories/profile_editor_repository.dart';
import 'package:naarea/data/repositories/profile_media_repository.dart';
import 'package:naarea/data/repositories/account_repository.dart';
import 'package:naarea/data/repositories/reputation_repository.dart';
import 'package:naarea/data/repositories/profile_stats_repository.dart';
import 'package:naarea/data/repositories/place_photo_repository.dart';
import 'package:naarea/data/repositories/queue_repository.dart';
import 'package:naarea/data/services/place_photo_picker.dart';
import 'package:naarea/data/repositories/sponsorship_repository.dart';
import 'package:naarea/data/repositories/place_history_repository.dart';
import 'package:naarea/data/sponsorship_floor_reader.dart';
import 'package:naarea/ui/share/share_service.dart';
import 'package:naarea/data/repositories/food_tag_repository.dart';
import 'package:naarea/ui/dietary/dietary_store.dart';
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
  FakeDietaryRepository? dietary,
  FakeOwnerRepository? owners,
  OwnerWorkspaceRepository? ownerWorkspace,
  ProfileEditorRepository? profileEditor,
  ProfileMediaRepository? profileMedia,
  AccountRepository? account,
  ReputationRepository? reputation,
  ProfileStatsRepository? profileStats,
  PlacePhotoRepository? gallery,
  PlacePhotoPicker? galleryPicker,
  QueueRepository? queue,
  SponsorshipRepository? sponsors,
  PlaceHistoryRepository? history,
  ShareService? share,
  FakeFoodTagRepository? foodTags,
  DateTime Function()? clock,
  ThemeData? theme,
  double textScale = 1,
  GlobalKey? captureKey,
}) async {
  final loc = location ?? FakeLocationService();
  final u = users ?? (FakeUserRepository()..addUser('me', 'Eu'));
  final auth = FakeAuthRepository(uid: uid, users: u);
  final r = reviews ?? FakeReviewRepository();
  final p = placeRepository ?? FakePlaceRepository(places);
  final s = saved ?? FakeSavedRepository();

  final l = (lists ?? FakeListsRepository(saved: s))
    ..users ??= u
    ..auth ??= auth;
  final ph = photos ?? FakeReviewPhotoRepository(r.photos);
  final pk = picker ?? FakePhotoPicker();
  final v = visits ?? FakeVisitRepository();
  final ownerRepo = owners ?? FakeOwnerRepository();
  final dietaryRepo = dietary ?? FakeDietaryRepository();
  final router = buildRouter(auth);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<AppClock>.value(value: AppClock(clock)),
        ChangeNotifierProvider<AuthRepository>.value(value: auth),
        Provider<UserRepository>.value(value: u),
        Provider<OwnerRepository>.value(value: ownerRepo),
        if (ownerWorkspace != null)
          Provider<OwnerWorkspaceRepository>.value(value: ownerWorkspace),
        if (profileEditor != null)
          Provider<ProfileEditorRepository>.value(value: profileEditor),
        if (profileMedia != null)
          ChangeNotifierProvider<ProfileMediaRepository>.value(
            value: profileMedia,
          ),
        if (account != null) Provider<AccountRepository>.value(value: account),
        if (reputation != null)
          Provider<ReputationRepository>.value(value: reputation),
        if (profileStats != null)
          Provider<ProfileStatsRepository>.value(value: profileStats),
        if (gallery != null)
          Provider<PlacePhotoRepository>.value(value: gallery),
        if (galleryPicker != null)
          Provider<PlacePhotoPicker>.value(value: galleryPicker),
        if (queue != null) Provider<QueueRepository>.value(value: queue),
        if (sponsors != null)
          Provider<SponsorshipRepository>.value(value: sponsors),
        if (history != null) ...[
          Provider<PlaceHistoryRepository>.value(value: history),
          Provider<SponsorshipFloorReader>.value(
            value: SponsorshipFloorReader(history, clock: clock),
          ),
        ],
        if (share != null) Provider<ShareService>.value(value: share),
        Provider<FoodTagRepository>.value(
          value: foodTags ?? FakeFoodTagRepository(r, ownerRepo),
        ),
        ChangeNotifierProvider<DietaryStore>(
          create: (_) => DietaryStore(auth, dietaryRepo),
          lazy: false,
        ),
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
      child: RepaintBoundary(
        key: captureKey,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: theme,
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
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
