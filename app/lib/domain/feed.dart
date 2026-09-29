import 'models/review.dart';

/// Um card do feed "Amigos foram aqui": um local e as avaliações de quem o
/// usuário segue, da mais recente para a mais antiga.
class FeedItem {
  FeedItem({required this.placeId, required this.placeName, required this.reviews})
      : assert(reviews.isNotEmpty);

  final String placeId;
  final String placeName;

  /// Ordenadas por `createdAt` decrescente.
  final List<Review> reviews;

  DateTime get latestAt => reviews.first.createdAt;

  /// Nomes distintos dos autores, do mais recente para o mais antigo.
  List<String> get authorNames {
    final seen = <String>{};
    final names = <String>[];
    for (final r in reviews) {
      if (seen.add(r.authorId)) names.add(r.authorName);
    }
    return names;
  }

  /// "A foi aqui", "A e B foram aqui", "A, B e C foram aqui".
  String get headline => formatVisitors(authorNames);
}

/// Formata a frase de quem foi ao local.
String formatVisitors(List<String> names) {
  if (names.isEmpty) return '';
  if (names.length == 1) return '${names.first} foi aqui';
  final head = names.sublist(0, names.length - 1).join(', ');
  return '$head e ${names.last} foram aqui';
}

/// Agrupa avaliações por local; os cards são ordenados pela avaliação mais
/// recente de cada local. Função pura.
List<FeedItem> groupReviewsIntoFeed(Iterable<Review> reviews) {
  final byPlace = <String, List<Review>>{};
  for (final r in reviews) {
    byPlace.putIfAbsent(r.placeId, () => []).add(r);
  }
  final items = byPlace.entries.map((e) {
    final sorted = [...e.value]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return FeedItem(
      placeId: e.key,
      placeName: sorted.first.placeName,
      reviews: sorted,
    );
  }).toList()
    ..sort((a, b) {
      final byDate = b.latestAt.compareTo(a.latestAt);
      return byDate != 0 ? byDate : a.placeId.compareTo(b.placeId);
    });
  return items;
}
