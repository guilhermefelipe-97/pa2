import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../domain/models/place.dart';
import '../../domain/models/scores.dart';
import 'share_service.dart';

/// Texto que acompanha a imagem (F21). Só dados públicos do local + link.
String placeShareText(Place place) {
  final where = [
    place.category,
    place.neighborhood,
  ].where((s) => s.trim().isNotEmpty).join(' em ');
  return [
    '${place.name}${where.isEmpty ? '' : ' — $where'}',
    'Vi no NaÁrea: ${sharedPlaceLink(place.id)}',
  ].join('\n');
}

/// Abre a prévia do card e envia pela folha de compartilhamento do sistema.
Future<void> showPlaceShareSheet(
  BuildContext context, {
  required Place place,
  AxisAverages? averages,
}) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (_) => PlaceShareSheet(place: place, averages: averages),
);

class PlaceShareSheet extends StatefulWidget {
  const PlaceShareSheet({super.key, required this.place, this.averages});
  final Place place;
  final AxisAverages? averages;
  @override
  State<PlaceShareSheet> createState() => _PlaceShareSheetState();
}

class _PlaceShareSheetState extends State<PlaceShareSheet> {
  final cardKey = GlobalKey();
  String? sharer;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    final uid = context.read<AuthRepository>().currentUserId;
    if (uid != null) {
      context
          .read<UserRepository>()
          .getProfile(uid)
          .timeout(const Duration(seconds: 5))
          .then((p) {
            if (mounted) setState(() => sharer = p?.displayName);
          }, onError: (Object _) {});
    }
  }

  Future<void> send() async {
    final service = context.read<ShareService?>();
    if (service == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final boundary =
          cardKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      await service.shareImage(
        png: data!.buffer.asUint8List(),
        text: placeShareText(widget.place),
        subject: widget.place.name,
      );
      if (mounted) Navigator.of(context).pop();
    } on Object {
      if (mounted) {
        setState(() => error = 'Não foi possível compartilhar. Tente de novo.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Compartilhar local', style: theme.textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            'Vai uma imagem com o card e um link. Quem não tem o app vê o card '
            'e a página do link; quem tem abre direto a ficha.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Center(
            child: FittedBox(
              child: RepaintBoundary(
                key: cardKey,
                child: PlaceShareCard(
                  place: widget.place,
                  averages: widget.averages,
                  sharer: sharer,
                ),
              ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('share-send'),
              onPressed: busy ? null : send,
              icon: const Icon(Icons.send_outlined, size: 18),
              label: Text(busy ? 'Preparando…' : 'Enviar'),
            ),
          ),
        ],
      ),
    );
  }
}

/// O card em si (F21): tamanho fixo para a imagem sair igual em qualquer tela.
class PlaceShareCard extends StatelessWidget {
  const PlaceShareCard({
    super.key,
    required this.place,
    this.averages,
    this.sharer,
  });
  final Place place;
  final AxisAverages? averages;
  final String? sharer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final subtitle = [
      place.category,
      place.neighborhood,
      place.city,
    ].where((s) => s.trim().isNotEmpty).join(' · ');
    final a = averages;
    Widget axis(String label, AxisAverage value) => Expanded(
      child: Column(
        children: [
          Text(
            value.value == null ? '—' : formatAverage(value.value!),
            style: theme.textTheme.headlineSmall?.copyWith(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
    return MediaQuery.withNoTextScaling(
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'NaÁrea',
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              place.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: scheme.onPrimaryContainer,
              ),
            ),
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onPrimaryContainer,
                ),
              ),
            const SizedBox(height: 16),
            if (a != null) ...[
              Row(
                children: [
                  axis('Comida', a.food),
                  axis('Ambiente', a.ambience),
                  axis('Atendimento', a.service),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Médias de ${reviewCountLabel(a.total)} da rede de '
                '${sharer ?? 'quem enviou'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ] else
              Text(
                'Ainda sem avaliações da rede de quem enviou.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onPrimaryContainer,
                ),
              ),
            const SizedBox(height: 16),
            Text(
              sharer == null ? 'Indicação no NaÁrea' : 'Indicado por $sharer',
              style: theme.textTheme.titleSmall?.copyWith(
                color: scheme.onPrimaryContainer,
              ),
            ),
            Text(
              '$sharedLinkHost/l/…',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
