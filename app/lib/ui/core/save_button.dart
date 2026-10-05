import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../saved/saved_places_store.dart';

/// Visual do marcador conforme o fundo.
enum SaveButtonStyle {
  /// Sobre foto: círculo claro por trás do ícone.
  onImage,

  /// Em barra de app escura/colorida: ícone na cor do primeiro plano.
  onAppBar,

  /// Em lista/fundo claro.
  plain,
}

/// Marcador "Quero ir" (F11): salva/remove o local em 1 toque, sem diálogo.
/// Otimista, com "Desfazer"; falha reverte e avisa. O estado vem do
/// [SavedPlacesStore] (sem ele no contexto, o botão não aparece).
class SaveButton extends StatelessWidget {
  const SaveButton({
    super.key,
    required this.placeId,
    this.style = SaveButtonStyle.plain,
  });

  final String placeId;
  final SaveButtonStyle style;

  static const savedMessage = 'Salvo em Quero ir';
  static const removedMessage = 'Removido de Quero ir';
  static const failureMessage = 'Não foi possível salvar';
  static const saveLabel = 'Salvar em Quero ir';
  static const removeLabel = 'Remover de Quero ir';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<SavedPlacesStore?>();
    if (store == null) return const SizedBox.shrink();
    final saved = store.isSaved(placeId);
    // Sem usuário (idle) ou carregando: não há estado confiável para trocar.
    final enabled = store.isReady || store.hasError;
    final label = saved ? removeLabel : saveLabel;
    final scheme = Theme.of(context).colorScheme;

    final Color color = switch (style) {
      SaveButtonStyle.onImage => saved ? scheme.primary : scheme.onSurface,
      SaveButtonStyle.onAppBar =>
        IconTheme.of(context).color ?? scheme.onPrimary,
      SaveButtonStyle.plain => saved ? scheme.primary : scheme.onSurfaceVariant,
    };

    final icon = AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) =>
          ScaleTransition(scale: animation, child: child),
      child: Icon(
        saved ? Icons.bookmark : Icons.bookmark_border,
        key: ValueKey(saved),
        color: color,
      ),
    );

    final button = IconButton(
      key: Key('save-$placeId'),
      onPressed: enabled ? () => _onPressed(context, store) : null,
      icon: icon,
      style: style == SaveButtonStyle.onImage
          ? IconButton.styleFrom(
              backgroundColor: scheme.surfaceContainerLowest.withValues(
                alpha: 0.92,
              ),
            )
          : null,
    );

    return Semantics(
      button: true,
      toggled: saved,
      enabled: enabled,
      label: label,
      onTap: enabled ? () => _onPressed(context, store) : null,
      excludeSemantics: true,
      child: Tooltip(message: label, excludeFromSemantics: true, child: button),
    );
  }

  Future<void> _onPressed(BuildContext context, SavedPlacesStore store) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!store.isReady) {
      // Carga inicial falhou: tenta de novo antes de desistir.
      await store.reload();
      if (!store.isReady) {
        _show(messenger, const SnackBar(content: Text(failureMessage)));
        return;
      }
    }
    final change = store.toggle(placeId);
    if (change == null) return;
    // Confirmação já no toque (otimista): offline o Future da escrita só
    // completa quando a rede voltar.
    var undone = false;
    _show(
      messenger,
      SnackBar(
        content: Text(change.saved ? savedMessage : removedMessage),
        action: SnackBarAction(
          label: 'Desfazer',
          onPressed: () {
            // Daqui em diante só o resultado do Desfazer é reportado.
            undone = true;
            _report(messenger, store.setSaved(placeId, !change.saved));
          },
        ),
      ),
    );
    final ok = await change.done;
    if (!ok && !undone) {
      _show(messenger, const SnackBar(content: Text(failureMessage)));
    }
  }

  static Future<void> _report(
    ScaffoldMessengerState messenger,
    Future<bool> done,
  ) async {
    if (!await done) {
      _show(messenger, const SnackBar(content: Text(failureMessage)));
    }
  }

  static void _show(ScaffoldMessengerState messenger, SnackBar bar) {
    if (!messenger.mounted) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(bar);
  }
}
