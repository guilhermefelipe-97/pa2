import 'package:flutter/material.dart';

import '../../domain/models/place.dart';
import '../../domain/models/review.dart';
import '../../domain/relative_time.dart';
import '../feed/widgets/place_photo.dart';
import '../feed/widgets/review_photo.dart';

/// Faixa horizontal com as fotos dos amigos no local (mais recente primeiro).
/// Tocar abre a foto em tela cheia, com crédito e tempo relativo.
class ReviewPhotoStrip extends StatelessWidget {
  const ReviewPhotoStrip({
    super.key,
    required this.place,
    required this.reviews,
    required this.now,
    this.currentUserId,
  });

  final Place place;

  /// Só avaliações com `hasPhoto`.
  final List<Review> reviews;
  final DateTime now;

  /// Usuário logado: a foto dele leva o crédito "Sua foto".
  final String? currentUserId;

  static const double tileSize = 112;

  bool _isOwn(Review r) => currentUserId != null && r.authorId == currentUserId;

  void _open(BuildContext context, int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ReviewPhotoViewer(
          place: place,
          reviews: reviews,
          initialIndex: index,
          now: now,
          currentUserId: currentUserId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (reviews.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          reviews.length == 1 ? 'Foto dos amigos' : 'Fotos dos amigos',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: tileSize,
          child: ListView.separated(
            key: const Key('review-photo-strip'),
            scrollDirection: Axis.horizontal,
            itemCount: reviews.length,
            separatorBuilder: (context, i) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final r = reviews[i];
              final own = _isOwn(r);
              return Semantics(
                button: true,
                label:
                    '${photoSemanticLabel(r.authorName, place.name, isOwn: own)}. '
                    'Abrir em tela cheia',
                excludeSemantics: true,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox.square(
                    dimension: tileSize,
                    child: Material(
                      child: InkWell(
                        key: Key('review-photo-tile-${r.id}'),
                        onTap: () => _open(context, i),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            PlacePhotoFallback(
                              category: place.category,
                              iconSize: 28,
                            ),
                            ReviewPhoto(
                              review: r,
                              placeName: place.name,
                              isOwn: own,
                              compactCredit: true,
                              creditPadding: const EdgeInsets.all(5),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Fotos em tela cheia (deslizar troca de foto; pinça dá zoom), com crédito e
/// tempo relativo de cada uma. Com zoom, o deslizar move a foto em vez de
/// trocar de página; trocar de página zera o zoom.
class ReviewPhotoViewer extends StatefulWidget {
  const ReviewPhotoViewer({
    super.key,
    required this.place,
    required this.reviews,
    required this.initialIndex,
    required this.now,
    this.currentUserId,
  });

  final Place place;
  final List<Review> reviews;
  final int initialIndex;
  final DateTime now;
  final String? currentUserId;

  @override
  State<ReviewPhotoViewer> createState() => _ReviewPhotoViewerState();
}

class _ReviewPhotoViewerState extends State<ReviewPhotoViewer> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;
  final Map<int, TransformationController> _zoom = {};
  bool _zoomed = false;

  TransformationController _zoomFor(int page) => _zoom.putIfAbsent(page, () {
    final c = TransformationController();
    c.addListener(() {
      if (page != _index) return;
      final zoomed = c.value.getMaxScaleOnAxis() > 1.01;
      if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
    });
    return c;
  });

  void _onPageChanged(int page) {
    for (final c in _zoom.values) {
      c.value = Matrix4.identity();
    }
    setState(() {
      _index = page;
      _zoomed = false;
    });
  }

  bool _isOwn(Review r) =>
      widget.currentUserId != null && r.authorId == widget.currentUserId;

  @override
  void dispose() {
    _controller.dispose();
    for (final c in _zoom.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.reviews[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.place.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          key: const Key('review-photo-viewer-close'),
          icon: const Icon(Icons.close),
          tooltip: 'Fechar',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              key: const Key('review-photo-viewer-pages'),
              controller: _controller,
              physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
              itemCount: widget.reviews.length,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, i) => InteractiveViewer(
                key: Key('review-photo-viewer-zoom-$i'),
                transformationController: _zoomFor(i),
                maxScale: 4,
                child: SizedBox.expand(
                  child: ReviewPhoto(
                    review: widget.reviews[i],
                    placeName: widget.place.name,
                    isOwn: _isOwn(widget.reviews[i]),
                    fit: BoxFit.contain,
                    showCredit: false,
                    decodeWidth: false,
                    loadingPlaceholder: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                    // Foto falhou: fallback da categoria, sem erro.
                    errorPlaceholder: PlacePhotoFallback(
                      category: widget.place.category,
                      iconSize: 72,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${photoCreditText(current.authorName, isOwn: _isOwn(current))} · '
                      '${relativeTime(current.createdAt, widget.now)}',
                      key: const Key('review-photo-viewer-credit'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (widget.reviews.length > 1)
                    Text(
                      '${_index + 1}/${widget.reviews.length}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
