import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:naarea/ui/owner/owner_view.dart';
import 'package:naarea/data/firebase/firestore_owner_repository.dart';
import 'package:naarea/data/repositories/owner_repository.dart';
import 'package:naarea/data/repositories/place_repository.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:naarea/data/repositories/auth_repository.dart';
import 'package:naarea/routing/router.dart';
import 'package:naarea/routing/routes.dart';
import 'package:naarea/ui/settings/settings_view.dart';
import 'package:naarea/data/repositories/user_repository.dart';
import 'package:naarea/ui/profile/profile_view_model.dart';
import 'package:naarea/ui/core/follow_events.dart';
import 'package:naarea/data/repositories/admin_ownership_repository.dart';
import 'package:naarea/domain/models/admin_ownership_request.dart';
import 'package:naarea/ui/admin/admin_access.dart';
import 'package:naarea/ui/admin/admin_ownership_view.dart';
import 'package:naarea/ui/admin/admin_ownership_view_model.dart';
import '../support/fakes.dart';

class AdminFake implements AdminOwnershipRepository {
  final role = StreamController<bool>.broadcast(sync: true);
  AdminOwnershipRequest record = AdminOwnershipRequest(
    uid: 'alice',
    placeId: 'p',
    createdAt: DateTime(2026, 10, 30),
    applicant: 'Alice',
    place: 'Local',
  );
  Completer<AdminOwnershipRequest?>? readGate;
  Completer<void>? decisionGate;
  Object? failure, readFailure;
  bool failRefreshAfterDecision = false;
  int decisions = 0, reads = 0;
  @override
  Stream<bool> observeAccess(String uid) => role.stream;
  @override
  Future<AdminRequestPage> pending({Object? cursor}) async {
    reads++;
    return AdminRequestPage([
      cursor == null
          ? record
          : AdminOwnershipRequest(
              uid: 'bob',
              placeId: 'p2',
              createdAt: record.createdAt,
              applicant: 'Bob',
              place: 'Outro local',
            ),
    ], cursor == null ? 'next' : null);
  }

  @override
  Future<AdminOwnershipRequest?> detail(String uid, String placeId) async {
    reads++;
    if (readFailure != null) throw readFailure!;
    return readGate == null ? record : readGate!.future;
  }

  @override
  Future<void> decide({
    required String operator,
    required String uid,
    required String placeId,
    required bool approve,
    required String reason,
  }) async {
    decisions++;
    if (decisionGate != null) await decisionGate!.future;
    if (failure != null) throw failure!;
    if (failRefreshAfterDecision) readFailure = StateError('sem rede');
    record = AdminOwnershipRequest(
      uid: uid,
      placeId: placeId,
      createdAt: record.createdAt,
      applicant: record.applicant,
      place: record.place,
      status: approve ? 'approved' : 'rejected',
      reason: reason.trim(),
    );
  }
}

