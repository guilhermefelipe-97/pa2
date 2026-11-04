import 'data/repositories/privacy_repository.dart';
import 'data/repositories/profile_stats_repository.dart';
import 'data/firebase/firestore_profile_stats_repository.dart';
import 'data/repositories/profile_editor_repository.dart';
import 'data/repositories/profile_media_repository.dart';
import 'data/repositories/account_repository.dart';
import 'data/firebase/firestore_profile_editor_repository.dart';
import 'data/firebase/firestore_profile_media_repository.dart';
import 'data/firebase/firebase_account_repository.dart';
import 'data/repositories/place_photo_repository.dart';
import 'data/firebase/firestore_place_photo_repository.dart';
import 'data/services/place_photo_picker.dart';
import 'data/repositories/queue_repository.dart';
import 'data/repositories/reputation_repository.dart';
import 'data/repositories/sponsorship_repository.dart';
import 'data/firebase/firestore_privacy_repository.dart';
import 'data/firebase/firestore_queue_repository.dart';
import 'data/firebase/firestore_reputation_repository.dart';
import 'data/firebase/firestore_sponsorship_repository.dart';
import 'data/firebase/firestore_place_history_repository.dart';
import 'data/repositories/place_history_repository.dart';
import 'data/sponsorship_floor_reader.dart';
import 'ui/share/share_service.dart';
import 'data/taste_match_service.dart';
import 'data/repositories/admin_ownership_repository.dart';
import 'data/firebase/firestore_admin_ownership_repository.dart';
import 'ui/admin/admin_access.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'data/catalog/catalog_place_repository.dart';
import 'data/firebase/firebase_auth_repository.dart';
import 'data/firebase/firestore_lists_repository.dart';
import 'data/firebase/firestore_open_report_repository.dart';
import 'data/firebase/firestore_place_repository.dart';
import 'data/firebase/firestore_review_photo_repository.dart';
import 'data/firebase/firestore_review_repository.dart';
import 'data/firebase/firestore_saved_repository.dart';
import 'data/firebase/firestore_user_repository.dart';
import 'data/firebase/firestore_visit_repository.dart';
import 'data/photon/photon_client.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/lists_repository.dart';
import 'data/repositories/open_report_repository.dart';
import 'data/repositories/place_repository.dart';
import 'data/repositories/review_photo_repository.dart';
import 'data/repositories/review_repository.dart';
import 'data/repositories/saved_repository.dart';
import 'data/repositories/user_repository.dart';
import 'data/repositories/visit_repository.dart';
import 'data/services/location_service.dart';
import 'data/services/photo_picker.dart';
import 'firebase_config.dart';
import 'firebase_options.dart';
import 'routing/router.dart';
import 'data/repositories/owner_repository.dart';
import 'data/repositories/owner_workspace_repository.dart';
import 'data/firebase/firestore_owner_workspace_repository.dart';
import 'data/repositories/dietary_repository.dart';
import 'data/repositories/food_tag_repository.dart';
import 'data/firebase/firestore_owner_repository.dart';
import 'data/firebase/firestore_dietary_repository.dart';
import 'ui/dietary/dietary_store.dart';
import 'ui/core/app_clock.dart';
import 'ui/core/follow_events.dart';
import 'ui/core/theme.dart';
import 'ui/lists/lists_store.dart';
import 'ui/saved/saved_places_store.dart';

const bool useEmulator = bool.fromEnvironment('USE_EMULATOR');

const String emulatorHost = String.fromEnvironment('EMULATOR_HOST');

