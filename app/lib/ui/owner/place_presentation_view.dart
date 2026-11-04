import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/owner_repository.dart';
import '../../data/repositories/owner_workspace_repository.dart';
import '../../data/repositories/place_repository.dart';
import '../../domain/models/place.dart';
import '../place/place_gallery.dart';

class PlacePresentationView extends StatelessWidget {
  const PlacePresentationView({super.key, required this.placeId});
  final String placeId;
  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthRepository>().currentUserId;
    return _Editor(key: ValueKey('$uid-$placeId'), uid: uid, placeId: placeId);
  }
}

class _Editor extends StatefulWidget {
  const _Editor({super.key, required this.uid, required this.placeId});
  final String? uid;
  final String placeId;
  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  final description = TextEditingController(), hours = TextEditingController();
  final form = GlobalKey<FormState>();
  Place? place;
  bool loading = true, busy = false, allowed = false;
  String? error, notice;
  bool get current =>
      mounted && context.read<AuthRepository>().currentUserId == widget.uid;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    description.dispose();
    hours.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final repo = context.read<OwnerWorkspaceRepository?>();
    final places = context.read<PlaceRepository>();
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final owner = await context
          .read<OwnerRepository>()
          .ownerOf(widget.placeId)
          .timeout(ownerLookupTimeout);
      if (!current) return;
      if (widget.uid == null || owner != widget.uid) {
        setState(() {
          allowed = false;
          error = 'A edição está disponível apenas para o titular atual.';
        });
        return;
      }
      if (repo == null) throw StateError('Edição indisponível');
      final data = await repo.presentation(widget.placeId);
      final found = await places.getPlaces([widget.placeId]);
      if (!current) return;
      if (found[widget.placeId] == null) throw StateError('Local indisponível');
      setState(() {
        place = found[widget.placeId];
        allowed = true;
        description.text = data.description;
        hours.text = data.hours;
      });
    } on Object {
      if (current) {
        setState(() => error = 'Não foi possível carregar. Tente novamente.');
      }
    } finally {
      if (current) setState(() => loading = false);
    }
  }

  Future<void> save() async {
    if (!current || busy || !allowed || !form.currentState!.validate()) return;
    final repo = context.read<OwnerWorkspaceRepository>();
    final owners = context.read<OwnerRepository>();
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      final owner = await owners
          .ownerOf(widget.placeId)
          .timeout(ownerLookupTimeout);
      if (!current) return;
      if (owner != widget.uid) {
        setState(() {
          allowed = false;
          error = 'A titularidade mudou. Você não pode mais editar este local.';
        });
        return;
      }
      await repo.save(
        widget.placeId,
        widget.uid!,
        PlacePresentation(
          description: description.text.trim(),
          hours: hours.text.trim(),
        ),
      );
      if (current) {
        setState(
          () =>
              notice = 'Alterações salvas. A ficha do local já pode exibi-las.',
        );
      }
    } on Object {
      if (current) {
        setState(
          () => error =
              'Não foi possível salvar. Seus textos foram mantidos; tente novamente.',
        );
      }
    } finally {
      if (current) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Editar estabelecimento')),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : !allowed
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(error ?? 'Edição indisponível.'),
                  TextButton(
                    onPressed: load,
                    child: const Text('Tentar novamente'),
                  ),
                ],
              ),
            ),
          )
        : Form(
            key: form,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  place!.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                Text(
                  'Fotos do estabelecimento',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 220,
                    child: PlaceGallery(
                      place: place!,
                      reviews: const [],
                      currentUserId: widget.uid,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Adicione várias fotos pelo ícone da câmera. As fotos são publicadas ao confirmar o envio.',
                ),
                const SizedBox(height: 20),
                TextFormField(
                  key: const Key('place-description'),
                  controller: description,
                  enabled: !busy,
                  decoration: const InputDecoration(
                    labelText: 'Apresentação',
                    hintText: 'Conte um pouco sobre o local',
                  ),
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 1000,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('place-public-hours'),
                  controller: hours,
                  enabled: !busy,
                  decoration: const InputDecoration(
                    labelText: 'Horários de funcionamento',
                    hintText: 'Ex.: terça a domingo, das 12h às 22h',
                  ),
                  minLines: 2,
                  maxLines: 5,
                  maxLength: 500,
                ),
                const Text(
                  'Inclua os dias, os horários e os intervalos de funcionamento.',
                ),
                const SizedBox(height: 16),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (notice != null) Text(notice!, semanticsLabel: notice),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const Key('save-place-presentation'),
                  onPressed: busy ? null : save,
                  icon: Icon(busy ? Icons.hourglass_top : Icons.check),
                  label: FittedBox(
                    child: Text(
                      busy ? 'Salvando…' : 'Salvar alterações',
                      maxLines: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
  );
}

class PlacePresentationSection extends StatefulWidget {
  const PlacePresentationSection({super.key, required this.placeId});
  final String placeId;
  @override
  State<PlacePresentationSection> createState() => _PresentationState();
}

class _PresentationState extends State<PlacePresentationSection> {
  Future<PlacePresentation>? read;
  String? uid;
  @override
  Widget build(BuildContext context) {
    final authUid = context.watch<AuthRepository?>()?.currentUserId;
    final repo = context.read<OwnerWorkspaceRepository?>();
    if (repo == null || authUid == null) return const SizedBox.shrink();
    if (read == null || uid != authUid) {
      uid = authUid;
      read = repo.presentation(widget.placeId);
    }
    return FutureBuilder<PlacePresentation>(
      future: read,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return TextButton(
            onPressed: () => setState(() => read = null),
            child: const Text('Carregar apresentação e horários do titular'),
          );
        }
        final data = snapshot.data;
        if (data == null || (data.description.isEmpty && data.hours.isEmpty)) {
          return const SizedBox.shrink();
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (data.description.isNotEmpty) ...[
                  Text(
                    'Sobre o local',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(data.description),
                  const SizedBox(height: 12),
                ],
                if (data.hours.isNotEmpty) ...[
                  Text(
                    'Horários informados pelo titular',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(data.hours),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
