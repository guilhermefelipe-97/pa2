import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/account_repository.dart';
import '../../data/repositories/profile_editor_repository.dart';
import '../../data/repositories/profile_media_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/services/photo_picker.dart';
import '../../domain/models/user_profile.dart';
import '../../domain/photo_compression.dart';
import '../../routing/routes.dart';
import '../core/photo_crop_view.dart';
import 'profile_media_image.dart';
import 'change_password_dialog.dart';

class ProfileEditView extends StatelessWidget {
  const ProfileEditView({super.key});
  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthRepository>().currentUserId;
    return uid == null
        ? const Scaffold(
            body: Center(child: Text('Entre para editar seu perfil.')),
          )
        : _Editor(key: ValueKey(uid), uid: uid);
  }
}

class _Editor extends StatefulWidget {
  const _Editor({super.key, required this.uid});
  final String uid;
  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      username = TextEditingController(),
      bio = TextEditingController(),
      city = TextEditingController(),
      instagram = TextEditingController();
  Uint8List? avatar, cover;
  bool removeAvatar = false, removeCover = false, loading = true, busy = false;
  String? error;
  bool get current =>
      mounted && context.read<AuthRepository>().currentUserId == widget.uid;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    name.dispose();
    username.dispose();
    usernameFocus.dispose();
    bio.dispose();
    city.dispose();
    instagram.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final p = await context
          .read<UserRepository>()
          .getProfile(widget.uid)
          .timeout(const Duration(seconds: 15));
      if (!current) return;
      if (p == null) throw StateError('Perfil não encontrado');
      name.text = p.displayName;
      username.text = p.username;
      bio.text = p.bio;
      city.text = p.city;
      instagram.text = p.instagram;
    } on Object {
      if (current) {
        setState(
          () => error = 'Não foi possível carregar o perfil. Tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> pick(String kind) async {
    if (busy || !current) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final bytes = await context.read<PhotoPicker>().pick(PhotoSource.gallery);
      if (bytes == null || !mounted || !current) return;
      final isAvatar = kind == 'avatar';
      final crop = await showPhotoCropView(
        context,
        bytes: bytes,
        aspectRatio: isAvatar ? 1 : coverAspectRatio,
        circle: isAvatar,
        title: isAvatar ? 'Ajustar foto' : 'Ajustar capa',
      );
      if (crop == null || !current) return;
      final jpeg = await compute(compressCroppedPhoto, (
        bytes: bytes,
        crop: crop,
      ));
      if (!current) return;
      setState(() {
        if (kind == 'avatar') {
          avatar = jpeg;
          removeAvatar = false;
        } else {
          cover = jpeg;
          removeCover = false;
        }
      });
    } on Object {
      if (current) {
        setState(
          () => error =
              'Não foi possível usar a foto. Confira a permissão e escolha outra imagem.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Mesma proporção da capa no perfil (largura / 2,4).
  static const coverAspectRatio = 2.4;

  static const usernameNeededForPhotos =
      'Para salvar a foto do perfil e a capa, é necessário ter um @usuário. '
      'Escolha um no campo "Nome de usuário".';

  final usernameFocus = FocusNode();

  bool get changesPhotos =>
      avatar != null || cover != null || removeAvatar || removeCover;

  Future<void> save() async {
    if (busy || !current) return;
    if (!form.currentState!.validate()) {
      final missingUsername = username.text
          .trim()
          .replaceFirst(RegExp(r'^@'), '')
          .isEmpty;
      if (missingUsername) {
        usernameFocus.requestFocus();
        if (changesPhotos) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(
              const SnackBar(
                key: Key('profile-username-needed'),
                content: Text(usernameNeededForPhotos),
                duration: Duration(seconds: 6),
              ),
            );
        }
      }
      return;
    }
    final repo = context.read<ProfileEditorRepository?>();
    if (repo == null) {
      setState(
        () => error = 'Edição indisponível. Tente novamente mais tarde.',
      );
      return;
    }
    final media = context.read<ProfileMediaRepository?>();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await repo.save(
        UserProfile(
          uid: widget.uid,
          displayName: name.text.trim(),
          username: username.text
              .trim()
              .replaceFirst(RegExp(r'^@'), '')
              .toLowerCase(),
          bio: bio.text.trim(),
          city: city.text.trim(),
          instagram: instagram.text.trim().replaceFirst(RegExp(r'^@'), ''),
        ),
        avatar: avatar,
        cover: cover,
        removeAvatar: removeAvatar,
        removeCover: removeCover,
      );
      if (!current || !mounted) return;
      media?.invalidate(widget.uid);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Perfil atualizado.')));
      context.pop(true);
    } on ProfileEditException catch (e) {
      if (current) setState(() => error = e.message);
    } on Object {
      if (current) {
        setState(
          () => error =
              'Não foi possível salvar. Seus dados continuam nesta tela para tentar novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget image(String kind) {
    final selected = kind == 'avatar' ? avatar : cover;
    final removed = kind == 'avatar' ? removeAvatar : removeCover;
    final fallback = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Center(
        child: Icon(
          kind == 'avatar' ? Icons.person_outline : Icons.panorama_outlined,
          size: kind == 'avatar' ? 40 : 56,
        ),
      ),
    );
    return selected != null
        ? Image.memory(selected, fit: BoxFit.cover)
        : removed
        ? fallback
        : ProfileMediaImage(uid: widget.uid, kind: kind, placeholder: fallback);
  }

  void cancel() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/perfil');
    }
  }

  Widget section(String title, {String? badge}) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 16),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        if (badge != null)
          Text(
            badge.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: 10,
              letterSpacing: 1,
              color: Theme.of(context).colorScheme.secondary,
            ),
          ),
      ],
    ),
  );
  InputDecoration decoration(
    String label, {
    IconData? icon,
    String? prefix,
  }) => InputDecoration(
    hintText: label,
    // "@" sempre visível (prefixText só aparecia com o campo em foco).
    prefixIcon: prefix != null
        ? Padding(
            padding: const EdgeInsetsDirectional.only(start: 14, end: 2),
            child: Text(
              prefix,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          )
        : icon == null
        ? null
        : Icon(icon, size: 18),
    prefixIconConstraints: prefix != null
        ? const BoxConstraints(minWidth: 0, minHeight: 0)
        : null,
    filled: true,
    fillColor: Colors.white,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Theme.of(context).colorScheme.secondary),
    ),
    errorMaxLines: 3,
  );
  Widget label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: Theme.of(context).colorScheme.secondary,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final account = context.read<AccountRepository?>();
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          // Ícone em vez do texto "Cancelar": com fonte grande o texto
          // encolhia até ficar ilegível e encostava no título.
          leading: IconButton(
            key: const Key('profile-edit-cancel'),
            tooltip: 'Cancelar',
            icon: const Icon(Icons.close),
            onPressed: busy ? null : cancel,
          ),
          titleSpacing: 0,
          title: const Text(
            'Editar perfil',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          titleTextStyle: theme.textTheme.titleMedium,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                key: const Key('profile-edit-save'),
                onPressed:
                    busy || loading || (error != null && name.text.isEmpty)
                    ? null
                    : save,
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.secondary,
                  minimumSize: const Size(64, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                child: Text(busy ? 'Salvando…' : 'Salvar', maxLines: 1),
              ),
            ),
          ],
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : error != null && name.text.isEmpty
            ? Center(
                child: TextButton(onPressed: load, child: Text(error!)),
              )
            : Form(
                key: form,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  children: [
                    SizedBox(
                      height: 208,
                      child: Stack(
                        children: [
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            height: 160,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: image('cover'),
                            ),
                          ),
                          Positioned(
                            right: 10,
                            top: 10,
                            child: FilledButton.tonalIcon(
                              key: const Key('profile-pick-cover'),
                              onPressed: busy ? null : () => pick('cover'),
                              icon: const Icon(
                                Icons.panorama_outlined,
                                size: 16,
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white.withValues(
                                  alpha: .94,
                                ),
                                foregroundColor: theme.colorScheme.secondary,
                                minimumSize: const Size(48, 40),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                              ),
                              label: const FittedBox(
                                child: Text('Alterar capa', maxLines: 1),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 14,
                            top: 116,
                            child: Container(
                              width: 88,
                              height: 88,
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                              ),
                              child: ClipOval(child: image('avatar')),
                            ),
                          ),
                          Positioned(
                            left: 72,
                            top: 158,
                            child: IconButton.filled(
                              key: const Key('profile-pick-avatar'),
                              tooltip: 'Alterar foto',
                              onPressed: busy ? null : () => pick('avatar'),
                              style: IconButton.styleFrom(
                                shape: const CircleBorder(),
                                backgroundColor: theme.colorScheme.secondary,
                              ),
                              icon: const Icon(
                                Icons.photo_camera_outlined,
                                size: 18,
                              ),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            top: 164,
                            child: PopupMenuButton<String>(
                              tooltip: 'Opções de fotos',
                              enabled: !busy,
                              onSelected: (value) => setState(() {
                                if (value == 'avatar') {
                                  avatar = null;
                                  removeAvatar = true;
                                } else {
                                  cover = null;
                                  removeCover = true;
                                }
                              }),
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'avatar',
                                  child: Text('Remover foto'),
                                ),
                                PopupMenuItem(
                                  value: 'cover',
                                  child: Text('Remover capa'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    section('Informações básicas', badge: 'Público'),
                    label('Nome completo'),
                    TextFormField(
                      key: const Key('profile-name'),
                      controller: name,
                      enabled: !busy,
                      maxLength: 60,
                      decoration: decoration(
                        'Seu nome',
                      ).copyWith(counterText: ''),
                      validator: (s) => UserProfile.isValidName(s ?? '')
                          ? null
                          : 'Informe um nome de até 60 caracteres.',
                    ),
                    const SizedBox(height: 16),
                    label('Nome de usuário'),
                    TextFormField(
                      key: const Key('profile-username'),
                      controller: username,
                      focusNode: usernameFocus,
                      enabled: !busy,
                      maxLength: 24,
                      autocorrect: false,
                      textCapitalization: TextCapitalization.none,
                      decoration: decoration('usuario', prefix: '@').copyWith(
                        counterText: '',
                        helperText:
                            '3–24 caracteres: letras, números, ponto ou sublinhado.',
                        helperMaxLines: 3,
                      ),
                      validator: (s) {
                        final value = (s ?? '')
                            .trim()
                            .replaceFirst(RegExp(r'^@'), '')
                            .toLowerCase();
                        if (value.isEmpty) {
                          return 'Escolha um @usuário para salvar o perfil.';
                        }
                        return UserProfile.validUsername(value)
                            ? null
                            : 'Escolha um @usuário válido.';
                      },
                    ),
                    const SizedBox(height: 16),
                    label('Biografia'),
                    TextFormField(
                      key: const Key('profile-bio'),
                      controller: bio,
                      enabled: !busy,
                      maxLength: UserProfile.maxBioLength,
                      minLines: 3,
                      maxLines: 5,
                      decoration: decoration(
                        'Conte um pouco sobre você e os lugares de que gosta.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    label('Bairro principal'),
                    TextFormField(
                      key: const Key('profile-city'),
                      controller: city,
                      enabled: !busy,
                      maxLength: 80,
                      decoration: decoration(
                        'Bairro e cidade (opcional)',
                        icon: Icons.place_outlined,
                      ).copyWith(counterText: ''),
                    ),
                    section('Presença e links', badge: 'Opcional'),
                    label('Instagram'),
                    TextFormField(
                      key: const Key('profile-instagram'),
                      controller: instagram,
                      enabled: !busy,
                      maxLength: 30,
                      autocorrect: false,
                      decoration: decoration(
                        'seu.usuario',
                        prefix: '@',
                      ).copyWith(counterText: ''),
                      validator: (s) =>
                          UserProfile.validInstagram(
                            (s ?? '').trim().replaceFirst(RegExp(r'^@'), ''),
                          )
                          ? null
                          : 'Informe apenas o usuário do Instagram, sem o link.',
                    ),
                    section('Acesso e segurança'),
                    label('E-mail'),
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListTile(
                        leading: const Icon(Icons.mail_outline, size: 18),
                        title: Text(
                          account?.email ?? 'Gerenciar e-mail',
                          style: theme.textTheme.bodyMedium,
                        ),
                        trailing: const Icon(Icons.chevron_right, size: 18),
                        onTap: busy
                            ? null
                            : () async {
                                await context.push(Routes.accountSecurity);
                                if (mounted) setState(() {});
                              },
                      ),
                    ),
                    label('Senha'),
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_outline, size: 18),
                          const SizedBox(width: 10),
                          const Expanded(child: Text('••••••••', maxLines: 1)),
                          TextButton(
                            key: const Key('profile-change-password'),
                            onPressed: busy || account == null
                                ? null
                                : () => showChangePasswordDialog(context),
                            child: const FittedBox(
                              child: Text('Alterar senha', maxLines: 1),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (busy) const LinearProgressIndicator(),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            error!,
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}
