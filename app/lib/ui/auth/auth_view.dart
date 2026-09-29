import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/user_profile.dart';
import '../../routing/routes.dart';
import 'auth_view_model.dart';

/// Tela de entrada/cadastro. [isSignUp] escolhe o modo.
class AuthView extends StatefulWidget {
  const AuthView({super.key, required this.viewModel, required this.isSignUp});

  final AuthViewModel viewModel;
  final bool isSignUp;

  @override
  State<AuthView> createState() => _AuthViewState();
}

class _AuthViewState extends State<AuthView> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final vm = widget.viewModel;
    if (widget.isSignUp) {
      await vm.signUp(
        displayName: _name.text,
        email: _email.text,
        password: _password.text,
      );
    } else {
      await vm.signIn(email: _email.text, password: _password.text);
    }
    // Sucesso: o redirect do go_router leva ao feed.
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSignUp = widget.isSignUp;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: ListenableBuilder(
                listenable: widget.viewModel,
                builder: (context, _) {
                  final vm = widget.viewModel;
                  return AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('NaÁrea',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.displaySmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.primary,
                            )),
                        const SizedBox(height: 8),
                        Text(
                          isSignUp
                              ? 'Crie sua conta — suas avaliações sempre levam seu nome.'
                              : 'Descubra onde seus amigos foram.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 32),
                        if (isSignUp) ...[
                          TextField(
                            key: const Key('auth-name'),
                            controller: _name,
                            textCapitalization: TextCapitalization.words,
                            maxLength: UserProfile.maxNameLength,
                            autofillHints: const [AutofillHints.name],
                            decoration: const InputDecoration(
                              labelText: 'Nome',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => vm.clearError(),
                          ),
                          const SizedBox(height: 12),
                        ],
                        TextField(
                          key: const Key('auth-email'),
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(
                            labelText: 'E-mail',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => vm.clearError(),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          key: const Key('auth-password'),
                          controller: _password,
                          obscureText: true,
                          autofillHints: [
                            isSignUp ? AutofillHints.newPassword : AutofillHints.password,
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Senha',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => vm.clearError(),
                          onSubmitted: (_) => _submit(),
                        ),
                        if (vm.errorMessage != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            vm.errorMessage!,
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ],
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: vm.isLoading ? null : _submit,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: vm.isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Text(isSignUp ? 'Criar conta' : 'Entrar'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: vm.isLoading
                              ? null
                              : () => context.go(isSignUp ? Routes.login : Routes.signUp),
                          child: Text(isSignUp
                              ? 'Já tenho conta — entrar'
                              : 'Não tem conta? Cadastre-se'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
