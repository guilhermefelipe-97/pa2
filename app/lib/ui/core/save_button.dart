import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../lists/add_to_list_sheet.dart';
import '../lists/lists_store.dart';
import '../saved/saved_places_store.dart';
import 'messages.dart';

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
  static const failureMessage = saveFailureMessage;
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
      onPressed: enabled ? () => _onPressed(context) : null,
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
      onTap: enabled ? () => _onPressed(context) : null,
      excludeSemantics: true,
      child: Tooltip(message: label, excludeFromSemantics: true, child: button),
    );
  }

  void _onPressed(BuildContext context) {
    QueroIrActions.toggle(context, placeId);
  }
}

/// Fluxos do "Quero ir" compartilhados pelo marcador e pelo menu do card da
/// aba: troca otimista, SnackBar com "Desfazer" (e "Adicionar a lista" ao
/// salvar, F12), aviso de falha.
abstract final class QueroIrActions {
  static const addToListLabel = 'Adicionar a lista';
  static const undoLabel = 'Desfazer';

  /// "Removido de Quero ir" / "... e de 1 lista" / "... e de 2 listas".
  static String removedMessageFor(int lists) => switch (lists) {
    0 => SaveButton.removedMessage,
    1 => '${SaveButton.removedMessage} e de 1 lista',
    _ => '${SaveButton.removedMessage} e de $lists listas',
  };

  /// Inverte o estado de [placeId].
  static Future<void> toggle(BuildContext context, String placeId) =>
      _change(context, placeId, null);

  /// Tira [placeId] do "Quero ir" (e de todas as listas, no mesmo batch).
  static Future<void> remove(BuildContext context, String placeId) =>
      _change(context, placeId, false);

  static Future<void> _change(
    BuildContext context,
    String placeId,
    bool? target,
  ) async {
    final store = context.read<SavedPlacesStore?>();
    if (store == null) return;
    final lists = context.read<ListsStore?>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    final actionColor = Theme.of(context).colorScheme.inversePrimary;
    if (!store.isReady) {
      // Carga inicial falhou: tenta de novo antes de desistir.
      await store.reload();
      if (!store.isReady) {
        _show(messenger, const SnackBar(content: Text(saveFailureMessage)));
        return;
      }
    }
    final saved = target ?? !store.isSaved(placeId);
    if (saved == store.isSaved(placeId)) return;
    // Listas de onde o local sai junto (para a mensagem e o "Desfazer").
    final fromLists = saved || lists == null
        ? const <String>[]
        : [for (final l in lists.listsContaining(placeId)) l.id];
    final done = store.setSaved(placeId, saved);

    // Confirmação já no toque (otimista): offline o Future da escrita só
    // completa quando a rede voltar.
    var undone = false;
    void undo() {
      // Daqui em diante só o resultado do Desfazer é reportado.
      undone = true;
      if (!saved && lists != null) {
        _reportRestore(messenger, lists.restore(placeId, fromLists));
      } else {
        _report(messenger, store.setSaved(placeId, !saved));
      }
    }

    void undoFromContent() {
      messenger.hideCurrentSnackBar();
      undo();
    }

    final SnackBar bar;
    if (saved && lists != null) {
      bar = SnackBar(
        content: Row(
          children: [
            const Expanded(child: Text(SaveButton.savedMessage)),
            // "Adicionar a lista" é a action; o "Desfazer" fica no conteúdo,
            // como botão acessível (rótulo, toque e foco de teclado).
            Semantics(
              container: true,
              button: true,
              label: undoLabel,
              onTap: undoFromContent,
              excludeSemantics: true,
              child: TextButton(
                key: const Key('snackbar-undo'),
                style: TextButton.styleFrom(foregroundColor: actionColor),
                onPressed: undoFromContent,
                child: const Text(undoLabel),
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: addToListLabel,
          onPressed: () {
            if (navigator.mounted) {
              showAddToListSheet(navigator.context, placeId);
            }
          },
        ),
      );
    } else {
      bar = SnackBar(
        content: Text(
          saved ? SaveButton.savedMessage : removedMessageFor(fromLists.length),
        ),
        action: SnackBarAction(label: undoLabel, onPressed: undo),
      );
    }
    _show(messenger, bar);
    final ok = await done;
    if (!ok && !undone) {
      _show(messenger, const SnackBar(content: Text(saveFailureMessage)));
    }
  }

  static Future<void> _report(
    ScaffoldMessengerState messenger,
    Future<bool> done,
  ) async {
    if (!await done) {
      _show(messenger, const SnackBar(content: Text(saveFailureMessage)));
    }
  }

  static Future<void> _reportRestore(
    ScaffoldMessengerState messenger,
    Future<RestoreResult> done,
  ) async {
    final message = switch (await done) {
      RestoreResult.ok => null,
      RestoreResult.savedFailed => saveFailureMessage,
      RestoreResult.someListsFailed => restoreListsFailureMessage,
    };
    if (message != null) _show(messenger, SnackBar(content: Text(message)));
  }

  static void _show(ScaffoldMessengerState messenger, SnackBar bar) {
    if (!messenger.mounted) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(bar);
  }
}
