import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../domain/models/place.dart';
import '../../core/category_style.dart';

/// Foto de capa do local. O fallback (gradiente + ícone da categoria) fica
/// sempre por baixo: aparece sem URL, enquanto carrega e com a URL quebrada
/// (404, sem rede). Nunca mostra erro. O tamanho vem do pai (ex.:
/// `AspectRatio(16/9)`).
class PlacePhoto extends StatelessWidget {
  const PlacePhoto({super.key, required this.place, this.iconSize = 48});

  final Place place;
  final double iconSize;

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
    final fallback = _PhotoFallback(
      category: place.category,
      iconSize: iconSize,
    );
    if (url == null || url.isEmpty) return fallback;
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
            Image.network(
              url,
              headers: kIsWeb ? null : _nativeHeaders,
              cacheWidth: cacheWidth,
              fit: BoxFit.cover,
              semanticLabel: semanticLabelFor(place),
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
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
          ],
        );
      },
    );
  }
}

class _PhotoFallback extends StatelessWidget {
  const _PhotoFallback({required this.category, required this.iconSize});

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
