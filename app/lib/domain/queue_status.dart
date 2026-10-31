import 'geo.dart';
import 'models/queue_report.dart';

const queueCooldown = Duration(minutes: 30);
const queueLiveWindow = Duration(minutes: 60);
const queueHistoryWindow = Duration(days: 28);

class QueueSummary {
  const QueueSummary(
    this.median,
    this.count,
    this.latest, {
    this.p25,
    this.p75,
  });
  final double median;
  final int count;
  final DateTime latest;
  final double? p25;
  final double? p75;
}

double _percentile(List<int> values, double p) {
  final index = (values.length - 1) * p;
  final lo = index.floor(), hi = index.ceil();
  return values[lo] + (values[hi] - values[lo]) * (index - lo);
}

QueueSummary? _summary(Iterable<QueueReport> reports, {int minimum = 1}) {
  final latest = <String, QueueReport>{};
  for (final report in reports) {
    final old = latest[report.authorId];
    if (old == null ||
        report.createdAt.isAfter(old.createdAt) ||
        (report.createdAt == old.createdAt &&
            report.id.compareTo(old.id) > 0)) {
      latest[report.authorId] = report;
    }
  }
  if (latest.length < minimum) return null;
  final values = latest.values.map((r) => r.minutes).toList()..sort();
  final at = latest.values
      .map((r) => r.createdAt)
      .reduce((a, b) => a.isAfter(b) ? a : b);
  return QueueSummary(
    _percentile(values, .5),
    values.length,
    at,
    p25: _percentile(values, .25),
    p75: _percentile(values, .75),
  );
}

bool _within(QueueReport r, DateTime now, Duration window) =>
    !r.createdAt.isAfter(now) && r.createdAt.isAfter(now.subtract(window));

QueueSummary? liveQueue(Iterable<QueueReport> reports, DateTime now) =>
    _summary(reports.where((r) => _within(r, now, queueLiveWindow)));

/// Fixed UTC−3; independent of device timezone and daylight saving.
DateTime _local(DateTime t) => t.toUtc().subtract(const Duration(hours: 3));
QueueSummary? historicalQueue(Iterable<QueueReport> reports, DateTime now) {
  final local = _local(now);
  return _summary(
    reports.where((r) {
      final at = _local(r.createdAt);
      return _within(r, now, queueHistoryWindow) &&
          at.weekday == local.weekday &&
          at.hour ~/ 2 == local.hour ~/ 2;
    }),
    minimum: 3,
  );
}

/// Falha fechada: coordenadas e distância não finitas nunca liberam envio.
bool nearForQueue(LatLng device, LatLng place) {
  bool valid(LatLng p) =>
      p.lat.isFinite &&
      p.lng.isFinite &&
      p.lat >= -90 &&
      p.lat <= 90 &&
      p.lng >= -180 &&
      p.lng <= 180;
  if (!valid(device) || !valid(place)) return false;
  final distance = distanceMeters(device, place);
  return distance.isFinite && distance <= 150;
}
