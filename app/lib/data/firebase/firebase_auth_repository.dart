import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import '../../domain/models/user_profile.dart';
import '../repositories/auth_repository.dart';
import '../repositories/user_repository.dart';

/// Invariante: nunca existe sessão "logada" sem `users/{uid}`. Cadastro e login
/// seguram a notificação de auth até o perfil estar garantido.
class FirebaseAuthRepository extends AuthRepository {
  FirebaseAuthRepository({
    required FirebaseAuth auth,
    required UserRepository userRepository,
  }) : _auth = auth,
       _users = userRepository {
    _sub = _auth.authStateChanges().listen((user) {
      if (_gating) return;
      _publish(user?.uid);
    });
  }

  static const String signUpFallbackMessage = 'Não foi possível criar a conta.';
  static const String signInFallbackMessage =
      'Não foi possível entrar. Tente de novo.';
  static const String missingProfileMessage =
      'Sua conta está sem perfil e não pôde ser recuperada. '
      'Crie uma nova conta ou fale com o suporte.';

  final FirebaseAuth _auth;
  final UserRepository _users;
  late final StreamSubscription<User?> _sub;

  bool _initialized = false;
  bool _gating = false;
  String? _uid;

  @override
  bool get isInitialized => _initialized;

  @override
  String? get currentUserId => _uid;

  void _publish(String? uid) {
    if (_initialized && uid == _uid) return;
    _uid = uid;
    _initialized = true;
    notifyListeners();
  }

  @override
  Future<void> signUp({
    required String displayName,
    required String email,
    required String password,
  }) async {
    final name = UserProfile.normalizeName(displayName);
    if (!UserProfile.isNonEmptyName(name)) {
      throw const AuthException('Informe seu nome.');
    }
    if (!UserProfile.isNameWithinLimit(name)) {
      throw const AuthException('Nome muito longo (máx. 60 caracteres).');
    }
    _gating = true;
    User? created;
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      created = cred.user!;
      // Antes do perfil: se falhar, o rollback apaga só a conta de auth e não
      // deixa `users/{uid}` órfão (as Rules negam delete do perfil). Também
      // permite recuperar o perfil no login a partir do displayName do Auth.
      await created.updateDisplayName(name);
      await _users.createProfile(uid: created.uid, displayName: name);
    } on FirebaseAuthException catch (e) {
      await _rollback(created);
      throw AuthException(messageFor(e.code, signUp: true));
    } on Object {
      await _rollback(created);
      throw const AuthException(signUpFallbackMessage);
    } finally {
      _gating = false;
      _publish(_auth.currentUser?.uid);
    }
  }

  /// Conta sem perfil não pode existir: desfaz o cadastro pela metade.
  Future<void> _rollback(User? created) async {
    if (created == null) return;
    try {
      await created.delete();
    } on Object {
      // Se nem o delete funcionar, ao menos não deixa a sessão aberta; o
      // login seguinte tenta recuperar o perfil (ver signIn).
    }
    await _safeSignOut();
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    _gating = true;
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await _ensureProfile(cred.user!);
    } on FirebaseAuthException catch (e) {
      await _safeSignOut();
      throw AuthException(messageFor(e.code, signUp: false));
    } on AuthException {
      await _safeSignOut();
      rethrow;
    } on Object {
      await _safeSignOut();
      throw const AuthException(signInFallbackMessage);
    } finally {
      _gating = false;
      _publish(_auth.currentUser?.uid);
    }
  }

  /// Recria `users/{uid}` a partir do displayName do Auth quando o cadastro
  /// anterior ficou pela metade; sem nome válido, recusa o login.
  Future<void> _ensureProfile(User user) async {
    final profile = await _users.getProfile(user.uid);
    if (profile != null) return;
    final authName = user.displayName ?? '';
    if (!UserProfile.isValidName(authName)) {
      throw const AuthException(missingProfileMessage);
    }
    await _users.createProfile(uid: user.uid, displayName: authName);
  }

  Future<void> _safeSignOut() async {
    try {
      await _auth.signOut();
    } on Object {
      // nada a fazer
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  /// Mensagem para a UI a partir do código do FirebaseAuthException.
  static String messageFor(String code, {required bool signUp}) {
    switch (code) {
      case 'email-already-in-use':
        return 'Este e-mail já está cadastrado.';
      case 'invalid-email':
        return 'E-mail inválido.';
      case 'weak-password':
        return 'Senha fraca: use pelo menos 6 caracteres.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'E-mail ou senha incorretos.';
      case 'network-request-failed':
        return 'Sem conexão. Tente de novo.';
      default:
        return signUp ? signUpFallbackMessage : signInFallbackMessage;
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
