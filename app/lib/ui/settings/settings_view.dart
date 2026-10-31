import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../domain/models/user_profile.dart';
import '../../routing/routes.dart';
import '../admin/admin_access.dart';
import '../core/editorial.dart';
import '../feed/widgets/author_avatar.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});
  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthRepository>().currentUserId;
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: uid == null
          ? const SizedBox.shrink()
          : _Settings(key: ValueKey(uid), uid: uid),
    );
  }
}

class _Settings extends StatefulWidget {
  const _Settings({super.key, required this.uid});
  final String uid;
  @override
  State<_Settings> createState() => _SettingsState();
}

class _SettingsState extends State<_Settings> {
  late final Future<UserProfile?> profile;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    profile = context.read<UserRepository>().getProfile(widget.uid);
  }

  Future<void> signOut() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await context.read<AuthRepository>().signOut();
    } on Object {
      if (mounted)
        setState(() => error = 'Não foi possível sair. Tente de novo.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget destination(
    IconData icon,
    String title,
    String subtitle,
    String route,
  ) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.all(16),
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: busy ? null : () => context.push(route),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminAccess?>()?.enabled == true;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        FutureBuilder<UserProfile?>(
          future: profile,
          builder: (context, snapshot) {
            final name = snapshot.data?.displayName.trim();
            return Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: AuthorAvatar(
                  id: widget.uid,
                  name: name ?? '',
                  radius: 24,
                ),
                title: Text(name == null || name.isEmpty ? 'Seu perfil' : name),
                subtitle: const Text('Sua identidade pública'),
                trailing: const Icon(Icons.chevron_right),
                onTap: busy
                    ? null
                    : () => context.push(Routes.person(widget.uid)),
              ),
            );
          },
        ),
        const EditorialHeading(
          eyebrow: 'Preferências',
          title: 'Seu jeito de explorar',
        ),
        destination(
          Icons.restaurant_outlined,
          'Perfil alimentar',
          'Preferências para filtrar os lugares dos amigos.',
          '/perfil-alimentar',
        ),
        destination(
          Icons.visibility_off_outlined,
          'Publicação em Amigos',
          'Modo silencioso: afeta o feed de Amigos. Avaliações e visitas continuam identificadas.',
          '/modo-silencioso',
        ),
        const EditorialHeading(
          eyebrow: 'Área do titular',
          title: 'Seus estabelecimentos',
        ),
        destination(
          Icons.storefront_outlined,
          'Meus estabelecimentos',
          'Solicitações de titularidade e respostas às avaliações.',
          '/meus-estabelecimentos',
        ),
        if (admin) ...[
          const EditorialHeading(
            eyebrow: 'Acesso autorizado',
            title: 'Administração',
          ),
          destination(
            Icons.admin_panel_settings_outlined,
            'Administração',
            'Revisar solicitações de titularidade.',
            Routes.admin,
          ),
        ],
        const SizedBox(height: 24),
        OutlinedButton.icon(
          key: const Key('settings-sign-out'),
          onPressed: busy ? null : signOut,
          icon: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.logout),
          label: Text(busy ? 'Saindo…' : 'Sair'),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(
              liveRegion: true,
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
        const SizedBox(height: 24),
        Text(
          'NaÁrea · 1.3.0+6',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
