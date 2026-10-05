import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/companion.dart';
import '../../domain/models/review.dart';
import 'review_view_model.dart';

class ReviewView extends StatelessWidget {
  const ReviewView({super.key, required this.viewModel});

  final ReviewViewModel viewModel;

  Future<void> _submit(BuildContext context) async {
    final ok = await viewModel.submit();
    if (ok && context.mounted) context.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(viewModel.place.name)),
      body: ListenableBuilder(
        listenable: viewModel,
        builder: (context, _) {
          final vm = viewModel;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${vm.place.category} · ${vm.place.neighborhood}',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              _AxisPicker(
                label: 'Comida',
                value: vm.food,
                onChanged: vm.setFood,
                enabled: !vm.isSubmitting,
              ),
              _AxisPicker(
                label: 'Ambiente',
                value: vm.ambience,
                onChanged: vm.setAmbience,
                enabled: !vm.isSubmitting,
              ),
              _AxisPicker(
                label: 'Atendimento',
                value: vm.service,
                onChanged: vm.setService,
                enabled: !vm.isSubmitting,
              ),
              const SizedBox(height: 16),
              Text(
                'Com quem você foi? (opcional)',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in Companion.values)
                    ChoiceChip(
                      label: Text(c.label),
                      selected: vm.companion == c,
                      onSelected: vm.isSubmitting
                          ? null
                          : (_) => vm.toggleCompanion(c),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              TextField(
                key: const Key('review-comment'),
                enabled: !vm.isSubmitting,
                onChanged: vm.setComment,
                minLines: 2,
                maxLines: 5,
                maxLength: Review.maxCommentLength,
                // O maxLength do Flutter conta grafemas; as Rules contam
                // unidades UTF-16. Este formatter garante a conta das Rules.
                inputFormatters: const [
                  Utf16LengthLimitingFormatter(Review.maxCommentLength),
                ],
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Conta pra galera como foi (opcional)',
                  hintText: 'Ex.: camarão no ponto, fila grande no sábado',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'O período do dia é registrado automaticamente pelo horário do envio.',
                style: theme.textTheme.bodySmall,
              ),
              if (vm.errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  vm.errorMessage!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                key: const Key('review-submit'),
                onPressed: vm.canSubmit ? () => _submit(context) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: vm.isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Enviar'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AxisPicker extends StatelessWidget {
  const _AxisPicker({
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final int? value;
  final ValueChanged<int> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            emptySelectionAllowed: true,
            showSelectedIcon: false,
            segments: [
              for (var i = 1; i <= 5; i++)
                ButtonSegment<int>(value: i, label: Text('$i')),
            ],
            selected: value == null ? <int>{} : {value!},
            // null desabilita o SegmentedButton (ex.: durante o envio).
            onSelectionChanged: enabled
                ? (s) {
                    if (s.isNotEmpty) onChanged(s.first);
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

/// Limita o texto a [maxLength] unidades UTF-16 (`String.length`), a mesma
/// conta do `size()` das Security Rules. Não corta um emoji ao meio.
class Utf16LengthLimitingFormatter extends TextInputFormatter {
  const Utf16LengthLimitingFormatter(this.maxLength);

  final int maxLength;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.length <= maxLength) return newValue;
    var cut = maxLength;
    final last = text.codeUnitAt(cut - 1);
    if (last >= 0xD800 && last <= 0xDBFF) cut--; // high surrogate sem par
    final truncated = text.substring(0, cut);
    return TextEditingValue(
      text: truncated,
      selection: TextSelection.collapsed(offset: truncated.length),
    );
  }
}
