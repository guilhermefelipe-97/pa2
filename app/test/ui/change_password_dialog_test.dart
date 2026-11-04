import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:naarea/data/repositories/auth_repository.dart';
import 'package:naarea/data/repositories/account_repository.dart';
import 'package:naarea/ui/core/theme.dart';
import 'package:naarea/ui/profile/change_password_dialog.dart';
import '../support/fakes.dart';
import '../support/profile_edit_fakes.dart';

class GatedAccount extends FakeAccountRepository {
  final done = Completer<void>();
  int calls = 0;
  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    calls++;
    await done.future;
  }
}

Future<void> open(
  WidgetTester tester,
  FakeAuthRepository auth,
  AccountRepository account, {
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthRepository>.value(value: auth),
        Provider<AccountRepository>.value(value: account),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showChangePasswordDialog(context),
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

Future<void> fill(
  WidgetTester tester, {
  String current = 'senha-atual',
  String confirmation = 'senha-nova',
}) async {
  await tester.enterText(
    find.byKey(const Key('password-modal-current')),
    current,
  );
  await tester.enterText(
    find.byKey(const Key('password-modal-new')),
    'senha-nova',
  );
  await tester.enterText(
    find.byKey(const Key('password-modal-confirm')),
    confirmation,
  );
}

void main() {
  testWidgets(
    'modal valida confirmação, autentica senha atual, permite corrigir e fecha no sucesso',
    (tester) async {
      final auth = FakeAuthRepository(uid: 'me'),
          account = FakeAccountRepository();
      await open(tester, auth, account);
      await fill(tester, current: 'errada', confirmation: 'diferente');
      await tester.tap(find.byKey(const Key('password-modal-save')));
      await tester.pumpAndSettle();
      expect(find.text('As senhas não coincidem.'), findsOneWidget);
      expect(account.passwordChanges, 0);
      await tester.enterText(
        find.byKey(const Key('password-modal-confirm')),
        'senha-nova',
      );
      await tester.tap(find.byKey(const Key('password-modal-save')));
      await tester.pumpAndSettle();
      expect(find.text('Senha atual incorreta.'), findsOneWidget);
      expect(account.passwordChanges, 0);
      await tester.enterText(
        find.byKey(const Key('password-modal-current')),
        'senha-atual',
      );
      await tester.tap(find.byKey(const Key('password-modal-save')));
      await tester.pumpAndSettle();
      expect(account.passwordChanges, 1);
      expect(find.byType(ChangePasswordDialog), findsNothing);
      expect(find.text('Senha atualizada.'), findsOneWidget);
    },
  );
  testWidgets(
    'bloqueia duplicação e descarte durante envio; falha permite tentar novamente',
    (tester) async {
      final auth = FakeAuthRepository(uid: 'me'), account = GatedAccount();
      await open(tester, auth, account);
      await fill(tester);
      await tester.tap(find.byKey(const Key('password-modal-save')));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('password-modal-save')))
            .onPressed,
        isNull,
      );
      expect(account.calls, 1);
      account.done.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Verifique sua conexão'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('password-modal-save')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.byType(ChangePasswordDialog), findsNothing);
    },
  );
  testWidgets(
    'troca de conta oculta campos e descarta confirmação de operação antiga',
    (tester) async {
      final auth = FakeAuthRepository(uid: 'me'), account = GatedAccount();
      await open(tester, auth, account);
      await fill(tester);
      await tester.tap(find.byKey(const Key('password-modal-save')));
      await tester.pump();
      auth.restoreSession('other');
      await tester.pump();
      expect(find.byKey(const Key('password-modal-current')), findsNothing);
      account.done.complete();
      await tester.pumpAndSettle();
      expect(find.text('Senha atualizada.'), findsNothing);
      expect(find.text('Conta alterada. Entre novamente.'), findsOneWidget);
    },
  );
  testWidgets(
    'modal com teclado em 320dp e fonte 2x permite rolar sem overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.reset);
      await open(
        tester,
        FakeAuthRepository(uid: 'me'),
        FakeAccountRepository(),
        scale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsWidgets);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
