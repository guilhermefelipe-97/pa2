import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/repositories/account_repository.dart';
import '../../data/repositories/auth_repository.dart';

class AccountSecurityView extends StatefulWidget {
  const AccountSecurityView({super.key});
  @override
  State<AccountSecurityView> createState() => _AccountSecurityViewState();
}

class _AccountSecurityViewState extends State<AccountSecurityView>
    with WidgetsBindingObserver {
  final email = TextEditingController(),
      emailPassword = TextEditingController(),
      currentPassword = TextEditingController(),
      newPassword = TextEditingController(),
      confirmPassword = TextEditingController();
  final emailForm = GlobalKey<FormState>(),
      passwordForm = GlobalKey<FormState>();
  bool busy = false;
  String? notice, uid;
  @override
  void initState() {
    super.initState();
    uid = context.read<AuthRepository>().currentUserId;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => refreshEmail());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refreshEmail();
  }

  Future<void> refreshEmail() async {
    if (!mounted || busy) return;
    final repo = context.read<AccountRepository?>();
    try {
      await repo?.refresh();
      if (mounted) setState(() {});
    } on Object {
      /* Mantém o e-mail já carregado até uma nova consulta. */
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    email.dispose();
    emailPassword.dispose();
    currentPassword.dispose();
    newPassword.dispose();
    confirmPassword.dispose();
    super.dispose();
  }

  Future<void> submit(bool changingEmail) async {
    if (busy ||
        !(changingEmail ? emailForm : passwordForm).currentState!.validate()) {
      return;
    }
    final repo = context.read<AccountRepository?>();
    final auth = context.read<AuthRepository>();
    if (repo == null || auth.currentUserId != uid) {
      setState(() => notice = 'Entre novamente para gerenciar sua conta.');
      return;
    }
    setState(() {
      busy = true;
      notice = null;
    });
    try {
      if (changingEmail) {
        await repo.requestEmailChange(
          email: email.text.trim(),
          currentPassword: emailPassword.text,
        );
      } else {
        await repo.changePassword(
          currentPassword: currentPassword.text,
          newPassword: newPassword.text,
        );
      }
      if (!mounted || auth.currentUserId != uid) return;
      emailPassword.clear();
      currentPassword.clear();
      newPassword.clear();
      confirmPassword.clear();
      setState(
        () => notice = changingEmail
            ? 'Enviamos uma confirmação para o novo e-mail. O endereço atual só muda depois que você confirmar o link.'
            : 'Senha atualizada.',
      );
    } on AuthException catch (e) {
      if (mounted && auth.currentUserId == uid) {
        setState(() => notice = e.message);
      }
    } on Object {
      if (mounted && auth.currentUserId == uid) {
        setState(
          () => notice =
              'Não foi possível concluir. Verifique a conexão e tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget password(
    TextEditingController controller,
    String label,
    String key, {
    bool newValue = false,
  }) => TextFormField(
    key: Key(key),
    controller: controller,
    enabled: !busy,
    obscureText: true,
    enableSuggestions: false,
    autocorrect: false,
    decoration: InputDecoration(labelText: label),
    validator: (s) => s == null || s.isEmpty
        ? 'Informe a senha.'
        : newValue && s.length < 6
        ? 'Use pelo menos 6 caracteres.'
        : null,
  );
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthRepository>();
    final same = auth.currentUserId == uid;
    final repo = context.read<AccountRepository?>();
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('E-mail e senha')),
        bottomNavigationBar: same && (notice != null || busy)
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (busy) const LinearProgressIndicator(),
                      if (notice != null)
                        Semantics(liveRegion: true, child: Text(notice!)),
                    ],
                  ),
                ),
              )
            : null,
        body: !same
            ? const Center(child: Text('Conta alterada. Entre novamente.'))
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    'E-mail atual',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(repo?.email ?? 'Indisponível'),
                  const SizedBox(height: 20),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Form(
                        key: emailForm,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Alterar e-mail',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              key: const Key('account-new-email'),
                              controller: email,
                              enabled: !busy,
                              keyboardType: TextInputType.emailAddress,
                              autocorrect: false,
                              decoration: const InputDecoration(
                                labelText: 'Novo e-mail',
                              ),
                              validator: (s) =>
                                  RegExp(
                                    r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                  ).hasMatch((s ?? '').trim())
                                  ? null
                                  : 'Informe um e-mail válido.',
                            ),
                            const SizedBox(height: 12),
                            password(
                              emailPassword,
                              'Senha atual',
                              'account-email-password',
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              key: const Key('account-save-email'),
                              onPressed: busy ? null : () => submit(true),
                              child: const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'Confirmar novo e-mail',
                                  maxLines: 1,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Form(
                        key: passwordForm,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Alterar senha',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            password(
                              currentPassword,
                              'Senha atual',
                              'account-current-password',
                            ),
                            const SizedBox(height: 12),
                            password(
                              newPassword,
                              'Nova senha',
                              'account-new-password',
                              newValue: true,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              key: const Key('account-confirm-password'),
                              controller: confirmPassword,
                              enabled: !busy,
                              obscureText: true,
                              enableSuggestions: false,
                              autocorrect: false,
                              decoration: const InputDecoration(
                                labelText: 'Confirmar nova senha',
                              ),
                              validator: (s) => s != newPassword.text
                                  ? 'As senhas não coincidem.'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              key: const Key('account-save-password'),
                              onPressed: busy ? null : () => submit(false),
                              child: const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('Salvar nova senha', maxLines: 1),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (busy) const LinearProgressIndicator(),
                ],
              ),
      ),
    );
  }
}
