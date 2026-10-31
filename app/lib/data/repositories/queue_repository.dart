import '../../domain/models/queue_report.dart';
import '../../domain/models/place.dart';
export '../../domain/models/queue_report.dart';

class QueueReceipt {
  const QueueReceipt({
    required this.id,
    required this.minutes,
    required this.createdAt,
    required this.placeCreated,
    this.recovered = false,
  });
  final String id;
  final int minutes;
  final DateTime createdAt;
  final bool placeCreated, recovered;
}

class QueueRecoveryRequired implements Exception {
  const QueueRecoveryRequired(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract class QueueRepository {
  Future<DateTime?> queueReportLockOf(String uid, String placeId);
  Future<QueueReceipt?> reconcilePending(String uid, String placeId);
  Future<QueueReceipt> createReport(NewQueueReport report, {Place? newPlace});
  Future<List<QueueReport>> fetchForPlace(
    String placeId, {
    required DateTime since,
  });
}
