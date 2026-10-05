import 'package:flutter/material.dart';

import '../../domain/models/place_list.dart';

/// Nome (1–40, aparado, único sem caixa/acento) + emoji opcional de uma
/// lista. Usado no "Nova lista" do sheet e no diálogo de renomear.
class ListNameForm extends StatefulWidget {
  const ListNameForm({
    super.key,
    required this.submitLabel,
    required this.isTaken,
    required this.onSubmit,
    this.onCancel,
    this.initialName = '',
    this.initialEmoji,
  });

  final String submitLabel;
  final String initialName;
  final String? initialEmoji;

  /// Nome já usado por outra lista do usuário?
  final bool Function(String name) isTaken;
  final void Function(String name, String? emoji) onSubmit;
  final VoidCallback? onCancel;

  static const takenMessage = 'Você já tem uma lista com esse nome';

  @override
  State<ListNameForm> createState() => _ListNameFormState();
}

class _ListNameFormState extends State<ListNameForm> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  late String? _emoji = widget.initialEmoji;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _trimmed => PlaceList.normalizeName(_name.text);

  bool get _taken {
    if (_trimmed.isEmpty) return false;
    // Renomear para o mesmo nome (ou só mudar a caixa) não é repetição.
    if (PlaceList.nameKey(_trimmed) == PlaceList.nameKey(widget.initialName)) {
      return false;
    }
    return widget.isTaken(_trimmed);
  }

  bool get _valid => PlaceList.isValidName(_name.text) && !_taken;

  void _submit() {
    if (!_valid) return;
    widget.onSubmit(_trimmed, _emoji);
  }

  @override
  Widget build(BuildContext context) {
    final length = _trimmed.length;
    final tooLong = length > PlaceList.maxNameLength;
    final error = _taken
        ? ListNameForm.takenMessage
        : tooLong
        ? 'Use até ${PlaceList.maxNameLength} caracteres'
        : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('list-name-field'),
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: 'Nome da lista',
            hintText: 'Ex.: Sábado com as meninas',
            errorText: error,
            counterText: '$length/${PlaceList.maxNameLength}',
          ),
        ),
        const SizedBox(height: 12),
        Text('Emoji (opcional)', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final e in listEmojis)
              ChoiceChip(
                key: Key('list-emoji-$e'),
                label: Text(e, style: const TextStyle(fontSize: 18)),
                showCheckmark: false,
                selected: _emoji == e,
                onSelected: (on) => setState(() => _emoji = on ? e : null),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (widget.onCancel != null)
              TextButton(
                onPressed: widget.onCancel,
                child: const Text('Cancelar'),
              ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('list-name-submit'),
              onPressed: _valid ? _submit : null,
              child: Text(widget.submitLabel),
            ),
          ],
        ),
      ],
    );
  }
}
