import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/account_repository.dart';

Future<void> showChangePasswordDialog(BuildContext context) async {
  final auth = context.read<AuthRepository>();
  final uid = auth.currentUserId;
  if (uid == null) return;
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ChangePasswordDialog(uid: uid),
  );
  if (context.mounted && result == true && auth.currentUserId == uid) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Senha atualizada.')));
  }
}

class ChangePasswordDialog extends StatefulWidget {
  const ChangePasswordDialog({super.key, required this.uid});
  final String uid;
  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordState();
}

class _ChangePasswordState extends State<ChangePasswordDialog> {
  final form = GlobalKey<FormState>();
  final old = TextEditingController(),
      next = TextEditingController(),
      confirm = TextEditingController();
  final visible = [false, false, false];
  bool busy = false;
  String? error;
  @override
  void dispose() {
    old.dispose();
    next.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    final auth = context.read<AuthRepository>();
    final repo = context.read<AccountRepository?>();
    if (repo == null || auth.currentUserId != widget.uid) {
      setState(() => error = 'Entre novamente para alterar a senha.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await repo.changePassword(
        currentPassword: old.text,
        newPassword: next.text,
      );
      if (!mounted || auth.currentUserId != widget.uid) return;
      old.clear();
      next.clear();
      confirm.clear();
      Navigator.of(context).pop(true);
    } on AuthException catch (e) {
      if (mounted && auth.currentUserId == widget.uid) {
        setState(() => error = e.message);
      }
    } on Object {
      if (mounted && auth.currentUserId == widget.uid) {
        setState(
          () => error =
              'Não foi possível alterar a senha. Verifique sua conexão e tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget field(
    int i,
    String label,
    TextEditingController controller,
    String key,
  ) => TextFormField(
    key: Key(key),
    controller: controller,
    enabled: !busy,
    obscureText: !visible[i],
    autocorrect: false,
    enableSuggestions: false,
    autofillHints: [
      i == 0 ? AutofillHints.password : AutofillHints.newPassword,
    ],
    decoration: InputDecoration(
      labelText: label,
      errorMaxLines: 3,
      suffixIcon: IconButton(
        tooltip: visible[i] ? 'Ocultar $label' : 'Mostrar $label',
        onPressed: busy ? null : () => setState(() => visible[i] = !visible[i]),
        icon: Icon(
          visible[i]
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          size: 20,
        ),
      ),
    ),
    validator: (value) => value == null || value.isEmpty
        ? 'Informe a senha.'
        : i == 1 && value.length < 6
        ? 'Use pelo menos 6 caracteres.'
        : i == 2 && value != next.text
        ? 'As senhas não coincidem.'
        : null,
  );
  @override
  Widget build(BuildContext context) {
    final same = context.watch<AuthRepository>().currentUserId == widget.uid;
    final theme = Theme.of(context);
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Alterar senha'),
        scrollable: true,
        content: !same
            ? const Text('Conta alterada. Entre novamente.')
            : SizedBox(
                width: 360,
                child: Form(
                  key: form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Confirme sua senha atual para escolher uma nova senha.',
                      ),
                      const SizedBox(height: 20),
                      field(0, 'Senha atual', old, 'password-modal-current'),
                      const SizedBox(height: 14),
                      field(1, 'Nova senha', next, 'password-modal-new'),
                      const SizedBox(height: 14),
                      field(
                        2,
                        'Confirmar nova senha',
                        confirm,
                        'password-modal-confirm',
                      ),
                      const SizedBox(height: 8),
                      const Text('Use pelo menos 6 caracteres.'),
                      if (error != null) ...[
                        const SizedBox(height: 12),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            error!,
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                      ],
                      if (busy) ...[
                        const SizedBox(height: 12),
                        const LinearProgressIndicator(),
                      ],
                    ],
                  ),
                ),
              ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.of(context).pop(false),
            child: Text(same ? 'Cancelar' : 'Fechar'),
          ),
          if (same)
            FilledButton(
              key: const Key('password-modal-save'),
              onPressed: busy ? null : save,
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.secondary,
              ),
              child: FittedBox(
                child: Text(busy ? 'Salvando…' : 'Salvar senha', maxLines: 1),
              ),
            ),
        ],
      ),
    );
  }
}
