import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/repositories/auth_repository.dart';
import '../domain/models/place.dart';
import '../ui/auth/auth_view.dart';
import '../ui/auth/auth_view_model.dart';
import '../ui/core/app_shell.dart';
import '../ui/core/follow_events.dart';
import '../ui/core/view_model_host.dart';
import '../ui/feed/feed_view.dart';
import '../ui/feed/feed_view_model.dart';
import '../ui/lists/lists_store.dart';
import '../ui/nearby/nearby_view.dart';
import '../ui/nearby/nearby_view_model.dart';
import '../ui/place/place_detail_view.dart';
import '../ui/place/place_detail_view_model.dart';
import '../ui/people/people_view.dart';
import '../ui/people/people_view_model.dart';
import '../ui/profile/profile_view.dart';
import '../ui/profile/profile_view_model.dart';
import '../ui/review/place_picker_view.dart';
import '../ui/review/place_picker_view_model.dart';
import '../ui/review/review_view.dart';
import '../ui/review/review_view_model.dart';
import '../ui/saved/saved_places_store.dart';
import '../ui/saved/saved_view.dart';
import '../ui/saved/saved_view_model.dart';
import 'routes.dart';

/// Decide para onde redirecionar conforme o estado de autenticação.
/// Função pura para ser testável.
String? authRedirect({
  required bool isInitialized,
  required bool isSignedIn,
  required String location,
}) {
  final atSplash = location == Routes.splash;
  final atAuth = location == Routes.login || location == Routes.signUp;
  if (!isInitialized) return atSplash ? null : Routes.splash;
  if (!isSignedIn) return atAuth ? null : Routes.login;
  if (atAuth || atSplash) return Routes.feed;
  return null;
}

GoRouter buildRouter(AuthRepository auth) {
  return GoRouter(
    initialLocation: Routes.feed,
    refreshListenable: auth,
    redirect: (context, state) => authRedirect(
      isInitialized: auth.isInitialized,
      isSignedIn: auth.isSignedIn,
      location: state.matchedLocation,
    ),
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (context, state) =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      GoRoute(
        path: Routes.login,
        builder: (context, state) => ViewModelHost<AuthViewModel>(
          create: (context) => AuthViewModel(authRepository: context.read()),
          builder: (context, vm) => AuthView(isSignUp: false, viewModel: vm),
        ),
      ),
      GoRoute(
        path: Routes.signUp,
        builder: (context, state) => ViewModelHost<AuthViewModel>(
          create: (context) => AuthViewModel(authRepository: context.read()),
          builder: (context, vm) => AuthView(isSignUp: true, viewModel: vm),
        ),
      ),
      // Telas principais com a barra inferior (Amigos · Perto · Quero ir ·
      // Pessoas).
      // Cada aba guarda o próprio estado (IndexedStack).
      StatefulShellRoute(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        navigatorContainerBuilder: (context, shell, children) => AppBranchStack(
          currentIndex: shell.currentIndex,
          children: children,
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.feed,
                builder: (context, state) => ViewModelHost<FeedViewModel>(
                  create: (context) => FeedViewModel(
                    authRepository: context.read(),
                    userRepository: context.read(),
                    reviewRepository: context.read(),
                    placeRepository: context.read(),
                    followEvents: context.read<FollowEvents>(),
                  ),
                  builder: (context, vm) => FeedView(viewModel: vm),
                ),
              ),
            ],
          ),
          // "Perto" (F10): criado só na 1ª visita à aba (branch sem preload),
          // então a permissão é pedida no contexto dela.
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.nearby,
                builder: (context, state) => ViewModelHost<NearbyViewModel>(
                  create: (context) => NearbyViewModel(
                    locationService: context.read(),
                    placeRepository: context.read(),
                    authRepository: context.read(),
                    userRepository: context.read(),
                    reviewRepository: context.read(),
                    followEvents: context.read<FollowEvents>(),
                    savedStore: context.read<SavedPlacesStore?>(),
                  ),
                  builder: (context, vm) => NearbyView(viewModel: vm),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.saved,
                builder: (context, state) => ViewModelHost<SavedViewModel>(
                  create: (context) => SavedViewModel(
                    store: context.read(),
                    placeRepository: context.read(),
                    lists: context.read<ListsStore?>(),
                  ),
                  builder: (context, vm) => SavedView(viewModel: vm),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.people,
                builder: (context, state) => ViewModelHost<PeopleViewModel>(
                  create: (context) => PeopleViewModel(
                    authRepository: context.read(),
                    userRepository: context.read(),
                    followEvents: context.read<FollowEvents>(),
                  ),
                  builder: (context, vm) => PeopleView(viewModel: vm),
                ),
              ),
            ],
          ),
        ],
      ),
      // Fora do shell: cobre a barra inferior. Abre só com o id (link direto,
      // reload na web, aba "Quero ir"); `extra` (FeedItem/Place) só adianta
      // a primeira pintura.
      GoRoute(
        path: Routes.placeDetailPattern,
        builder: (context, state) {
          final placeId = state.pathParameters['placeId']!;
          return ViewModelHost<PlaceDetailViewModel>(
            key: ValueKey('place-$placeId'),
            create: (context) => PlaceDetailViewModel(
              placeId: placeId,
              initial: state.extra,
              authRepository: context.read(),
              userRepository: context.read(),
              placeRepository: context.read(),
              reviewRepository: context.read(),
              followEvents: context.read<FollowEvents>(),
            ),
            builder: (context, vm) => PlaceDetailView(viewModel: vm),
          );
        },
      ),
      // Perfil simples de uma pessoa (F06), fora do shell como o detalhe.
      GoRoute(
        path: Routes.personPattern,
        builder: (context, state) {
          final uid = state.pathParameters['uid']!;
          return ViewModelHost<ProfileViewModel>(
            key: ValueKey('person-$uid'),
            create: (context) => ProfileViewModel(
              uid: uid,
              authRepository: context.read(),
              userRepository: context.read(),
              reviewRepository: context.read(),
              followEvents: context.read<FollowEvents>(),
            ),
            builder: (context, vm) => ProfileView(viewModel: vm),
          );
        },
      ),
      GoRoute(
        path: Routes.pickPlace,
        builder: (context, state) => ViewModelHost<PlacePickerViewModel>(
          create: (context) =>
              PlacePickerViewModel(placeRepository: context.read()),
          builder: (context, vm) => PlacePickerView(viewModel: vm),
        ),
        routes: [
          GoRoute(
            path: ':placeId',
            // Sem o Place (ex.: deep link / reload na web) volta para a escolha.
            redirect: (context, state) =>
                state.extra is Place ? null : Routes.pickPlace,
            builder: (context, state) => ViewModelHost<ReviewViewModel>(
              create: (context) => ReviewViewModel(
                place: state.extra! as Place,
                authRepository: context.read(),
                userRepository: context.read(),
                reviewRepository: context.read(),
                photoPicker: context.read(),
                compress: compressPhotoInBackground,
              ),
              builder: (context, vm) => ReviewView(viewModel: vm),
            ),
          ),
        ],
      ),
    ],
  );
}
