import 'dart:async';

import 'package:flutter/material.dart';
import '../core/bill_extras_picker.dart';
import '../../data/repositories/privacy_repository.dart';
import '../privacy/silent_field.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/place_repository.dart';
import '../../data/repositories/owner_repository.dart';
import '../../data/repositories/visit_repository.dart';
import '../../domain/models/companion.dart';
import '../../domain/models/place.dart';
import '../core/app_clock.dart';
import '../core/price_band_picker.dart';
import 'visit_view_model.dart';

const String visitActionLabel = 'Voltei aqui';

Future<bool> showVisitSheet(
  BuildContext context, {
  required Place place,
}) async {
  final vm = VisitViewModel(
    place: place,
    privacyRepository: context.read<PrivacyRepository?>(),
    ownerRepository: context.read<OwnerRepository?>(),
    authRepository: context.read(),
    userRepository: context.read(),
    visitRepository: context.read<VisitRepository>(),
    placeRepository: context.read<PlaceRepository?>(),
    clock: context.read<AppClock?>()?.now,
  );

  unawaited(vm.checkLock());
  final navigator = Navigator.of(context);
  final route = VisitSheetRoute(
    viewModel: vm,
    capturedThemes: InheritedTheme.capture(
      from: context,
      to: navigator.context,
    ),
    barrierLabel: MaterialLocalizations.of(
      context,
    ).scrimOnTapHint(MaterialLocalizations.of(context).bottomSheetLabel),
  );
  final registered = await navigator.push(route);

  route.completed.whenComplete(vm.dispose);
  return registered == true;
}

class VisitSheetRoute extends ModalBottomSheetRoute<bool> {
  VisitSheetRoute({
    required this.viewModel,
    super.capturedThemes,
    super.barrierLabel,
  }) : super(
         isScrollControlled: true,

         showDragHandle: false,
         builder: (context) => VisitSheet(viewModel: viewModel),
       ) {
    viewModel.addListener(_onChange);
  }

  final VisitViewModel viewModel;

  bool _lastCanClose = true;

  void _onChange() {
    if (viewModel.canClose == _lastCanClose) return;
    _lastCanClose = viewModel.canClose;

    if (isActive) changedInternalState();
  }

  @override
  bool get isDismissible => viewModel.canClose;

  @override
  bool get enableDrag => viewModel.canClose;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => ListenableBuilder(
    listenable: viewModel,
    builder: (context, _) =>
        super.buildPage(context, animation, secondaryAnimation),
  );

  @override
  void dispose() {
    viewModel.removeListener(_onChange);
    super.dispose();
  }
}

class VisitSheet extends StatefulWidget {
  const VisitSheet({super.key, required this.viewModel});

  final VisitViewModel viewModel;

  @override
  State<VisitSheet> createState() => _VisitSheetState();
}

class _VisitSheetState extends State<VisitSheet> {
  VisitViewModel get _vm => widget.viewModel;
  double _handleDrag = 0;

  Future<void> _confirm() async {
    final ok = await _vm.submit();
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, child) =>
          PopScope(canPop: _vm.canClose, child: child!),

      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: ListenableBuilder(
            listenable: _vm,
            builder: (context, _) {
              final vm = _vm;
              final muted = theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              );

              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragStart: vm.canClose
                          ? (_) => _handleDrag = 0
                          : null,
                      onVerticalDragUpdate: vm.canClose
                          ? (details) => _handleDrag += details.delta.dy
                          : null,
                      onVerticalDragEnd: vm.canClose
                          ? (details) {
                              if (_handleDrag > 60 ||
                                  (details.primaryVelocity ?? 0) > 700) {
                                Navigator.of(context).pop(false);
                              }
                            }
                          : null,
                      child: SizedBox(
                        key: const Key('visit-handle'),
                        height: 36,
                        width: double.infinity,
                        child: Center(
                          child: Container(
                            width: 32,
                            height: 4,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: vm.canClose ? 0.4 : 0.12),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Text(visitActionLabel, style: theme.textTheme.titleLarge),
                    Text(vm.place.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Sem notas: só conta que você voltou. O período do dia é '
                      'registrado pelo horário do envio.',
                      style: muted,
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
                            key: ValueKey('visit-companion-${c.value}'),
                            label: Text(c.label),
                            selected: vm.companion == c,
                            onSelected: vm.isSubmitting || vm.isBlocked
                                ? null
                                : (_) => vm.toggleCompanion(c),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
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
                    ),
                    PriceBandPicker(
                      value: vm.priceBand,
                      onChanged: vm.setPriceBand,
                      enabled: !vm.isSubmitting && !vm.isBlocked,
                    ),
                    const SizedBox(height: 16),
                    BillExtrasPicker(
                      couvert: vm.couvert,
                      serviceFee: vm.serviceFee,
                      onCouvert: vm.setCouvert,
                      onServiceFee: vm.setServiceFee,
                      enabled: !vm.isSubmitting && !vm.isBlocked,
                    ),
                    if (vm.blockedMessage != null) ...[
                      const SizedBox(height: 16),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          vm.blockedMessage!,
                          key: const Key('visit-blocked'),
                          style: muted,
                        ),
                      ),
                    ],
                    if (vm.errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          vm.errorMessage!,
                          key: const Key('visit-error'),
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        key: const Key('visit-confirm'),
                        onPressed: vm.canSubmit ? _confirm : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: vm.isSubmitting || vm.isCheckingLock
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Confirmar'),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
