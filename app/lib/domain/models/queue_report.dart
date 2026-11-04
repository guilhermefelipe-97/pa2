class QueueReport {
  const QueueReport({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.placeId,
    required this.minutes,
    required this.createdAt,
  });
  final String id, authorId, authorName, placeId;
  final int minutes;
  final DateTime createdAt;
}

class NewQueueReport {
  const NewQueueReport({
    required this.authorId,
    required this.authorName,
    required this.placeId,
    required this.minutes,
  });
  final String authorId, authorName, placeId;
  final int minutes;
}
