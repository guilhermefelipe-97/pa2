import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/place_photo_repository.dart';
import '../../data/repositories/place_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/services/place_photo_picker.dart';
import '../../domain/models/place.dart';
import '../../domain/models/review.dart';
import '../../domain/photo_compression.dart';
import '../feed/widgets/place_photo.dart';

class PlaceGallery extends StatelessWidget {
  const PlaceGallery({
    super.key,
    required this.place,
    required this.reviews,
    this.currentUserId,
    this.coverOnly = false,
  });
  final Place place;
  final List<Review> reviews;
  final String? currentUserId;
  final bool coverOnly;
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthRepository?>();
    final uid = auth == null ? currentUserId : auth.currentUserId;
    return _Gallery(
      key: ValueKey('$uid-${place.id}'),
      uid: uid,
      place: place,
      reviews: reviews,
      coverOnly: coverOnly,
    );
  }
}

class _Gallery extends StatefulWidget {
  const _Gallery({
    super.key,
    required this.uid,
    required this.place,
    required this.reviews,
    required this.coverOnly,
  });
  final String? uid;
  final Place place;
  final List<Review> reviews;
  final bool coverOnly;
  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  final controller = PageController();
  List<PlaceGalleryPhoto> photos = [];
  String? cursor, error;
  int page = 0;
  bool loading = false;
  bool deleting = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> load({bool more = false}) async {
    final repo = context.read<PlacePhotoRepository?>();
    if (repo == null || loading || widget.uid == null) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await repo
          .list(widget.place.id, after: more ? cursor : null)
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() {
        photos = more
            ? {
                for (final p in [...photos, ...result.photos]) p.id: p,
              }.values.toList()
            : result.photos;
        cursor = result.cursor;
        if (!more) page = 0;
      });
      if (!more && controller.hasClients) controller.jumpToPage(0);
    } on Object {
      if (mounted) {
        setState(() => error = 'Fotos indisponíveis. Tentar novamente');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> upload() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _UploadSheet(place: widget.place, uid: widget.uid!),
    );
    if (saved == true && mounted) await load();
  }

  Future<void> removePhoto(PlaceGalleryPhoto photo) async {
    if (deleting || photo.authorId != widget.uid) return;
    final repo = context.read<PlacePhotoRepository>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Remover esta foto?'),
        content: const Text(
          'A foto será removida da galeria do estabelecimento.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (!mounted ||
        confirmed != true ||
        context.read<AuthRepository>().currentUserId != widget.uid) {
      return;
    }
    setState(() => deleting = true);
    try {
      await repo
          .remove(widget.place.id, photo.id)
          .timeout(const Duration(seconds: 15));
      if (mounted) await load();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível remover a foto. Tente novamente.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final place = widget.place;
    final entries = <Widget>[
      for (final photo in photos)
        Image.memory(
          photo.jpeg,
          fit: BoxFit.cover,
          semanticLabel: 'Foto de ${photo.authorName} em ${place.name}',
        ),
      for (final r in widget.reviews)
        PlacePhoto(
          place: place,
          friendPhoto: r,
          friendPhotoIsOwn: r.authorId == widget.uid,
        ),
      if (place.photoUrl?.isNotEmpty == true) PlacePhoto(place: place),
    ];
    final hasMore = cursor != null;
    final available = entries.length;
    final count = available + (hasMore ? 1 : 0);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (entries.isEmpty && !hasMore)
          PlacePhoto(place: place, iconSize: 64)
        else
          PageView.builder(
            key: const Key('place-gallery-pages'),
            controller: controller,
            itemCount: count,
            onPageChanged: (value) => setState(() => page = value),
            itemBuilder: (context, i) => i == available
                ? Center(
                    child: FilledButton.tonalIcon(
                      onPressed: loading ? null : () => load(more: true),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(loading ? 'Carregando…' : 'Ver mais fotos'),
                    ),
                  )
                : entries[i],
          ),
        if (!widget.coverOnly &&
            context.read<PlacePhotoRepository?>() != null &&
            context.read<PlacePhotoPicker?>() != null &&
            widget.uid != null)
          Positioned(
            top: 12,
            right: 12,
            child: Material(
              color: Colors.white.withValues(alpha: .94),
              borderRadius: BorderRadius.circular(24),
              child: IconButton(
                key: const Key('place-add-photos'),
                tooltip: 'Adicionar fotos do estabelecimento',
                onPressed: upload,
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 20),
              ),
            ),
          ),
        if (!widget.coverOnly &&
            page < photos.length &&
            photos[page].authorId == widget.uid)
          Positioned(
            top: 12,
            left: 12,
            child: IconButton.filledTonal(
              tooltip: 'Remover minha foto',
              onPressed: deleting ? null : () => removePhoto(photos[page]),
              icon: const Icon(Icons.delete_outline, size: 20),
            ),
          ),
        if (!widget.coverOnly && available > 0)
          if (page < photos.length)
            Positioned(
              left: 12,
              bottom: 10,
              right: 84,
              child: Text(
                'Foto de ${photos[page].authorName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                ),
              ),
            ),
        if (!widget.coverOnly && available > 0)
          Positioned(
            right: 12,
            bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .65),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${page < available ? page + 1 : available}/$available${hasMore ? '+' : ''}',
                key: const Key('place-gallery-counter'),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
        if (!widget.coverOnly && available > 1)
          Positioned(
            left: 12,
            top: 76,
            bottom: 76,
            child: Center(
              child: IconButton.filledTonal(
                tooltip: 'Foto anterior',
                onPressed: page > 0
                    ? () => controller.previousPage(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                      )
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
            ),
          ),
        if (!widget.coverOnly && (available > 1 || hasMore))
          Positioned(
            right: 12,
            top: 76,
            bottom: 76,
            child: Center(
              child: IconButton.filledTonal(
                tooltip: 'Próxima foto',
                onPressed: page < count - 1
                    ? () => controller.nextPage(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                      )
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ),
          ),
        if (error != null)
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: TextButton(
              style: TextButton.styleFrom(backgroundColor: Colors.white),
              onPressed: () => load(),
              child: Text(error!),
            ),
          ),
      ],
    );
  }
}

