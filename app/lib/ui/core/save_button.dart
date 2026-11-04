import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../lists/add_to_list_sheet.dart';
import '../lists/lists_store.dart';
import '../saved/saved_places_store.dart';
import 'messages.dart';

enum SaveButtonStyle { onImage, onAppBar, plain }

class SaveButton extends StatelessWidget {
  const SaveButton({
    super.key,
    required this.placeId,
    this.style = SaveButtonStyle.plain,
    this.showLabel = false,
    this.prominent = false,
    this.compact = false,
  });

  final String placeId;
  final SaveButtonStyle style;
  final bool showLabel;
  final bool prominent;
  final bool compact;

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

    final enabled = store.isReady || store.hasError;
    final label = saved ? removeLabel : saveLabel;
    final scheme = Theme.of(context).colorScheme;

    final Color color = prominent
        ? scheme.onPrimary
        : switch (style) {
            SaveButtonStyle.onImage =>
              saved ? scheme.primary : scheme.onSurface,
            SaveButtonStyle.onAppBar =>
              IconTheme.of(context).color ?? scheme.onPrimary,
            SaveButtonStyle.plain =>
              saved ? scheme.primary : scheme.onSurfaceVariant,
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
        size: compact ? 16 : null,
      ),
    );

    final button = showLabel
        ? FilledButton.tonalIcon(
            style: compact
                ? FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    minimumSize: const Size(0, 44),
                    textStyle: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  )
                : prominent
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    textStyle: Theme.of(context).textTheme.labelMedium,
                  )
                : null,
            key: Key('save-$placeId'),
            onPressed: enabled ? () => _onPressed(context) : null,
            icon: icon,
            label: compact
                ? FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      saved ? 'Salvo' : 'Quero ir',
                      maxLines: 1,
                      softWrap: false,
                    ),
                  )
                : Text(saved ? 'Salvo' : 'Quero ir'),
          )
        : IconButton(
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

abstract final class QueroIrActions {
  static const addToListLabel = 'Adicionar a lista';
  static const undoLabel = 'Desfazer';

  static String removedMessageFor(int lists) => switch (lists) {
    0 => SaveButton.removedMessage,
    1 => '${SaveButton.removedMessage} e de 1 lista',
    _ => '${SaveButton.removedMessage} e de $lists listas',
  };

  static Future<void> toggle(BuildContext context, String placeId) =>
      _change(context, placeId, null);

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
      await store.reload();
      if (!store.isReady) {
        _show(messenger, const SnackBar(content: Text(saveFailureMessage)));
        return;
      }
    }
    final saved = target ?? !store.isSaved(placeId);
    if (saved == store.isSaved(placeId)) return;

    final fromLists = saved || lists == null
        ? const <String>[]
        : [for (final l in lists.listsContaining(placeId)) l.id];
    final done = store.setSaved(placeId, saved);

    var undone = false;
    void undo() {
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
