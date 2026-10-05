import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../domain/models/place.dart';
import '../../../domain/models/review.dart';
import '../../core/category_style.dart';
import 'review_photo.dart';

/// Foto de capa do local, em camadas (a de cima cobre as de baixo):
/// 1. foto do amigo ([friendPhoto], a avaliação mais recente com foto), com
///    o crédito "Foto de Ana";
/// 2. foto do catálogo (`place.photoUrl`);
/// 3. fallback (gradiente + ícone da categoria).
/// Cada camada só aparece quando carrega: sem foto, enquanto carrega ou com
/// falha, a de baixo continua visível. Nunca mostra erro. O tamanho vem do
/// pai (ex.: `AspectRatio(16/9)`).
class PlacePhoto extends StatelessWidget {
  const PlacePhoto({
    super.key,
    required this.place,
    this.iconSize = 48,
    this.friendPhoto,
    this.creditPadding = const EdgeInsets.all(8),
    this.friendPhotoIsOwn = false,
  });

  final Place place;
  final double iconSize;

  /// Avaliação (com `hasPhoto`) cuja foto vira a capa.
  final Review? friendPhoto;

  /// Posição do crédito da foto do amigo (canto inferior esquerdo).
  final EdgeInsets creditPadding;

  /// [friendPhoto] é do próprio usuário: crédito "Sua foto".
  final bool friendPhotoIsOwn;

  /// A Wikimedia pede User-Agent identificável com contato. No navegador o
  /// cabeçalho é proibido (e ignorado), então só vai nas plataformas nativas.
  static const Map<String, String> _nativeHeaders = {
    'User-Agent':
        'NaArea/1.0 (https://github.com/guilhermefelipe-97/pa2; projeto academico)',
  };

  /// Texto para leitores de tela: não finge que a imagem é do local quando
  /// ela é só ilustrativa.
  static String semanticLabelFor(Place place) => place.photoIllustrative
      ? 'Imagem ilustrativa, não é do próprio local: ${place.name}'
      : 'Foto de ${place.name}';

  @override
  Widget build(BuildContext context) {
    final url = place.photoUrl;
    final friend = friendPhoto?.hasPhoto == true ? friendPhoto : null;
    final fallback = PlacePhotoFallback(
      category: place.category,
      iconSize: iconSize,
    );
    final hasUrl = url != null && url.isNotEmpty;
    if (!hasUrl && friend == null) return fallback;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // Decodifica no tamanho em que será desenhada (economiza memória).
        final cacheWidth = width.isFinite && width > 0
            ? (width * dpr).round()
            : null;
        return Stack(
          fit: StackFit.expand,
          children: [
            fallback,
            if (hasUrl)
              // Com foto de amigo por cima, só o rótulo dela é lido.
              ExcludeSemantics(
                excluding: friend != null,
                child: Image.network(
                  url,
                  headers: kIsWeb ? null : _nativeHeaders,
                  cacheWidth: cacheWidth,
                  fit: BoxFit.cover,
                  semanticLabel: semanticLabelFor(place),
                  frameBuilder:
                      (context, child, frame, wasSynchronouslyLoaded) {
                        if (wasSynchronouslyLoaded) return child;
                        return AnimatedOpacity(
                          opacity: frame == null ? 0 : 1,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                          child: child,
                        );
                      },
                  // O fallback já está por baixo.
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox.shrink(),
                ),
              ),
            if (friend != null)
              ReviewPhoto(
                review: friend,
                placeName: place.name,
                isOwn: friendPhotoIsOwn,
                creditPadding: creditPadding,
              ),
          ],
        );
      },
    );
  }
}

/// Gradiente + ícone da categoria (quando não há foto).
class PlacePhotoFallback extends StatelessWidget {
  const PlacePhotoFallback({
    super.key,
    required this.category,
    required this.iconSize,
  });

  final String category;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('place-photo-fallback'),
      decoration: BoxDecoration(gradient: categoryGradient(category)),
      child: SizedBox.expand(
        child: Center(
          child: Icon(
            categoryIcon(category),
            size: iconSize,
            color: Colors.white.withValues(alpha: 0.9),
          ),
        ),
      ),
    );
  }
}