class _UploadSheet extends StatefulWidget {
  const _UploadSheet({required this.place, required this.uid});
  final Place place;
  final String uid;
  @override
  State<_UploadSheet> createState() => _UploadSheetState();
}

class _UploadSheetState extends State<_UploadSheet> {
  final photos = <Uint8List>[];
  bool busy = false;
  String? error;
  bool get current =>
      mounted && context.read<AuthRepository>().currentUserId == widget.uid;
  Future<void> pick() async {
    if (busy || !current) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final selected = await context.read<PlacePhotoPicker>().pickMany();
      for (final bytes in selected.take(
        maxPlacePhotosPerUpload - photos.length,
      )) {
        final jpeg = await compute(compressPhoto, bytes);
        if (!current) return;
        setState(() => photos.add(jpeg));
      }
    } on Object {
      if (current) {
        setState(
          () => error =
              'Não foi possível preparar as fotos. Verifique a permissão e escolha imagens válidas.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (busy || photos.isEmpty || !current) return;
    setState(() {
      busy = true;
      error = null;
    });
    final repo = context.read<PlacePhotoRepository>();
    final users = context.read<UserRepository>();
    final places = context.read<PlaceRepository>();
    try {
      final profile = await users
          .getProfile(widget.uid)
          .timeout(const Duration(seconds: 10));
      if (!current) return;
      if (profile == null) throw StateError('Perfil indisponível');
      await ensurePlaceForSave(
        places,
        uid: widget.uid,
        placeId: widget.place.id,
      );
      if (!current) return;
      await repo.add(
        widget.place.id,
        authorId: widget.uid,
        authorName: profile.displayName,
        photos: List.of(photos),
      );
      if (!mounted) return;
      if (current) Navigator.pop(context, true);
    } on Object {
      if (current) {
        setState(
          () => error =
              'Não foi possível enviar. Suas fotos continuam selecionadas; tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sameAccount =
        context.watch<AuthRepository>().currentUserId == widget.uid;
    if (!sameAccount) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Conta alterada. Feche esta tela e entre novamente.'),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Fechar'),
              ),
            ],
          ),
        ),
      );
    }
    return PopScope(
      canPop: !busy,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Fotos do estabelecimento',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Selecione até $maxPlacePhotosPerUpload fotos por envio. Elas serão públicas e identificadas com seu nome.',
              ),
              if (!sameAccount)
                const Text(
                  'Conta alterada. Feche esta tela e entre novamente.',
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < photos.length; i++)
                    SizedBox(
                      width: 96,
                      height: 96,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(photos[i], fit: BoxFit.cover),
                          ),
                          Align(
                            alignment: Alignment.topRight,
                            child: IconButton.filledTonal(
                              tooltip: 'Remover foto ${i + 1}',
                              onPressed: busy || !sameAccount
                                  ? null
                                  : () => setState(() => photos.removeAt(i)),
                              icon: const Icon(Icons.close, size: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('place-photos-pick'),
                onPressed:
                    busy ||
                        !sameAccount ||
                        photos.length >= maxPlacePhotosPerUpload
                    ? null
                    : pick,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Selecionar fotos'),
              ),
              if (busy) const LinearProgressIndicator(),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Semantics(liveRegion: true, child: Text(error!)),
                ),
              const SizedBox(height: 8),
              FilledButton(
                key: const Key('place-photos-save'),
                onPressed: busy || !sameAccount || photos.isEmpty ? null : save,
                child: Text(
                  busy
                      ? 'Aguarde…'
                      : 'Enviar ${photos.length} foto${photos.length == 1 ? '' : 's'}',
                ),
              ),
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
