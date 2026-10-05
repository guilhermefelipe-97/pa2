import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../data/services/photo_picker.dart';
import '../../domain/models/companion.dart';
import '../../domain/models/review.dart';
import 'review_view_model.dart';

class ReviewView extends StatefulWidget {
  const ReviewView({super.key, required this.viewModel});

  final ReviewViewModel viewModel;

  @override
  State<ReviewView> createState() => _ReviewViewState();
}

class _ReviewViewState extends State<ReviewView> {
  ReviewViewModel get viewModel => widget.viewModel;

  @override
  void initState() {
    super.initState();
    // Android: foto tirada antes de o sistema encerrar o app (no-op nas
    // outras plataformas).
    viewModel.recoverLostPhoto();
  }

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
              _PhotoField(viewModel: vm),
              const SizedBox(height: 16),
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

/// Foto opcional (G1): adicionar pela câmera ou galeria; tocar na prévia
/// oferece trocar ou remover.
class _PhotoField extends StatelessWidget {
  const _PhotoField({required this.viewModel});

  final ReviewViewModel viewModel;

  static Future<PhotoSource?> _chooseSource(BuildContext context) =>
      showModalBottomSheet<PhotoSource>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const Key('photo-source-camera'),
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Tirar foto'),
                onTap: () => Navigator.pop(context, PhotoSource.camera),
              ),
              ListTile(
                key: const Key('photo-source-gallery'),
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Escolher da galeria'),
                onTap: () => Navigator.pop(context, PhotoSource.gallery),
              ),
            ],
          ),
        ),
      );

  Future<void> _add(BuildContext context) async {
    final source = await _chooseSource(context);
    if (source != null) await viewModel.pickPhoto(source);
  }

  Future<void> _edit(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('photo-change'),
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Trocar foto'),
              onTap: () => Navigator.pop(context, 'change'),
            ),
            ListTile(
              key: const Key('photo-remove'),
              leading: const Icon(Icons.delete_outline),
              title: const Text('Remover foto'),
              onTap: () => Navigator.pop(context, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (action == 'remove') viewModel.removePhoto();
    if (action == 'change') await _add(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final vm = viewModel;
    final photo = vm.photo;
    final busy = vm.photoBusy;

    Widget frame(Widget child) => ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(color: scheme.surfaceContainerHigh, child: child),
      ),
    );

    final Widget content;
    if (vm.isProcessingPhoto) {
      content = frame(
        const Center(
          key: Key('photo-processing'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 8),
              Text('Preparando a foto…'),
            ],
          ),
        ),
      );
    } else if (photo != null) {
      content = Semantics(
        button: true,
        label: 'Sua foto. Toque para trocar ou remover',
        excludeSemantics: true,
        child: InkWell(
          key: const Key('photo-preview'),
          borderRadius: BorderRadius.circular(16),
          onTap: busy ? null : () => _edit(context),
          child: frame(
            Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(photo, fit: BoxFit.cover, gaplessPlayback: true),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit, size: 14, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          'Trocar ou remover',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      content = Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          key: const Key('photo-add'),
          onPressed: busy ? null : () => _add(context),
          icon: const Icon(Icons.add_a_photo_outlined),
          label: const Text('Adicionar foto'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Foto (opcional)', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        content,
        if (vm.photoMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            vm.photoMessage!,
            key: const Key('photo-message'),
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
          ),
        ],
      ],
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
