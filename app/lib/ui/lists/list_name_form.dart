import 'package:flutter/material.dart';

import '../../domain/models/place_list.dart';
import 'list_category.dart';

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
            labelText: 'Título',
            hintText: 'Ex.: Cafés para conhecer',
            errorText: error,
            counterText: '$length/${PlaceList.maxNameLength}',
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Categoria sugerida (opcional)',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final category in listCategories)
              ChoiceChip(
                key: Key('list-emoji-${category.value}'),
                label: FittedBox(child: Text(category.label, maxLines: 1)),
                avatar: Icon(
                  category.icon,
                  size: 18,
                  color: _emoji == category.value
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.secondary,
                ),
                showCheckmark: false,
                selected: _emoji == category.value,
                onSelected: (on) =>
                    setState(() => _emoji = on ? category.value : null),
              ),
          ],
        ),
        const SizedBox(height: 12),
        OverflowBar(
          alignment: MainAxisAlignment.end,
          spacing: 8,
          overflowSpacing: 8,
          children: [
            if (widget.onCancel != null)
              TextButton(
                onPressed: widget.onCancel,
                child: const FittedBox(child: Text('Cancelar', maxLines: 1)),
              ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('list-name-submit'),
              onPressed: _valid ? _submit : null,
              child: FittedBox(child: Text(widget.submitLabel, maxLines: 1)),
            ),
          ],
        ),
      ],
    );
  }
}
