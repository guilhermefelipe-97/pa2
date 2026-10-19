import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/open_report_repository.dart';
import '../../data/services/location_service.dart';
import '../../domain/decision.dart';
import '../../domain/models/companion.dart';
import '../../routing/routes.dart';
import '../core/app_clock.dart';
import '../feed/widgets/feed_card.dart' show placeSubtitle;
import 'decision_view_model.dart';

/// Rótulo do botão do modo decisão (F09) na aba "Quero ir".
const decideLabel = 'Decidir por mim';

/// Toque 1 do modo decisão: abre a escolha de companhia sobre os
/// [candidates] (salvos do chip ativo). O toque 2 (companhia) mostra 1
/// lugar.
Future<void> showDecisionSheet(
  BuildContext context, {
  required List<DecisionCandidate> candidates,
}) {
  final vm = DecisionViewModel(
    candidates: candidates,
    authRepository: context.read(),
    userRepository: context.read(),
    reviewRepository: context.read(),
    openReportRepository: context.read<OpenReportRepository?>(),
    locationService: context.read<LocationService?>(),
    clock: context.read<AppClock?>()?.now,
  );
  final router = GoRouter.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) => DecisionSheet(
      viewModel: vm,
      onOpenPlace: (option) {
        Navigator.of(sheetContext).pop();
        router.push(Routes.placeDetail(option.place.id), extra: option.place);
      },
    ),
  ).whenComplete(vm.dispose);
}

/// Conteúdo do sheet do modo decisão.
class DecisionSheet extends StatefulWidget {
  const DecisionSheet({
    super.key,
    required this.viewModel,
    required this.onOpenPlace,
  });

  final DecisionViewModel viewModel;
  final void Function(DecisionOption option) onOpenPlace;

  @override
  State<DecisionSheet> createState() => _DecisionSheetState();
}

class _DecisionSheetState extends State<DecisionSheet> {
  @override
  void initState() {
    super.initState();
    // Os sinais chegam enquanto a pessoa escolhe a companhia.
    widget.viewModel.prepare();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 150),
          alignment: Alignment.topCenter,
          child: switch (widget.viewModel.phase) {
            DecisionPhase.choosing => _CompanionChoice(
              onChoose: widget.viewModel.choose,
            ),
            DecisionPhase.loading => const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
            DecisionPhase.noneOpen => _NoneOpen(onBack: widget.viewModel.back),
            DecisionPhase.result => _Result(
              viewModel: widget.viewModel,
              onOpenPlace: widget.onOpenPlace,
            ),
          },
        ),
      ),
    );
  }
}

class _CompanionChoice extends StatelessWidget {
  const _CompanionChoice({required this.onChoose});

  final Future<void> Function(Companion? companion) onChoose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const Key('decide-companions'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text('Com quem você vai?', style: theme.textTheme.titleLarge),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in Companion.values)
              FilledButton.tonal(
                key: Key('decide-${c.value}'),
                onPressed: () => onChoose(c),
                child: Text(c.label),
              ),
            OutlinedButton(
              key: const Key('decide-any'),
              onPressed: () => onChoose(null),
              child: const Text('Tanto faz'),
            ),
          ],
        ),
      ],
    );
  }
}

class _NoneOpen extends StatelessWidget {
  const _NoneOpen({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.door_front_door_outlined,
          size: 40,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 12),
        Text(
          DecisionViewModel.noneOpenText,
          key: const Key('decide-none-open'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        TextButton(onPressed: onBack, child: const Text('Voltar')),
      ],
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.viewModel, required this.onOpenPlace});

  final DecisionViewModel viewModel;
  final void Function(DecisionOption option) onOpenPlace;

  @override
  Widget build(BuildContext context) {
    final option = viewModel.current!;
    final place = option.place;
    final theme = Theme.of(context);
    final subtitle = placeSubtitle(place.neighborhood, place.category);
    return Column(
      key: const Key('decide-result'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (viewModel.wrapped)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              DecisionViewModel.wrappedText,
              key: const Key('decide-wrapped'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        Text('Que tal', style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        // Anúncio para leitores de tela a cada novo lugar.
        Semantics(
          liveRegion: true,
          child: Text(
            place.name,
            key: const Key('decide-place'),
            style: theme.textTheme.headlineSmall,
          ),
        ),
        if (subtitle.isNotEmpty)
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.tertiary,
            ),
          ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lightbulb_outline, size: 20, color: theme.hintColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                viewModel.reason ?? '',
                key: const Key('decide-reason'),
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('decide-next'),
                onPressed: viewModel.next,
                child: const Text('Outra opção'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                key: const Key('decide-open'),
                onPressed: () => onOpenPlace(option),
                child: const Text('Ver local'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
