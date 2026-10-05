import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'data/firebase/firebase_auth_repository.dart';
import 'data/firebase/firestore_place_repository.dart';
import 'data/firebase/firestore_review_repository.dart';
import 'data/firebase/firestore_saved_repository.dart';
import 'data/firebase/firestore_user_repository.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/place_repository.dart';
import 'data/repositories/review_repository.dart';
import 'data/repositories/saved_repository.dart';
import 'data/repositories/user_repository.dart';
import 'firebase_config.dart';
import 'firebase_options.dart';
import 'routing/router.dart';
import 'ui/core/theme.dart';
import 'ui/saved/saved_places_store.dart';

/// `flutter run --dart-define=USE_EMULATOR=true` usa os emuladores locais
/// (auth :9099, firestore :8080) em vez do projeto real.
const bool useEmulator = bool.fromEnvironment('USE_EMULATOR');

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
    // Ex.: lib/firebase_options.dart ainda é o placeholder. Mostra a instrução
    // em vez de travar com erro não tratado antes do runApp.
    runApp(SetupErrorApp(error: e));
    return;
  }

  final auth = FirebaseAuth.instance;
  final db = FirebaseFirestore.instance;
  if (useEmulator) {
    final host = defaultTargetPlatform == TargetPlatform.android && !kIsWeb
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
        ChangeNotifierProvider<AuthRepository>.value(value: authRepository),
        Provider<UserRepository>.value(value: userRepository),
        Provider<PlaceRepository>(create: (_) => FirestorePlaceRepository(db)),
        Provider<ReviewRepository>(
          create: (_) => FirestoreReviewRepository(db),
        ),
        Provider<SavedRepository>(create: (_) => FirestoreSavedRepository(db)),
        // "Quero ir": ids salvos carregados uma vez por sessão (segue o login).
        ChangeNotifierProvider<SavedPlacesStore>(
          lazy: false,
          create: (context) => SavedPlacesStore(
            authRepository: authRepository,
            savedRepository: context.read(),
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

/// Tela mínima quando o Firebase não pôde ser inicializado.
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
