import '../feed/widgets/place_photo.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../dietary/food_filter_options.dart';
import '../core/bill_extras_picker.dart';
import '../privacy/silent_field.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../data/services/photo_picker.dart';
import '../../domain/models/companion.dart';
import '../../domain/models/review.dart';
import '../../domain/food_tags.dart';
import '../core/price_band_picker.dart';
import '../feed/widgets/axis_scores.dart' show noScoresLabel;
import '../visit/visit_sheet.dart';
import '../visit/visit_view_model.dart';
import 'review_view_model.dart';

const String noAxisHint = 'Toque numa estrela de pelo menos um eixo';

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

    viewModel.checkLock();

    viewModel.recoverLostPhoto();
  }

  Future<void> _submit(BuildContext context) async {
    final ok = await viewModel.submit();
    if (ok && context.mounted) context.pop(true);
  }

  Future<void> _registerVisit(BuildContext context) async {
    final registered = await showVisitSheet(context, place: viewModel.place);
    if (!registered || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(VisitViewModel.successMessage)),
    );
    context.pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Nova experiência')),
      bottomNavigationBar: ListenableBuilder(
        listenable: viewModel,
        builder: (context, _) {
          final vm = viewModel;
          if (vm.isCheckingLock || vm.isBlocked) return const SizedBox.shrink();
          final values = [
            vm.food,
            vm.ambience,
            vm.service,
          ].whereType<int>().toList();
          final average = values.isEmpty
              ? '—'
              : (values.reduce((a, b) => a + b) / values.length)
                    .toStringAsFixed(1)
                    .replaceAll('.', ',');
          final score = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('MÉDIA GERAL', style: theme.textTheme.labelSmall),
              Text(
                '$average / 5',
                key: const Key('review-overall'),
                style: theme.textTheme.titleLarge,
              ),
            ],
          );
          final button = FilledButton.icon(
            key: const Key('review-submit'),
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.tertiaryContainer,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: vm.canSubmit ? () => _submit(context) : null,
            icon: vm.isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_outlined, size: 18),
            label: Text(vm.isSubmitting ? 'Publicando…' : 'Publicar avaliação'),
          );
          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: MediaQuery.textScalerOf(context).scale(1) > 1.3
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        score,
                        const SizedBox(height: 8),
                        SizedBox(width: double.infinity, child: button),
                      ],
                    )
                  : Row(
                      children: [
                        score,
                        const SizedBox(width: 16),
                        Expanded(child: button),
                      ],
                    ),
            ),
          );
        },
      ),
      body: ListenableBuilder(
        listenable: viewModel,
        builder: (context, _) {
          final vm = viewModel;
          if (vm.isCheckingLock) {
            return const Center(
              key: Key('review-lock-checking'),
              child: CircularProgressIndicator(),
            );
          }
          if (vm.isOwnBusiness) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(vm.blockedMessage!),
              ),
            );
          }
          if (vm.isBlocked) {
            return _BlockedReview(
              message: vm.blockedMessage!,
              onRegisterVisit: () => _registerVisit(context),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: theme.colorScheme.surfaceContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 56,
                          height: 56,
                          child: PlacePhoto(place: vm.place, iconSize: 24),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'AVALIANDO VISITA',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.secondary,
                              ),
                            ),
                            Text(
                              vm.place.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium,
                            ),
                            Text(
                              [
                                vm.place.neighborhood,
                                vm.place.city,
                                vm.place.category,
                              ].where((v) => v.trim().isNotEmpty).join(' • '),
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Text(
                'Como foi sua experiência?',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Atribua notas aos eixos vividos. Se algum aspecto não se aplicou à sua visita, você pode deixá-lo sem nota.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              _AxisPicker(
                axisKey: 'food',
                emoji: '🍽️',
                label: 'Comida',
                title: 'Comida & Bebida',
                description: 'Qualidade dos pratos, bebidas e ingredientes.',
                value: vm.food,
                onChanged: vm.setFood,
                onClear: vm.clearFood,
                enabled: !vm.isSubmitting,
              ),
              _AxisPicker(
                axisKey: 'ambience',
                emoji: '✨',
                label: 'Ambiente',
                title: 'Ambiente & Atmosfera',
                description:
                    'Conforto acústico, temperatura, iluminação e estética.',
                value: vm.ambience,
                onChanged: vm.setAmbience,
                onClear: vm.clearAmbience,
                enabled: !vm.isSubmitting,
              ),
              _AxisPicker(
                axisKey: 'service',
                emoji: '🤝',
                label: 'Atendimento',
                title: 'Atendimento',
                description: 'Cordialidade, agilidade e atenção da equipe.',
                value: vm.service,
                onChanged: vm.setService,
                onClear: vm.clearService,
                enabled: !vm.isSubmitting,
              ),
              Semantics(
                liveRegion: true,
                child: vm.hasValidAxes
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          noAxisHint,
                          key: const Key('review-axis-hint'),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
              ),
              Text('Comentário autêntico', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(
                key: const Key('review-comment'),
                enabled: !vm.isSubmitting,
                onChanged: vm.setComment,
                minLines: 4,
                maxLines: 6,
                maxLength: Review.maxCommentLength,
                inputFormatters: const [
                  Utf16LengthLimitingFormatter(Review.maxCommentLength),
                ],
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText:
                      'Conte os destaques, o que pedir ou dicas para quem vai visitar...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _PhotoField(viewModel: vm),
              const SizedBox(height: 24),
              Text(
                'Com quem você foi? (opcional)',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
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
              Text(
                'Destaques rápidos (opcional)',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              for (final group in [
                (
                  title: null,
                  tags: [
                    for (final t in foodTags)
                      if (!homeFoodTags.contains(t)) t,
                  ],
                ),
                (title: 'Comida caseira', tags: homeFoodTags),
              ]) ...[
                if (group.title != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Text(
                      group.title!,
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final tag in group.tags)
                      FilterChip(
                        key: Key('review-tag-$tag'),
                        label: Text(
                          foodTagLabel(tag),
                          style: TextStyle(
                            color: vm.tags.contains(tag)
                                ? theme.colorScheme.onPrimary
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                        selected: vm.tags.contains(tag),
                        onSelected: vm.isSubmitting
                            ? null
                            : (_) => vm.toggleTag(tag),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              PriceBandPicker(
                value: vm.priceBand,
                onChanged: vm.setPriceBand,
                enabled: !vm.isSubmitting,
              ),
              const SizedBox(height: 24),
              BillExtrasPicker(
                couvert: vm.couvert,
                serviceFee: vm.serviceFee,
                onCouvert: vm.setCouvert,
                onServiceFee: vm.setServiceFee,
                enabled: !vm.isSubmitting,
              ),
              const SizedBox(height: 24),
              if (vm.privacyUnavailable)
                TextButton(
                  onPressed: vm.isSubmitting ? null : vm.checkLock,
                  child: const Text(
                    'Preferência indisponível. Tentar novamente',
                  ),
                ),
              SilentField(
                value: vm.silent,
                onChanged: vm.isSubmitting ? null : vm.setSilent,
                expandedDescription: true,
              ),
              const SizedBox(height: 12),
              Text(
                'O período do dia é registrado automaticamente pelo horário do envio.',
                style: theme.textTheme.bodySmall,
              ),
              if (vm.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    vm.errorMessage!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _BlockedReview extends StatelessWidget {
  const _BlockedReview({required this.message, required this.onRegisterVisit});

  final String message;
  final VoidCallback onRegisterVisit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(
          Icons.event_repeat,
          size: 48,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 16),
        Text(
          message,
          key: const Key('review-blocked'),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Assim cada avaliação conta uma experiência de verdade.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Voltou aqui? Registre a visita: ela conta para quem segue você.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Center(
          child: FilledButton.icon(
            key: const Key('review-register-visit'),
            onPressed: onRegisterVisit,
            icon: const Icon(Icons.replay),
            label: const Text('Registrar visita'),
          ),
        ),
      ],
    );
  }
}

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
        child: SizedBox(
          width: 112,
          height: 96 * MediaQuery.textScalerOf(context).scale(1),
          child: OutlinedButton(
            key: const Key('photo-add'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.all(8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              side: BorderSide(color: scheme.outlineVariant),
              backgroundColor: scheme.surfaceContainer,
            ),
            onPressed: busy ? null : () => _add(context),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_a_photo_outlined),
                SizedBox(height: 8),
                Text(
                  'Adicionar',
                  semanticsLabel: 'Adicionar foto',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Foto da sua visita (opcional)',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Mostre o pedido, comanda, ambiente ou aquele detalhe especial.',
          style: theme.textTheme.bodySmall,
        ),
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
    required this.axisKey,
    required this.emoji,
    required this.label,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
    required this.onClear,
    this.enabled = true,
  });

  final String axisKey;
  final String emoji;
  final String label;
  final String title;
  final String description;
  final int? value;
  final ValueChanged<int> onChanged;
  final VoidCallback onClear;
  final bool enabled;

  static const double maxStarSize = 44;
  static const double starPadding = 4;

  static const double disabledOpacity = 0.38;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final current = value;

    final filled = scheme.secondary;
    final opacity = enabled ? 1.0 : disabledOpacity;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 16,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 72,
                    child: Text(
                      current == null ? 'Sem nota' : '$current de 5',
                      semanticsLabel: current == null
                          ? noScoresLabel
                          : '$current de 5',
                      textAlign: TextAlign.end,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),

                  Visibility(
                    visible: current != null,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: IconButton(
                      key: Key('axis-$axisKey-clear'),
                      tooltip: 'Limpar $label',
                      onPressed: enabled && current != null ? onClear : null,
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final iconSize = math.max(
                  0.0,
                  math.min(
                    maxStarSize,
                    constraints.maxWidth / 5 - 4 * starPadding,
                  ),
                );
                return Row(
                  children: [
                    for (var i = 1; i <= 5; i++)
                      Expanded(
                        child: Semantics(
                          button: true,
                          enabled: enabled,
                          selected: current == i,
                          label: '$label $i de 5',
                          onTap: enabled ? () => onChanged(i) : null,
                          excludeSemantics: true,
                          child: Center(
                            child: IconButton(
                              key: Key('axis-$axisKey-$i'),
                              iconSize: iconSize,
                              padding: const EdgeInsets.all(starPadding),
                              constraints: const BoxConstraints(),
                              onPressed: enabled ? () => onChanged(i) : null,
                              icon: Opacity(
                                opacity: opacity,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: current != null && i <= current
                                        ? filled
                                        : scheme.surfaceContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Icon(
                                      current != null && i <= current
                                          ? Icons.star_rounded
                                          : Icons.star_outline_rounded,
                                      color: current != null && i <= current
                                          ? Colors.white
                                          : scheme.outline,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

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
    if (last >= 0xD800 && last <= 0xDBFF) cut--;
    final truncated = text.substring(0, cut);
    return TextEditingValue(
      text: truncated,
      selection: TextSelection.collapsed(offset: truncated.length),
    );
  }
}
