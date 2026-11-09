import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../domain/photo_compression.dart';

/// Abre a tela de ajuste de enquadramento (foto de perfil ou capa). Devolve a
/// parte escolhida da imagem ou `null` se a pessoa cancelar.
Future<PhotoCrop?> showPhotoCropView(
  BuildContext context, {
  required Uint8List bytes,
  required double aspectRatio,
  bool circle = false,
  String title = 'Ajustar foto',
}) => Navigator.of(context, rootNavigator: true).push<PhotoCrop>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => PhotoCropView(
      bytes: bytes,
      aspectRatio: aspectRatio,
      circle: circle,
      title: title,
    ),
  ),
);

/// Arrastar move a imagem e o gesto de pinça (ou o controle de zoom) aproxima.
/// A moldura sempre fica coberta pela imagem, então o recorte nunca tem borda
/// vazia.
class PhotoCropView extends StatefulWidget {
  const PhotoCropView({
    super.key,
    required this.bytes,
    required this.aspectRatio,
    this.circle = false,
    this.title = 'Ajustar foto',
  });

  final Uint8List bytes;
  final double aspectRatio;
  final bool circle;
  final String title;

  static const maxZoom = 5.0;

  /// Parte da imagem visível na moldura, em frações da imagem mostrada
  /// ([content]) — mesma conta usada ao confirmar. Função pura para teste.
  static PhotoCrop visibleCrop({
    required Matrix4 transform,
    required Size viewport,
    required Size content,
  }) {
    final scale = transform.getMaxScaleOnAxis();
    final t = transform.getTranslation();
    double frac(double v, double size) => (v / size).clamp(0.0, 1.0);
    final left = frac(-t.x / scale, content.width);
    final top = frac(-t.y / scale, content.height);
    return PhotoCrop(
      left: left,
      top: top,
      width: frac(viewport.width / scale, content.width).clamp(0.0, 1 - left),
      height: frac(viewport.height / scale, content.height).clamp(0.0, 1 - top),
    );
  }

  @override
  State<PhotoCropView> createState() => _PhotoCropViewState();
}

class _PhotoCropViewState extends State<PhotoCropView> {
  final _controller = TransformationController();
  Size? _imageSize;
  bool _failed = false;
  Size? _viewport;
  Size? _content;
  double _zoom = 1;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncZoom);
    _decodeSize();
  }

  Future<void> _decodeSize() async {
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(widget.bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final size = Size(
        descriptor.width.toDouble(),
        descriptor.height.toDouble(),
      );
      descriptor.dispose();
      buffer.dispose();
      if (!mounted) return;
      if (size.isEmpty) throw StateError('imagem vazia');
      setState(() => _imageSize = size);
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_syncZoom)
      ..dispose();
    super.dispose();
  }

  void _syncZoom() {
    final z = _controller.value.getMaxScaleOnAxis();
    if ((z - _zoom).abs() > 0.001) setState(() => _zoom = z);
  }

  /// Ajusta a imagem para cobrir a moldura e a centraliza (primeira vez ou
  /// quando a tela muda de tamanho).
  void _layout(Size viewport, Size image) {
    if (_viewport == viewport) return;
    final cover = [
      viewport.width / image.width,
      viewport.height / image.height,
    ].reduce((a, b) => a > b ? a : b);
    final content = Size(image.width * cover, image.height * cover);
    _viewport = viewport;
    _content = content;
    _zoom = 1;
    _controller.value = Matrix4.identity()
      ..translateByDouble(
        -(content.width - viewport.width) / 2,
        -(content.height - viewport.height) / 2,
        0,
        1,
      );
  }

  /// Zoom pelo controle deslizante, mantendo o centro da moldura.
  void _setZoom(double zoom) {
    final viewport = _viewport, content = _content;
    if (viewport == null || content == null) return;
    final m = _controller.value;
    final old = m.getMaxScaleOnAxis();
    final t = m.getTranslation();
    final cx = (viewport.width / 2 - t.x) / old;
    final cy = (viewport.height / 2 - t.y) / old;
    double clampT(double v, double view, double size) =>
        v.clamp(view - size * zoom, 0.0);
    _controller.value = Matrix4.identity()
      ..translateByDouble(
        clampT(viewport.width / 2 - cx * zoom, viewport.width, content.width),
        clampT(
          viewport.height / 2 - cy * zoom,
          viewport.height,
          content.height,
        ),
        0,
        1,
      )
      ..scaleByDouble(zoom, zoom, 1, 1);
  }

  void _confirm() {
    final viewport = _viewport, content = _content;
    if (viewport == null || content == null) return;
    Navigator.of(context).pop(
      PhotoCropView.visibleCrop(
        transform: _controller.value,
        viewport: viewport,
        content: content,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final image = _imageSize;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        // O tema do app usa título e botões escuros: aqui o fundo é preto.
        titleTextStyle: theme.textTheme.titleLarge?.copyWith(
          color: Colors.white,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          key: const Key('photo-crop-cancel'),
          tooltip: 'Cancelar',
          color: Colors.white,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(widget.title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              key: const Key('photo-crop-confirm'),
              onPressed: image == null ? null : _confirm,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                disabledBackgroundColor: Colors.white24,
              ),
              child: const Text('Usar'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: _failed
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Não foi possível abrir esta imagem. Escolha outra.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ),
              )
            : image == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: AspectRatio(
                          aspectRatio: widget.aspectRatio,
                          child: LayoutBuilder(
                            builder: (context, box) {
                              final viewport = box.biggest;
                              _layout(viewport, image);
                              final content = _content!;
                              return Stack(
                                fit: StackFit.expand,
                                children: [
                                  ClipRect(
                                    child: InteractiveViewer(
                                      key: const Key('photo-crop-viewer'),
                                      transformationController: _controller,
                                      constrained: false,
                                      minScale: 1,
                                      maxScale: PhotoCropView.maxZoom,
                                      child: SizedBox.fromSize(
                                        size: content,
                                        child: Image.memory(
                                          widget.bytes,
                                          fit: BoxFit.fill,
                                          gaplessPlayback: true,
                                        ),
                                      ),
                                    ),
                                  ),
                                  IgnorePointer(
                                    child: CustomPaint(
                                      painter: _FramePainter(
                                        circle: widget.circle,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                    child: Text(
                      'Arraste para posicionar e use dois dedos ou o controle '
                      'abaixo para aproximar.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Row(
                      children: [
                        const Icon(Icons.zoom_out, color: Colors.white70),
                        Expanded(
                          child: Slider(
                            key: const Key('photo-crop-zoom'),
                            value: _zoom.clamp(1.0, PhotoCropView.maxZoom),
                            min: 1,
                            max: PhotoCropView.maxZoom,
                            label: 'Zoom',
                            activeColor: Colors.white,
                            inactiveColor: Colors.white24,
                            thumbColor: Colors.white,
                            onChanged: _setZoom,
                          ),
                        ),
                        const Icon(Icons.zoom_in, color: Colors.white70),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Moldura: escurece fora do círculo (perfil) e desenha a borda.
class _FramePainter extends CustomPainter {
  const _FramePainter({required this.circle});
  final bool circle;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    if (circle) {
      final hole = Path()..addOval(rect.deflate(1));
      final shade = Path.combine(
        PathOperation.difference,
        Path()..addRect(rect),
        hole,
      );
      canvas
        ..drawPath(shade, Paint()..color = Colors.black54)
        ..drawPath(hole, border);
    } else {
      canvas.drawRect(rect.deflate(1), border);
    }
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.circle != circle;
}
