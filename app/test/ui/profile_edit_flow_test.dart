import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/models/user_profile.dart';
import 'package:naarea/routing/routes.dart';
import 'package:naarea/ui/core/theme.dart';
import 'package:naarea/ui/profile/profile_edit_view.dart';
import '../support/app_harness.dart';
import '../support/builders.dart';
import '../support/fakes.dart';
import '../support/profile_edit_fakes.dart';

void main() {
  testWidgets(
    'Configurações abre edição; salvar @ e bio aparece no perfil e mantém listas',
    (tester) async {
      final users = FakeUserRepository()..addUser('me', 'Bianca');
      final media = FakeProfileMedia(),
          editor = FakeProfileEditor(users, media);
      final app = await pumpApp(
        tester,
        users: users,
        profileEditor: editor,
        profileMedia: media,
        account: FakeAccountRepository(),
      );
      app.router.go(Routes.settings);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bianca'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileEditView), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('profile-username')),
        'bianca.cafes',
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('profile-bio')),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        find.byKey(const Key('profile-bio')),
        'Cafés, amigos e novos sabores.',
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('profile-instagram')),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        find.byKey(const Key('profile-instagram')),
        '@bianca.cafes',
      );
      await tester.tap(find.byKey(const Key('profile-edit-save')));
      await tester.pumpAndSettle();
      expect(editor.writes, 1);
      expect(users.profiles['me']!.instagram, 'bianca.cafes');
      app.router.go('/perfil');
      await tester.pumpAndSettle();
      expect(find.text('@bianca.cafes'), findsOneWidget);
      expect(find.text('Cafés, amigos e novos sabores.'), findsOneWidget);
      expect(find.byKey(const Key('profile-tab-2')), findsOneWidget);
    },
  );
  testWidgets('nova avaliação aparece ao voltar para a aba Perfil', (
    tester,
  ) async {
    final users = FakeUserRepository()..addUser('me', 'Bianca');
    final reviews = FakeReviewRepository();
    final app = await pumpApp(
      tester,
      users: users,
      reviews: reviews,
      places: [place()],
    );
    app.router.go('/perfil');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('profile-empty')),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('profile-empty')), findsOneWidget);
    app.router.go(Routes.feed);
    await tester.pumpAndSettle();
    reviews.stored.add(
      review(
        id: 'minha-nova',
        authorId: 'me',
        authorName: 'Bianca',
        comment: 'Café excelente.',
      ),
    );
    app.router.go('/perfil');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('profile-review-minha-nova')),
      findsOneWidget,
    );
    expect(find.text('Café excelente.'), findsOneWidget);
  });
  testWidgets(
    'alterar e-mail confirma envio e não finge mudar o endereço antes do link',
    (tester) async {
      final account = FakeAccountRepository();
      final app = await pumpApp(tester, account: account);
      app.router.go(Routes.accountSecurity);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('account-new-email')),
        'novo@exemplo.com',
      );
      await tester.enterText(
        find.byKey(const Key('account-email-password')),
        'senha-atual',
      );
      await tester.tap(find.byKey(const Key('account-save-email')));
      await tester.pumpAndSettle();
      expect(account.requestedEmail, 'novo@exemplo.com');
      expect(account.email, 'conta@exemplo.com');
      expect(find.textContaining('O endereço atual só muda'), findsOneWidget);
    },
  );
  testWidgets('senha exige confirmação igual e senha atual correta', (
    tester,
  ) async {
    final account = FakeAccountRepository();
    final app = await pumpApp(tester, account: account);
    app.router.go(Routes.accountSecurity);
    await tester.pumpAndSettle();
    for (final (key, value) in [
      ('account-current-password', 'errada'),
      ('account-new-password', 'nova-senha'),
      ('account-confirm-password', 'diferente'),
    ]) {
      await tester.scrollUntilVisible(
        find.byKey(Key(key)),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.byKey(Key(key)), value);
    }
    await tester.ensureVisible(find.byKey(const Key('account-save-password')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-save-password')));
    await tester.pumpAndSettle();
    expect(account.passwordChanges, 0);
    expect(find.text('As senhas não coincidem.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('account-confirm-password')),
      'nova-senha',
    );
    await tester.ensureVisible(find.byKey(const Key('account-save-password')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-save-password')));
    await tester.pumpAndSettle();
    expect(find.text('Senha atual incorreta.'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('account-current-password')),
      -150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const Key('account-current-password')),
      'senha-atual',
    );
    await tester.ensureVisible(find.byKey(const Key('account-save-password')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-save-password')));
    await tester.pumpAndSettle();
    expect(account.passwordChanges, 1);
  });
  testWidgets('perfil com bio e editor em 320dp fonte 2x', (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final users = FakeUserRepository()
      ..profiles['me'] = const UserProfile(
        uid: 'me',
        displayName: 'Bianca Ferreira',
        username: 'bianca.cafes',
        bio: 'Cafés, amigos e experiências pela cidade.',
      );
    final media = FakeProfileMedia();
    final app = await pumpApp(
      tester,
      users: users,
      theme: AppTheme.light(),
      textScale: 2,
      profileEditor: FakeProfileEditor(users, media),
      profileMedia: media,
    );
    app.router.go('/perfil');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    app.router.go(Routes.editProfile);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    app.router.go(Routes.accountSecurity);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