void main() {
  late AdminFake repo;
  late FakeAuthRepository auth;
  late AdminAccess access;
  setUp(() {
    repo = AdminFake();
    auth = FakeAuthRepository(uid: 'operator');
    access = AdminAccess(auth, repo);
    repo.role.add(false);
  });
  tearDown(() async {
    access.dispose();
    auth.dispose();
    await repo.role.close();
  });
  Future<void> flush() => Future<void>.delayed(Duration.zero);
  test(
    'common user cannot load direct route; role enables paginated queue and revocation clears it',
    () async {
      final vm = AdminOwnershipViewModel(access, repo);
      expect(repo.reads, 0);
      repo.role.add(true);
      await flush();
      expect(vm.requests, hasLength(1));
      await vm.load(more: true);
      expect(vm.requests, hasLength(2));
      expect(vm.requests.map((r) => r.placeId).toSet(), hasLength(2));
      repo.role.add(false);
      expect(vm.requests, isEmpty);
      await vm.load();
      expect(repo.reads, 2);
      vm.dispose();
    },
  );
  test(
    'late detail is discarded after account switch and revocation',
    () async {
      repo.readGate = Completer();
      final vm = AdminOwnershipViewModel(
        access,
        repo,
        uid: 'alice',
        placeId: 'p',
      );
      repo.role.add(true);
      auth.restoreSession('other');
      repo.readGate!.complete(repo.record);
      await flush();
      expect(vm.request, isNull);
      expect(access.enabled, isFalse);
      vm.dispose();
    },
  );
  test(
    'approval is single submit and exposes status/reason after refresh',
    () async {
      final vm = AdminOwnershipViewModel(
        access,
        repo,
        uid: 'alice',
        placeId: 'p',
      );
      repo.role.add(true);
      await flush();
      repo.decisionGate = Completer();
      final operation = vm.decide(true, ' Presencial ');
      await vm.decide(true, 'Outro');
      expect(repo.decisions, 1);
      repo.decisionGate!.complete();
      await operation;
      expect(vm.request!.status, 'approved');
      expect(vm.request!.reason, 'Presencial');
      vm.dispose();
    },
  );
  test(
    'uncertain response blocks repetition until server refresh; conflict reloads',
    () async {
      final vm = AdminOwnershipViewModel(
        access,
        repo,
        uid: 'alice',
        placeId: 'p',
      );
      repo.role.add(true);
      await flush();
      repo.failure = const AdminUncertain();
      await vm.decide(false, 'Motivo');
      await vm.decide(false, 'Motivo');
      expect(repo.decisions, 1);
      expect(vm.uncertain, isTrue);
      await vm.load();
      expect(vm.uncertain, isFalse);
      repo.failure = const AdminConflict();
      await vm.decide(true, 'Motivo');
      expect(vm.message, contains('Conflito'));
      expect(vm.busy, isFalse);
      vm.dispose();
    },
  );
  test(
    'revocation during decision clears detail and discards late result',
    () async {
      final vm = AdminOwnershipViewModel(
        access,
        repo,
        uid: 'alice',
        placeId: 'p',
      );
      repo.role.add(true);
      await flush();
      repo.decisionGate = Completer();
      final operation = vm.decide(true, 'Motivo');
      repo.role.add(false);
      repo.decisionGate!.complete();
      await operation;
      expect(vm.request, isNull);
      expect(vm.message, isNull);
      vm.dispose();
    },
  );
  testWidgets(
    'direct unauthorized screen hides data and decision; approval needs verification and final confirmation',
    (tester) async {
      access.dispose();
      access = AdminAccess(auth, repo);
      repo.role.add(false);
      final vm = AdminOwnershipViewModel(
        access,
        repo,
        uid: 'alice',
        placeId: 'p',
      );
      await tester.pumpWidget(
        MaterialApp(home: AdminOwnershipView(viewModel: vm)),
      );
      expect(find.text('Acesso negado'), findsOneWidget);
      expect(find.text('Alice'), findsNothing);
      repo.role.add(true);
      await tester.pump();
      await tester.pump();
      expect(vm.busy, isFalse);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Verificado presencialmente',
      );
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Aprovar'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.ensureVisible(find.text('Aprovar'));
      await tester.tap(find.text('Aprovar'));
      await tester.pumpAndSettle();
      expect(find.text('Confirmar aprovação?'), findsOneWidget);
      expect(repo.decisions, 0);
      repo.role.add(false);
      await tester.pumpAndSettle();
      expect(find.textContaining('O solicitante verá'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirmar'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      vm.dispose();
    },
  );
  testWidgets(
    'real admin routes deny common user; enabled queue opens detail and revocation hides both',
    (tester) async {
      access.dispose();
      access = AdminAccess(auth, repo);
      repo.role.add(false);
      final router = buildRouter(auth)..go(Routes.adminRequests);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthRepository>.value(value: auth),
            ChangeNotifierProvider<AdminAccess>.value(value: access),
            Provider<AdminOwnershipRepository>.value(value: repo),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Acesso negado'), findsOneWidget);
      expect(repo.reads, 0);
      repo.role.add(true);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Local'));
      await tester.pumpAndSettle();
      expect(find.text('Abrir perfil do solicitante'), findsOneWidget);
      repo.role.add(false);
      await tester.pumpAndSettle();
      expect(find.text('Acesso negado'), findsOneWidget);
      expect(find.textContaining('Solicitante: Alice'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    },
  );
  testWidgets(
    'self profile menu offers Administration only with enabled membership',
    (tester) async {
      access.dispose();
      access = AdminAccess(auth, repo);
      repo.role.add(false);
      final users = FakeUserRepository()..addUser('operator', 'Operador');
      final events = FollowEvents();
      final vm = ProfileViewModel(
        uid: 'operator',
        authRepository: auth,
        userRepository: users,
        reviewRepository: FakeReviewRepository(),
        followEvents: events,
        visitRepository: FakeVisitRepository(),
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AdminAccess>.value(value: access),
            ChangeNotifierProvider<AuthRepository>.value(value: auth),
            Provider<UserRepository>.value(value: users),
          ],
          child: MaterialApp.router(
            routerConfig: GoRouter(
              routes: [
                GoRoute(path: '/', builder: (_, _) => const SettingsView()),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Administração'), findsNothing);
      repo.role.add(true);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.widgetWithText(ListTile, 'Administração'),
        250,
      );
      await tester.pumpAndSettle();
      expect(find.text('Administração'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
      vm.dispose();
      events.dispose();
    },
  );
  test(
    'refresh falho bloqueia decisão antiga e preserva falha após decisão concluída',
    () async {
      final vm = AdminOwnershipViewModel(
        access,
        repo,
        uid: 'alice',
        placeId: 'p',
      );
      repo.role.add(true);
      await flush();
      repo.readFailure = StateError('rede');
      await vm.load();
      await vm.decide(true, 'Motivo');
      expect(repo.decisions, 0);
      expect(vm.uncertain, isTrue);
      repo.readFailure = null;
      await vm.load();
      repo.failRefreshAfterDecision = true;
      await vm.decide(true, 'Motivo');
      expect(vm.message, contains('concluída'));
      expect(vm.message, contains('indisponível'));
      expect(vm.uncertain, isTrue);
      vm.dispose();
    },
  );
  test(
    'erro de papel e permission-denied apagam dados; retry reinicia observação',
    () async {
      final vm = AdminOwnershipViewModel(
        access,
        repo,
        uid: 'alice',
        placeId: 'p',
      );
      repo.role.add(true);
      await flush();
      expect(vm.request, isNotNull);
      repo.role.addError(StateError('terminal'));
      expect(access.state, AdminAccessState.error);
      expect(vm.request, isNull);
      access.retry();
      expect(access.state, AdminAccessState.loading);
      repo.role.add(true);
      await flush();
      expect(vm.request, isNotNull);
      repo.readFailure = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
      await vm.load();
      expect(access.state, AdminAccessState.error);
      expect(vm.request, isNull);
      vm.dispose();
    },
  );
  test(
    'titular existente bloqueia aprovação no VM e permite reprovar',
    () async {
      repo.record = AdminOwnershipRequest(
        uid: 'alice',
        placeId: 'p',
        createdAt: DateTime(2026),
        applicant: 'Alice',
        place: 'Local',
        ownerUid: 'titular',
      );
      final vm = AdminOwnershipViewModel(
        access,
        repo,
        uid: 'alice',
        placeId: 'p',
      );
      repo.role.add(true);
      await flush();
      await vm.decide(true, 'Motivo');
      expect(repo.decisions, 0);
      await vm.decide(false, 'Motivo');
      expect(repo.decisions, 1);
      vm.dispose();
    },
  );
  for (final approve in [true, false]) {
    testWidgets(
      'conclui confirmação de ${approve ? 'aprovação' : 'reprovação'} com alvo e motivo aparado',
      (tester) async {
        access.dispose();
        access = AdminAccess(auth, repo);
        repo.role.add(false);
        final vm = AdminOwnershipViewModel(
          access,
          repo,
          uid: 'alice',
          placeId: 'p',
        );
        await tester.pumpWidget(
          MaterialApp(home: AdminOwnershipView(viewModel: vm)),
        );
        repo.role.add(true);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '  Conferido  ');
        await tester.pump();
        if (approve) {
          await tester.tap(find.byType(Checkbox));
          await tester.pump();
        }
        final label = approve ? 'Aprovar' : 'Reprovar';
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(find.textContaining('Solicitante: Alice'), findsWidgets);
        expect(find.textContaining('Estabelecimento: Local'), findsOneWidget);
        expect(
          find.textContaining('Identificador do local: p'),
          findsOneWidget,
        );
        await tester.tap(find.text('Confirmar'));
        await tester.pumpAndSettle();
        expect(repo.decisions, 1);
        expect(repo.record.reason, 'Conferido');
        expect(find.text('Motivo: Conferido'), findsOneWidget);
        expect(
          find.textContaining(
            approve ? 'Status: Aprovado' : 'Status: Reprovado',
          ),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
        vm.dispose();
      },
    );
  }
  for (final status in ['approved', 'rejected', 'revoked']) {
    testWidgets('solicitante vê motivos corretos em $status', (tester) async {
      final db = FakeFirebaseFirestore();
      await db.doc('users/operator/ownershipRequests/p').set({
        'status': status,
        'reason': 'Decisão original',
        'revocation': {'reason': 'Representação encerrada'},
      });
      if (status == 'approved') {
        await db.doc('placeOwners/p').set({'uid': 'operator'});
      }
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthRepository>.value(value: auth),
            Provider<OwnerRepository>.value(
              value: FirestoreOwnerRepository(db),
            ),
            Provider<PlaceRepository>.value(
              value: FakePlaceRepository([
                const Place(
                  id: 'p',
                  name: 'Local',
                  category: 'Bar',
                  neighborhood: '',
                  city: '',
                ),
              ]),
            ),
          ],
          child: const MaterialApp(home: OwnerView()),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          status == 'revoked'
              ? 'Motivo da aprovação original: Decisão original'
              : 'Motivo: Decisão original',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Motivo da revogação: Representação encerrada'),
        status == 'revoked' ? findsOneWidget : findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    });
  }
  test(
    'permission-denied na decisão descarta detalhe e exige revalidar papel',
    () async {
      final vm = AdminOwnershipViewModel(
        access,
        repo,
        uid: 'alice',
        placeId: 'p',
      );
      repo.role.add(true);
      await flush();
      repo.failure = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
      await vm.decide(false, 'Motivo');
      expect(vm.request, isNull);
      expect(access.state, AdminAccessState.error);
      vm.dispose();
    },
  );
}
