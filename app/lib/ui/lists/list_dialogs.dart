import 'package:flutter/material.dart';

import '../../domain/models/place_list.dart';
import 'list_name_form.dart';
import 'lists_store.dart';

/// Renomear (nome + emoji) com as mesmas validações da criação. Completa com
/// `null` se cancelou; senão, com o resultado da escrita.
Future<bool?> showRenameListDialog(
  BuildContext context,
  ListsStore lists,
  PlaceList list,
) async {
  final values = await showDialog<({String name, String? emoji})>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Renomear lista'),
      content: SingleChildScrollView(
        child: ListNameForm(
          submitLabel: 'Salvar',
          initialName: list.name,
          initialEmoji: list.emoji,
          isTaken: (name) => lists.isNameTaken(name, exceptId: list.id),
          onCancel: () => Navigator.of(context).pop(),
          onSubmit: (name, emoji) =>
              Navigator.of(context).pop((name: name, emoji: emoji)),
        ),
      ),
    ),
  );
  if (values == null) return null;
  return lists.rename(list.id, values.name, emoji: values.emoji);
}

/// Pede confirmação antes de excluir. `true` = confirmou.
Future<bool> confirmDeleteList(BuildContext context, PlaceList list) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Excluir lista?'),
      content: Text(
        '"${list.label}" será excluída. Os locais continuam no Quero ir.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('confirm-delete-list'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Excluir'),
        ),
      ],
    ),
  );
  return ok ?? false;
}
