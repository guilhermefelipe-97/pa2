import 'package:flutter/material.dart' hide DayPeriod;
import 'package:provider/provider.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/owner_repository.dart';
import '../../data/repositories/place_history_repository.dart';
import '../../domain/models/day_period.dart';
import '../../domain/models/review.dart';
import '../../domain/models/scores.dart';
import '../../domain/models/visit.dart';
import '../../domain/owner_timeline.dart';
import '../core/app_clock.dart';

/// Painel do titular com a série temporal dos 3 eixos (F23).
class OwnerTimelineView extends StatelessWidget {
  const OwnerTimelineView({super.key, required this.placeId, this.placeName});
  final String placeId;
  final String? placeName;

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthRepository>().currentUserId;
    return Scaffold(
      appBar: AppBar(title: Text(placeName ?? 'Painel do local')),
      body: uid == null
          ? const SizedBox.shrink()
          : _Timeline(
              key: ValueKey('$uid-$placeId'),
              uid: uid,
              placeId: placeId,
            ),
    );
  }
}

typedef _History = ({List<Review> reviews, List<Visit> visits, DateTime at});

class _Timeline extends StatefulWidget {
  const _Timeline({super.key, required this.uid, required this.placeId});
  final String uid, placeId;
  @override
  State<_Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<_Timeline> {
  static const deniedText =
      'O painel é exclusivo do titular atual deste estabelecimento.';
  Future<_History>? read;
  DayPeriod? period;

  @override
  void initState() {
    super.initState();
    read = load();
  }

  Future<_History> load() async {
    final owners = context.read<OwnerRepository>();
    final history = context.read<PlaceHistoryRepository?>();
    final at = context.read<AppClock?>()?.now() ?? DateTime.now();
    final owner = await owners
        .ownerOf(widget.placeId)
        .timeout(ownerLookupTimeout);
    if (owner != widget.uid) throw const _NotOwner();
    if (history == null) throw StateError('histórico indisponível');
    final since = OwnerTimeline.windowStart(at);
    final (reviews, visits) = await (
      history.reviewsSince(widget.placeId, since),
      history.visitsSince(widget.placeId, since),
    ).wait;
    return (reviews: reviews, visits: visits, at: at);
  }

  void retry() => setState(() => read = load());

  @override
  Widget build(BuildContext context) => FutureBuilder<_History>(
    future: read,
    builder: (context, snap) {
      if (snap.error is _NotOwner) {
        return const Center(
          child: Padding(padding: EdgeInsets.all(24), child: Text(deniedText)),
        );
      }
      if (snap.hasError) {
        return Center(
          child: TextButton(
            onPressed: retry,
            child: const Text(
              'Não foi possível carregar o painel. Tentar novamente',
            ),
          ),
        );
      }
      if (!snap.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final h = snap.data!;
      final months = OwnerTimeline.build(
        reviews: h.reviews,
        visits: h.visits,
        now: h.at,
        period: period,
      );
      return RefreshIndicator(
        onRefresh: () async {
          retry();
          await read;
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Text(
              'Médias mensais dos últimos 12 meses, separadas por eixo. '
              'Inclui todas as avaliações e "Voltei aqui" do local.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            _PeriodFilter(
              value: period,
              onChanged: (p) => setState(() => period = p),
            ),
            const SizedBox(height: 16),
            if (months.every((m) => m.reviews == 0 && m.visits == 0))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  period == null
                      ? 'Ainda não há avaliações nos últimos 12 meses.'
                      : 'Nenhuma avaliação no período ${period!.label} nos últimos 12 meses.',
                  textAlign: TextAlign.center,
                ),
              )
            else ...[
              const _Legend(),
              const SizedBox(height: 8),
              _AxesChart(months: months),
              const SizedBox(height: 20),
              Text('Mês a mês', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final m in months.reversed) _MonthRow(month: m),
            ],
          ],
        ),
      );
    },
  );
}

class _NotOwner implements Exception {
  const _NotOwner();
}

class _PeriodFilter extends StatelessWidget {
  const _PeriodFilter({required this.value, required this.onChanged});
  final DayPeriod? value;
  final ValueChanged<DayPeriod?> onChanged;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      ChoiceChip(
        label: const Text('Todos'),
        selected: value == null,
        onSelected: (_) => onChanged(null),
      ),
      for (final p in DayPeriod.values)
        ChoiceChip(
          label: Text(p.label),
          selected: value == p,
          onSelected: (_) => onChanged(p),
        ),
    ],
  );
}

