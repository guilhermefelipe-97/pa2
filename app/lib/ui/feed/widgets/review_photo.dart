import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/review_photo_repository.dart';
import '../../../domain/models/review.dart';

/// Crédito visível sobre a foto: "Foto de Ana"; "Sua foto" quando a avaliação
/// é do próprio usuário ([isOwn]); sem nome, "Foto de um amigo".
String photoCreditText(String authorName, {bool isOwn = false}) {
  if (isOwn) return 'Sua foto';
  final name = authorName.trim();
  return name.isEmpty ? 'Foto de um amigo' : 'Foto de $name';
}

/// Rótulo para leitores de tela: "Foto de Ana em Mangai".
String photoSemanticLabel(
  String authorName,
  String placeName, {
  bool isOwn = false,
}) => '${photoCreditText(authorName, isOwn: isOwn)} em $placeName';

/// Foto enviada por quem avaliou, carregada sob demanda (só quando o widget é
/// construído, isto é, quando o card ou a miniatura aparece) pelo
/// [ReviewPhotoRepository] do contexto, que guarda em cache. Já em cache, a
/// foto aparece na hora, sem fade.
///
/// Enquanto carrega mostra [loadingPlaceholder]; se falhar ou não existir,
/// [errorPlaceholder]. Os dois são vazios por padrão, deixando à vista o que
/// estiver por baixo (foto do catálogo ou fallback da categoria), sem erro
/// visível. Com a foto, o crédito "Foto de Ana" fica sempre por cima.
class ReviewPhoto extends StatefulWidget {
  const ReviewPhoto({
    super.key,
    required this.review,
    required this.placeName,
    this.isOwn = false,
    this.fit = BoxFit.cover,
    this.creditPadding = const EdgeInsets.all(8),
    this.showCredit = true,
    this.compactCredit = false,
    this.decodeWidth = true,
    this.loadingPlaceholder,
    this.errorPlaceholder,
  });

  final Review review;
  final String placeName;

  /// A avaliação é do usuário logado (`authorId == uid`): crédito "Sua foto".
  final bool isOwn;
  final BoxFit fit;

  /// Distância do crédito até o canto inferior esquerdo.
  final EdgeInsets creditPadding;
  final bool showCredit;

  /// Crédito menor (miniaturas).
  final bool compactCredit;

  /// Decodifica no tamanho em que será desenhada (desligar no zoom).
  final bool decodeWidth;

  final Widget? loadingPlaceholder;
  final Widget? errorPlaceholder;

  @override
  State<ReviewPhoto> createState() => _ReviewPhotoState();
}

class _ReviewPhotoState extends State<ReviewPhoto> {
  Uint8List? _bytes;
  bool _failed = false;

  /// Veio do cache já resolvido: sem fade.
  bool _instant = false;

  /// Descarta respostas de um id anterior.
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ReviewPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Outro id: nunca mostra os bytes do anterior.
    if (oldWidget.review.id != widget.review.id) _load();
  }

  void _load() {
    final token = ++_token;
    final id = widget.review.id;
    final repo = context.read<ReviewPhotoRepository>();
    _failed = false;
    final cached = repo.peek(id);
    if (cached != null) {
      _bytes = cached;
      _instant = true;
      return;
    }
    _bytes = null;
    _instant = false;
    repo
        .getPhoto(id)
        .then(
          (bytes) {
            if (!mounted || token != _token) return;
            setState(() {
              _bytes = bytes;
              _failed = bytes == null || bytes.isEmpty;
            });
          },
          onError: (Object _) {
            if (!mounted || token != _token) return;
            setState(() => _failed = true);
          },
        );
  }

  Widget get _error => widget.errorPlaceholder ?? const SizedBox.shrink();

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (_failed) return _error;
    if (bytes == null || bytes.isEmpty) {
      return widget.loadingPlaceholder ?? const SizedBox.shrink();
    }
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final cacheWidth = widget.decodeWidth && width.isFinite && width > 0
            ? (width * dpr).round()
            : null;
        return Image.memory(
          bytes,
          key: Key('review-photo-${widget.review.id}'),
          fit: widget.fit,
          cacheWidth: cacheWidth,
          semanticLabel: photoSemanticLabel(
            widget.review.authorName,
            widget.placeName,
            isOwn: widget.isOwn,
          ),
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            final shown = frame != null || wasSynchronouslyLoaded;
            return AnimatedOpacity(
              opacity: shown ? 1 : 0,
              duration: _instant || wasSynchronouslyLoaded
                  ? Duration.zero
                  : const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  child,
                  // O crédito só aparece junto com a foto decodificada.
                  if (shown && widget.showCredit)
                    Positioned(
                      left: widget.creditPadding.left,
                      bottom: widget.creditPadding.bottom,
                      right: widget.creditPadding.right,
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: PhotoCreditChip(
                          text: photoCreditText(
                            widget.review.authorName,
                            isOwn: widget.isOwn,
                          ),
                          compact: widget.compactCredit,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
          // Bytes corrompidos: mesmo tratamento de foto que falhou.
          errorBuilder: (context, error, stackTrace) => _error,
        );
      },
    );
  }
}

/// Selo escuro com o crédito da foto, legível sobre qualquer imagem.
class PhotoCreditChip extends StatelessWidget {
  const PhotoCreditChip({super.key, required this.text, this.compact = false});

  final String text;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // O rótulo da imagem já diz quem tirou a foto: o selo não é lido de novo.
    return ExcludeSemantics(
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 10,
          vertical: compact ? 2 : 4,
        ),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.photo_camera,
              size: compact ? 11 : 14,
              color: Colors.white,
            ),
            SizedBox(width: compact ? 3 : 5),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 11 : 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
