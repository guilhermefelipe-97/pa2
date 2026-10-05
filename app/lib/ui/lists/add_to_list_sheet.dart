import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/models/place_list.dart';
import '../core/messages.dart';
import '../saved/saved_places_store.dart';
import 'list_name_form.dart';
import 'lists_store.dart';

/// Abre o "Adicionar a lista" de [placeId] (F12). Sem [ListsStore] no
/// contexto, não faz nada.
Future<void> showAddToListSheet(BuildContext context, String placeId) async {
  if (context.read<ListsStore?>() == null) return;
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => AddToListSheet(placeId: placeId),
  );
}

/// Bottom sheet com as listas marcáveis e "Nova lista" inline. Marcar salva
/// o local no "Quero ir"; desmarcar tira só daquela lista.
class AddToListSheet extends StatefulWidget {
  const AddToListSheet({super.key, required this.placeId});

  final String placeId;

  static const title = 'Adicionar a lista';
  static const failureMessage = saveFailureMessage;
  static const signedOutMessage = 'Entre para usar listas';
  static const limitMessage =
      'Você chegou ao limite de ${PlaceList.maxLists} listas';

  @override
  State<AddToListSheet> createState() => _AddToListSheetState();
}

class _AddToListSheetState extends State<AddToListSheet> {
  bool _creating = false;
  bool _failed = false;

  String get _placeId => widget.placeId;

  Future<void> _track(Future<bool> done) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await done;
    if (ok) return;
    if (mounted) {
      setState(() => _failed = true);
    } else if (messenger != null && messenger.mounted) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text(AddToListSheet.failureMessage)),
        );
    }
  }

  void _toggle(ListsStore lists, PlaceList list, bool member) {
    setState(() => _failed = false);
    _track(lists.setMembership(list.id, _placeId, member));
  }

  void _create(ListsStore lists, String name, String? emoji) {
    final created = lists.create(name, emoji: emoji, withPlace: _placeId);
    setState(() {
      _creating = false;
      _failed = created == null;
    });
    if (created != null) _track(created.done);
  }

  @override
  Widget build(BuildContext context) {
    final lists = context.watch<ListsStore>();
    // Reconstrói quando o "Quero ir" muda (contagens).
    context.watch<SavedPlacesStore?>();
    final theme = Theme.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    final Widget body;
    if (lists.isIdle) {
      // Sem usuário: não há o que carregar (nada de spinner eterno).
      body = const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text(AddToListSheet.signedOutMessage)),
      );
    } else if (lists.hasError) {
      body = Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('Não foi possível carregar suas listas.'),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: lists.reload,
              child: const Text('Tentar de novo'),
            ),
          ],
        ),
      );
    } else if (!lists.isReady) {
      body = const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    } else {
      final all = lists.lists;
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final list in all) _tile(lists, list),
          if (_creating)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: ListNameForm(
                key: const Key('new-list-form'),
                submitLabel: 'Criar',
                isTaken: lists.isNameTaken,
                onCancel: () => setState(() => _creating = false),
                onSubmit: (name, emoji) => _create(lists, name, emoji),
              ),
            )
          else
            ListTile(
              key: const Key('new-list'),
              leading: const Icon(Icons.add),
              title: const Text('Nova lista'),
              subtitle: lists.canCreate
                  ? null
                  : const Text(AddToListSheet.limitMessage),
              enabled: lists.canCreate,
              onTap: () => setState(() {
                _creating = true;
                _failed = false;
              }),
            ),
        ],
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  AddToListSheet.title,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              if (_failed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text(
                    AddToListSheet.failureMessage,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              body,
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(ListsStore lists, PlaceList list) {
    final member = list.contains(_placeId);
    final full = !member && list.isFull;
    final count = lists.countOf(list);
    return CheckboxListTile(
      key: Key('list-check-${list.id}'),
      value: member,
      onChanged: full ? null : (v) => _toggle(lists, list, v ?? false),
      title: Text(list.label),
      subtitle: Text(
        full
            ? 'Lista cheia (${PlaceList.maxPlaces} locais)'
            : count == 1
            ? '1 local'
            : '$count locais',
      ),
      controlAffinity: ListTileControlAffinity.trailing,
    );
  }
}
