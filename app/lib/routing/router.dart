import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/repositories/auth_repository.dart';
import '../domain/models/place.dart';
import '../ui/auth/auth_view.dart';
import '../ui/auth/auth_view_model.dart';
import '../ui/core/view_model_host.dart';
import '../ui/feed/feed_view.dart';
import '../ui/feed/feed_view_model.dart';
import '../ui/people/people_view.dart';
import '../ui/people/people_view_model.dart';
import '../ui/review/place_picker_view.dart';
import '../ui/review/place_picker_view_model.dart';
import '../ui/review/review_view.dart';
import '../ui/review/review_view_model.dart';
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
      GoRoute(
        path: Routes.feed,
        builder: (context, state) => ViewModelHost<FeedViewModel>(
          create: (context) => FeedViewModel(
            authRepository: context.read(),
            userRepository: context.read(),
            reviewRepository: context.read(),
          ),
          builder: (context, vm) => FeedView(viewModel: vm),
        ),
      ),
      GoRoute(
        path: Routes.people,
        builder: (context, state) => ViewModelHost<PeopleViewModel>(
          create: (context) => PeopleViewModel(
            authRepository: context.read(),
            userRepository: context.read(),
          ),
          builder: (context, vm) => PeopleView(viewModel: vm),
        ),
      ),
      GoRoute(
        path: Routes.pickPlace,
        builder: (context, state) => ViewModelHost<PlacePickerViewModel>(
          create: (context) => PlacePickerViewModel(placeRepository: context.read()),
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
              ),
              builder: (context, vm) => ReviewView(viewModel: vm),
            ),
          ),
        ],
      ),
    ],
  );
}
