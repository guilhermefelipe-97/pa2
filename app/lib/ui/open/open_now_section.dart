import 'package:flutter/material.dart';

import '../../domain/models/place.dart';
import 'open_now_view_model.dart';
import 'open_status_line.dart';

/// "Está aberto agora?" (F20) no detalhe: o status dos relatos recentes e,
/// para quem está a até 150 m, Sim/Não em 1 toque. Sem relato e sem ação
/// possível, não ocupa espaço.
class OpenNowSection extends StatefulWidget {
  const OpenNowSection({
    super.key,
    required this.viewModel,
    required this.place,
  });

  final OpenNowViewModel viewModel;
  final Place place;

  @override
  State<OpenNowSection> createState() => _OpenNowSectionState();
}

class _OpenNowSectionState extends State<OpenNowSection> {
  @override
  void initState() {
    super.initState();
    widget.viewModel.attach(widget.place);
  }

  @override
  void didUpdateWidget(OpenNowSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.place, widget.place)) {
      widget.viewModel.attach(widget.place);
    }
  }

  /// Explica antes do pedido do sistema; só pede se a pessoa aceitar.
  Future<void> _askLocation() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(OpenNowViewModel.explainTitle),
        content: const Text(OpenNowViewModel.explainBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(OpenNowViewModel.notNowLabel),
          ),
          FilledButton(
            key: const Key('open-use-location'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(OpenNowViewModel.useLocationLabel),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await widget.viewModel.useMyLocation();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        final status = vm.status;
        final action = _action(context, vm);
        if (status == null && action == null) return const SizedBox.shrink();
        return Padding(
          key: const Key('open-now'),
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (status != null)
                OpenStatusLine(
                  key: const Key('open-status'),
                  status: status,
                  now: vm.now(),
                  currentUserId: vm.currentUserId,
                ),
              if (status != null && action != null) const SizedBox(height: 8),
              ?action,
            ],
          ),
        );
      },
    );
  }

  Widget? _action(BuildContext context, OpenNowViewModel vm) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    switch (vm.proximity) {
      case OpenProximity.checking:
      case OpenProximity.far:
      case OpenProximity.none:
        return null;
      case OpenProximity.unavailable:
        return Text(
          OpenNowViewModel.unavailableMessage,
          key: const Key('open-location-unavailable'),
          style: muted,
        );
      case OpenProximity.locationOff:
        return Row(
          key: const Key('open-location-off'),
          children: [
            Icon(
              Icons.location_off,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(OpenNowViewModel.locationOffMessage, style: muted),
            ),
          ],
        );
      case OpenProximity.needsPermission:
        return TextButton.icon(
          key: const Key('open-ask-location'),
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
          onPressed: _askLocation,
          icon: const Icon(Icons.storefront),
          label: const Text(OpenNowViewModel.askLocationLabel),
        );
      case OpenProximity.near:
        final blocked = vm.blockedLabel;
        final enabled = vm.canReport;
        return Column(
          key: const Key('open-report'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  OpenNowViewModel.question,
                  style: theme.textTheme.titleSmall,
                ),
                FilledButton.tonal(
                  key: const Key('open-yes'),
                  onPressed: enabled ? () => vm.submit(open: true) : null,
                  child: Semantics(
                    label: 'Sim, está aberto agora',
                    excludeSemantics: true,
                    child: const Text('Sim'),
                  ),
                ),
                OutlinedButton(
                  key: const Key('open-no'),
                  onPressed: enabled ? () => vm.submit(open: false) : null,
                  child: Semantics(
                    label: 'Não, está fechado agora',
                    excludeSemantics: true,
                    child: const Text('Não'),
                  ),
                ),
                if (vm.isSubmitting)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            if (blocked != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  blocked,
                  key: const Key('open-locked'),
                  style: muted,
                ),
              ),
            if (vm.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  vm.errorMessage!,
                  key: const Key('open-error'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
          ],
        );
    }
  }
}
