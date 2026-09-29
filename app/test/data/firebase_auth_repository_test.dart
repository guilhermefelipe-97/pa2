import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';
import 'package:naarea/data/firebase/firebase_auth_repository.dart';
import 'package:naarea/data/firebase/firestore_user_repository.dart';
import 'package:naarea/data/repositories/auth_repository.dart';
import 'package:naarea/domain/models/user_profile.dart';

/// Repositório real (sobre o fake Firestore) com possibilidade de falhar
/// no createProfile.
class _FlakyUserRepository extends FirestoreUserRepository {
  _FlakyUserRepository(super.db);

  bool failCreate = false;
  int createCalls = 0;
  final Set<String> written = {};

  @override
  Future<void> createProfile({required String uid, required String displayName}) async {
    createCalls++;
    if (failCreate) throw Exception('permission-denied');
    await super.createProfile(uid: uid, displayName: displayName);
    written.add(uid);
  }
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeFirebaseFirestore db;
  late _FlakyUserRepository users;

  setUp(() {
    db = FakeFirebaseFirestore();
    users = _FlakyUserRepository(db);
  });

  test('inicializa com "deslogado" a partir do authStateChanges', () async {
    final repo = FirebaseAuthRepository(auth: MockFirebaseAuth(), userRepository: users);
    expect(repo.isInitialized, isFalse);
    await _settle();
    expect(repo.isInitialized, isTrue);
    expect(repo.isSignedIn, isFalse);
  });

