import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/taste_match_service.dart';
import '../../domain/taste_match.dart';

/// Selo "Gosto parecido" (F07). Só aparece quando a regra dá "sim"; carregando,
/// com erro, sem serviço ou para o próprio usuário não ocupa espaço.
class TasteMatchBadge extends StatefulWidget {
  const TasteMatchBadge({super.key, required this.uid, this.detailed = false});
  final String uid;

  /// No perfil: acrescenta "em N lugares em comum".
  final bool detailed;

  @override
  State<TasteMatchBadge> createState() => _TasteMatchBadgeState();
}

class _TasteMatchBadgeState extends State<TasteMatchBadge> {
  Future<TasteMatch>? read;
  String? me;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = context.watch<AuthRepository?>()?.currentUserId;
    if (current == me && read != null) return;
    me = current;
    final service = context.read<TasteMatchService?>();
    read = current == null || service == null || current == widget.uid
        ? null
        : service.matchFor(current, widget.uid);
  }

  @override
  Widget build(BuildContext context) {
    if (read == null) return const SizedBox.shrink();
    return FutureBuilder<TasteMatch>(
      future: read,
      builder: (context, snap) {
        final match = snap.data;
        if (match == null || !match.similar) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        final text = widget.detailed
            ? 'Gosto parecido · em ${match.commonPlaces} lugares em comum'
            : 'gosto parecido';
        return Container(
          key: ValueKey('taste-match-${widget.uid}'),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: scheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: scheme.onTertiaryContainer,
              fontSize: widget.detailed ? 12 : 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      },
    );
  }
}