({String label, Color color}) _axisStyle(ColorScheme scheme, int axis) =>
    switch (axis) {
      0 => (label: 'Comida', color: scheme.primary),
      1 => (label: 'Ambiente', color: scheme.tertiary),
      _ => (label: 'Atendimento', color: scheme.error),
    };

AxisAverage _axis(TimelineMonth m, int axis) => switch (axis) {
  0 => m.food,
  1 => m.ambience,
  _ => m.service,
};

class _Legend extends StatelessWidget {
  const _Legend();
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 16,
      children: [
        for (var i = 0; i < 3; i++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: _axisStyle(scheme, i).color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(_axisStyle(scheme, i).label),
            ],
          ),
      ],
    );
  }
}

class _AxesChart extends StatelessWidget {
  const _AxesChart({required this.months});
  final List<TimelineMonth> months;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label:
          'Gráfico das médias mensais de comida, ambiente e atendimento. Os valores estão na lista mês a mês.',
      excludeSemantics: true,
      child: SizedBox(
        height: 200,
        width: double.infinity,
        child: CustomPaint(
          painter: _ChartPainter(
            months: months,
            scheme: theme.colorScheme,
            labelStyle: theme.textTheme.labelSmall!,
          ),
        ),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.months,
    required this.scheme,
    required this.labelStyle,
  });
  final List<TimelineMonth> months;
  final ColorScheme scheme;
  final TextStyle labelStyle;

  static const left = 24.0, bottom = 22.0, top = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width - left;
    final h = size.height - bottom - top;
    double x(int i) =>
        left + (months.length == 1 ? w / 2 : w * i / (months.length - 1));
    double y(double v) => top + h * (5 - v) / 4;

    final grid = Paint()
      ..color = scheme.outlineVariant
      ..strokeWidth = 1;
    for (var v = 1; v <= 5; v++) {
      canvas.drawLine(
        Offset(left, y(v.toDouble())),
        Offset(size.width, y(v.toDouble())),
        grid,
      );
      _text(canvas, '$v', Offset(4, y(v.toDouble()) - 7));
    }
    for (var i = 0; i < months.length; i += 2) {
      _text(
        canvas,
        months[i].label,
        Offset(x(i) - 14, size.height - bottom + 6),
      );
    }

    for (var axis = 0; axis < 3; axis++) {
      final color = _axisStyle(scheme, axis).color;
      final line = Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      Offset? previous;
      for (var i = 0; i < months.length; i++) {
        final value = _axis(months[i], axis).value;
        if (value == null) {
          previous = null;
          continue;
        }
        final point = Offset(x(i), y(value));
        if (previous != null) canvas.drawLine(previous, point, line);
        final small = months[i].smallSample;
        canvas.drawCircle(
          point,
          3.5,
          Paint()
            ..color = color
            ..style = small ? PaintingStyle.stroke : PaintingStyle.fill
            ..strokeWidth = 1.5,
        );
        previous = point;
      }
    }
  }

  void _text(Canvas canvas, String text, Offset at) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.months != months || old.scheme != scheme;
}

class _MonthRow extends StatelessWidget {
  const _MonthRow({required this.month});
  final TimelineMonth month;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    String axisText(int i) {
      final a = _axis(month, i);
      return '${_axisStyle(scheme, i).label} ${a.value == null ? '—' : formatAverage(a.value!)}';
    }

    final counts = [
      reviewCountLabel(month.reviews),
      countLabel(month.visits, '"Voltei aqui"', '"Voltei aqui"'),
    ].join(' · ');
    return Padding(
      key: ValueKey('timeline-${month.year}-${month.month}'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(month.label, style: theme.textTheme.titleSmall),
              ),
              Text(counts, style: theme.textTheme.bodySmall),
            ],
          ),
          if (month.reviews > 0) ...[
            const SizedBox(height: 2),
            Text([for (var i = 0; i < 3; i++) axisText(i)].join(' · ')),
            if (month.smallSample)
              Text(
                'Amostra pequena: menos de ${OwnerTimeline.smallSampleBelow} avaliações.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