const String photonUrl = String.fromEnvironment(
  'PHOTON_URL',
  defaultValue: PhotonClient.defaultBaseUrl,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: firebaseOptionsFor(
        DefaultFirebaseOptions.currentPlatform,
        useEmulator: useEmulator,
      ),
    );
  } on Object catch (e) {
    runApp(SetupErrorApp(error: e));
    return;
  }

  final auth = FirebaseAuth.instance;
  final db = FirebaseFirestore.instance;
  if (useEmulator) {
    final host = emulatorHost.isNotEmpty
        ? emulatorHost
        : defaultTargetPlatform == TargetPlatform.android && !kIsWeb
        ? '10.0.2.2'
        : 'localhost';
    await auth.useAuthEmulator(host, 9099);
    db.useFirestoreEmulator(host, 8080);
  }

  final userRepository = FirestoreUserRepository(db);
  final authRepository = FirebaseAuthRepository(
    auth: auth,
    userRepository: userRepository,
  );

  runApp(
    MultiProvider(
      providers: [
        Provider<PrivacyRepository>(
          create: (_) => FirestorePrivacyRepository(db),
        ),
        Provider<QueueRepository>(create: (_) => FirestoreQueueRepository(db)),
        Provider<ReputationRepository>(
          create: (_) => FirestoreReputationRepository(db),
        ),
        Provider<PlaceHistoryRepository>(
          create: (_) => FirestorePlaceHistoryRepository(db),
        ),
        Provider<SponsorshipFloorReader>(
          create: (context) => SponsorshipFloorReader(context.read()),
        ),
        Provider<SponsorshipRepository>(
          create: (context) => FirestoreSponsorshipRepository(
            db,
            floor: context.read(),
            emulator: useEmulator,
          ),
        ),
        Provider<AppClock>.value(value: const AppClock()),
        Provider<ShareService>.value(value: const SystemShareService()),
        Provider<ProfileStatsRepository>(
          create: (_) => FirestoreProfileStatsRepository(db),
        ),
        Provider<ProfileEditorRepository>(
          create: (_) => FirestoreProfileEditorRepository(db),
        ),
        ChangeNotifierProvider<ProfileMediaRepository>(
          create: (_) => FirestoreProfileMediaRepository(db, authRepository),
        ),
        Provider<AccountRepository>(
          create: (_) => FirebaseAccountRepository(FirebaseAuth.instance),
        ),
        ChangeNotifierProvider<AuthRepository>.value(value: authRepository),
        Provider<UserRepository>.value(value: userRepository),

        Provider<PhotonClient>(
          create: (_) => PhotonClient(baseUrl: photonUrl),
          dispose: (_, client) => client.close(),
        ),

        Provider<PlaceRepository>(
          create: (context) => CatalogPlaceRepository(
            persisted: FirestorePlaceRepository(db),
            photon: context.read<PhotonClient>(),
          ),
        ),
        Provider<AdminOwnershipRepository>(
          create: (_) => FirestoreAdminOwnershipRepository(db),
        ),
        ChangeNotifierProvider<AdminAccess>(
          lazy: false,
          create: (context) => AdminAccess(authRepository, context.read()),
        ),
        Provider<OwnerRepository>(create: (_) => FirestoreOwnerRepository(db)),
        Provider<OwnerWorkspaceRepository>(
          create: (_) => FirestoreOwnerWorkspaceRepository(db),
        ),
        Provider<DietaryRepository>(
          create: (_) => FirestoreDietaryRepository(db),
        ),
        Provider<FoodTagRepository>(
          create: (_) => FirestoreReviewRepository(db),
        ),
        ChangeNotifierProvider<DietaryStore>(
          lazy: false,
          create: (context) => DietaryStore(authRepository, context.read()),
        ),
        Provider<ReviewRepository>(
          create: (_) => FirestoreReviewRepository(db),
        ),
        Provider<TasteMatchService>(
          create: (context) => TasteMatchService(context.read()),
        ),

        Provider<VisitRepository>(create: (_) => FirestoreVisitRepository(db)),

        Provider<OpenReportRepository>(
          create: (_) => FirestoreOpenReportRepository(db),
        ),

        Provider<ReviewPhotoRepository>(
          create: (_) => FirestoreReviewPhotoRepository(
            db,
            authRepository: authRepository,
          ),
          dispose: (_, repo) =>
              (repo as FirestoreReviewPhotoRepository).dispose(),
        ),
        Provider<PhotoPicker>(create: (_) => ImagePickerPhotoPicker()),
        Provider<PlacePhotoRepository>(
          create: (_) => FirestorePlacePhotoRepository(db),
        ),
        Provider<PlacePhotoPicker>(
          create: (_) => ImagePickerPlacePhotoPicker(),
        ),

        Provider<LocationService>(
          create: (_) => const GeolocatorLocationService(),
        ),

        ChangeNotifierProvider<FollowEvents>(create: (_) => FollowEvents()),
        Provider<SavedRepository>(create: (_) => FirestoreSavedRepository(db)),

        ChangeNotifierProvider<SavedPlacesStore>(
          lazy: false,
          create: (context) {
            final places = context.read<PlaceRepository>();
            return SavedPlacesStore(
              authRepository: authRepository,
              savedRepository: context.read(),

              persistPlace: (uid, placeId) =>
                  ensurePlaceForSave(places, uid: uid, placeId: placeId),
            );
          },
        ),
        Provider<ListsRepository>(create: (_) => FirestoreListsRepository(db)),

        ChangeNotifierProvider<ListsStore>(
          lazy: false,
          create: (context) => ListsStore(
            authRepository: authRepository,
            listsRepository: context.read(),
            savedStore: context.read(),
          ),
        ),
      ],
      child: NaAreaApp(router: buildRouter(authRepository)),
    ),
  );
}

class NaAreaApp extends StatelessWidget {
  const NaAreaApp({super.key, required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'NaÁrea',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      themeMode: ThemeMode.light,
      routerConfig: router,
    );
  }
}

class SetupErrorApp extends StatelessWidget {
  const SetupErrorApp({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final message = error is UnsupportedError
        ? (error as UnsupportedError).message ?? error.toString()
        : error.toString();
    return MaterialApp(
      title: 'NaÁrea',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Firebase não configurado',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                SelectableText(message),
                const SizedBox(height: 12),
                const SelectableText(
                  'Em app/: flutterfire configure --project=<id-do-projeto>\n'
                  'Detalhes em app/README.md.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
