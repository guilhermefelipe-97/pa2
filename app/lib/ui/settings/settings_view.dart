import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../domain/models/user_profile.dart';
import '../../routing/routes.dart';
import '../../data/services/location_service.dart';
import '../admin/admin_access.dart';
import '../core/editorial.dart';
import '../core/naarea_footer.dart';
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
  late Future<UserProfile?> profile;
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
      if (mounted) {
        setState(() => error = 'Não foi possível sair. Tente de novo.');
      }
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
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        child: Icon(
          icon,
          size: 20,
          color: Theme.of(context).colorScheme.secondary,
        ),
      ),
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
        const EditorialHeading(
          eyebrow: 'Conta e segurança',
          title: 'Sua conta',
        ),
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
                subtitle: const Text('Editar perfil, fotos, bio e conta'),
                trailing: const Icon(Icons.chevron_right),
                onTap: busy
                    ? null
                    : () async {
                        await context.push(Routes.editProfile);
                        if (mounted) {
                          setState(() {
                            profile = context.read<UserRepository>().getProfile(
                              widget.uid,
                            );
                          });
                        }
                      },
              ),
            );
          },
        ),
        const EditorialHeading(
          eyebrow: 'Preferências do app',
          title: 'Seu jeito de explorar',
        ),
        destination(
          Icons.visibility_off_outlined,
          'Publicação em Amigos',
          'Modo silencioso: afeta o feed de Amigos. Avaliações e visitas continuam identificadas.',
          '/modo-silencioso',
        ),
        const EditorialHeading(
          eyebrow: 'Aparelho',
          title: 'Notificações e permissões',
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Abrir configurações do aparelho'),
            subtitle: const Text(
              'Gerencie as permissões do NaÁrea no sistema.',
            ),
            trailing: const Icon(Icons.open_in_new),
            onTap: busy
                ? null
                : () async {
                    final service = context.read<LocationService?>();
                    final opened = await service?.openAppSettings() ?? false;
                    if (!opened && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Abra as configurações do seu aparelho para gerenciar as permissões.',
                          ),
                        ),
                      );
                    }
                  },
          ),
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
        const EditorialHeading(
          eyebrow: 'Ajuda e informações',
          title: 'Sobre o NaÁrea',
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Versão e licenças'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'NaÁrea',
              applicationVersion: '1.4.0+7',
              applicationLegalese: '© 2026. Todos os direitos reservados.',
              children: const [
                Text(
                  'Descubra lugares pelas experiências de quem você segue. As avaliações e visitas são identificadas.',
                ),
              ],
            ),
          ),
        ),
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
          'Versão 1.4.0+7',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        const NaAreaFooter(),
      ],
    );
  }
}