  group('signUp', () {
    test('não notifica "logado" antes de users/{uid} existir', () async {
      final auth = MockFirebaseAuth();
      final repo = FirebaseAuthRepository(auth: auth, userRepository: users);
      await _settle();

      final violations = <String>[];
      var signedInNotifications = 0;
      repo.addListener(() {
        final uid = repo.currentUserId;
        if (uid == null) return;
        signedInNotifications++;
        // Checagem síncrona no momento exato da notificação.
        if (!users.written.contains(uid)) violations.add(uid);
      });

      await repo.signUp(displayName: '  Bianca ', email: 'bia@x.com', password: '123456');
      await _settle();

      expect(repo.isSignedIn, isTrue);
      expect(signedInNotifications, 1);
      expect(violations, isEmpty);
      final profile = await users.getProfile(repo.currentUserId!);
      expect(profile!.displayName, 'Bianca');
      expect(auth.currentUser!.displayName, 'Bianca', reason: 'updateDisplayName antes do perfil');
    });

    test('createProfile falha: rollback e ninguém fica logado', () async {
      users.failCreate = true;
      final auth = MockFirebaseAuth();
      final repo = FirebaseAuthRepository(auth: auth, userRepository: users);
      await _settle();

      await expectLater(
        repo.signUp(displayName: 'Bia', email: 'bia@x.com', password: '123456'),
        throwsA(isA<AuthException>().having(
            (e) => e.message, 'message', FirebaseAuthRepository.signUpFallbackMessage)),
      );
      await _settle();
      expect(repo.currentUserId, isNull);
      expect(auth.currentUser, isNull);
      expect((await db.collection('users').get()).docs, isEmpty);
    });

    test('código de erro conhecido vira mensagem específica', () async {
      final auth = MockFirebaseAuth();
      whenCalling(Invocation.method(#createUserWithEmailAndPassword, null))
          .on(auth)
          .thenThrow(FirebaseAuthException(code: 'email-already-in-use'));
      final repo = FirebaseAuthRepository(auth: auth, userRepository: users);
      await _settle();

      await expectLater(
        repo.signUp(displayName: 'Bia', email: 'bia@x.com', password: '123456'),
        throwsA(isA<AuthException>()
            .having((e) => e.message, 'message', 'Este e-mail já está cadastrado.')),
      );
      expect(users.createCalls, 0);
      expect(repo.isSignedIn, isFalse);
    });

    test('nome vazio ou longo demais é recusado antes de chamar o Auth', () async {
      final repo = FirebaseAuthRepository(auth: MockFirebaseAuth(), userRepository: users);
      await expectLater(repo.signUp(displayName: '  ', email: 'a@b.c', password: '123456'),
          throwsA(isA<AuthException>()));
      await expectLater(
          repo.signUp(
              displayName: 'x' * (UserProfile.maxNameLength + 1), email: 'a@b.c', password: '123456'),
          throwsA(isA<AuthException>()));
      expect(users.createCalls, 0);
    });
  });

  group('signIn', () {
    test('com perfil existente: entra normalmente', () async {
      final auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1', displayName: 'Bia'));
      await users.createProfile(uid: 'u1', displayName: 'Bia');
      users.createCalls = 0;
      final repo = FirebaseAuthRepository(auth: auth, userRepository: users);
      await _settle();

      await repo.signIn(email: 'bia@x.com', password: '123456');
      await _settle();
      expect(repo.currentUserId, 'u1');
      expect(users.createCalls, 0);
    });

    test('sem perfil mas com displayName válido no Auth: recria o perfil', () async {
      final auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1', displayName: 'Bianca'));
      final repo = FirebaseAuthRepository(auth: auth, userRepository: users);
      await _settle();

      await repo.signIn(email: 'bia@x.com', password: '123456');
      await _settle();
      expect(repo.currentUserId, 'u1');
      expect((await users.getProfile('u1'))!.displayName, 'Bianca');
    });

    test('sem perfil e sem nome válido: desloga e explica', () async {
      final auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1', displayName: '   '));
      final repo = FirebaseAuthRepository(auth: auth, userRepository: users);
      await _settle();

      final notified = <String?>[];
      repo.addListener(() => notified.add(repo.currentUserId));

      await expectLater(
        repo.signIn(email: 'bia@x.com', password: '123456'),
        throwsA(isA<AuthException>().having(
            (e) => e.message, 'message', FirebaseAuthRepository.missingProfileMessage)),
      );
      await _settle();
      expect(repo.currentUserId, isNull);
      expect(auth.currentUser, isNull);
      expect(notified.whereType<String>(), isEmpty, reason: 'nunca publicou sessão sem perfil');
    });

    test('credenciais erradas: mensagem de login', () async {
      final auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1', displayName: 'Bia'));
      whenCalling(Invocation.method(#signInWithEmailAndPassword, null))
          .on(auth)
          .thenThrow(FirebaseAuthException(code: 'invalid-credential'));
      final repo = FirebaseAuthRepository(auth: auth, userRepository: users);
      await expectLater(
        repo.signIn(email: 'bia@x.com', password: 'errada'),
        throwsA(isA<AuthException>()
            .having((e) => e.message, 'message', 'E-mail ou senha incorretos.')),
      );
    });
  });

  group('messageFor', () {
    test('códigos conhecidos', () {
      expect(FirebaseAuthRepository.messageFor('email-already-in-use', signUp: true),
          'Este e-mail já está cadastrado.');
      expect(FirebaseAuthRepository.messageFor('invalid-email', signUp: true), 'E-mail inválido.');
      expect(FirebaseAuthRepository.messageFor('weak-password', signUp: true), contains('6'));
      for (final code in ['user-not-found', 'wrong-password', 'invalid-credential']) {
        expect(FirebaseAuthRepository.messageFor(code, signUp: false), 'E-mail ou senha incorretos.');
      }
      expect(FirebaseAuthRepository.messageFor('network-request-failed', signUp: false),
          'Sem conexão. Tente de novo.');
    });

    test('código desconhecido: mensagem depende do fluxo', () {
      expect(FirebaseAuthRepository.messageFor('operation-not-allowed', signUp: true),
          'Não foi possível criar a conta.');
      expect(FirebaseAuthRepository.messageFor('operation-not-allowed', signUp: false),
          'Não foi possível entrar. Tente de novo.');
    });
  });
}
