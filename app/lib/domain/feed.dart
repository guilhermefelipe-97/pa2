import 'models/place.dart';
import 'models/review.dart';
import 'models/scores.dart';

/// Um card do feed "Amigos foram aqui": um local e as avaliações de quem o
/// usuário segue, da mais recente para a mais antiga.
class FeedItem {
  FeedItem({required this.place, required this.reviews})
    : assert(reviews.isNotEmpty);

  /// Local do card (foto, bairro, categoria). Quando o local não está na
  /// lista de `places`, é um Place mínimo com o nome desnormalizado da review.
  final Place place;

  /// Ordenadas por `createdAt` decrescente.
  final List<Review> reviews;

  String get placeId => place.id;
  String get placeName => place.name;

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

  /// Avaliação mais recente que tem comentário (ou `null`).
  Review? get latestComment {
    for (final r in reviews) {
      if (r.comment?.trim().isNotEmpty ?? false) return r;
    }
    return null;
  }

  /// Média de cada um dos 3 eixos entre as avaliações do card (3 números,
  /// nunca uma nota única).
  AxisAverages get averages => AxisAverages.of(reviews.map((r) => r.scores));
}

/// Formata a frase de quem foi ao local.
String formatVisitors(List<String> names) {
  if (names.isEmpty) return '';
  if (names.length == 1) return '${names.first} foi aqui';
  final head = names.sublist(0, names.length - 1).join(', ');
  return '$head e ${names.last} foram aqui';
}

/// Agrupa avaliações por local; os cards são ordenados pela avaliação mais
/// recente de cada local. [places] (por id) fornece foto/bairro/categoria.
/// Função pura.
List<FeedItem> groupReviewsIntoFeed(
  Iterable<Review> reviews, {
  Map<String, Place> places = const {},
}) {
  final byPlace = <String, List<Review>>{};
  for (final r in reviews) {
    byPlace.putIfAbsent(r.placeId, () => []).add(r);
  }
  final items =
      byPlace.entries.map((e) {
        final sorted = [...e.value]
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        final place =
            places[e.key] ??
            Place(
              id: e.key,
              name: sorted.first.placeName,
              category: '',
              neighborhood: '',
              city: '',
            );
        return FeedItem(place: place, reviews: sorted);
      }).toList()..sort((a, b) {
        final byDate = b.latestAt.compareTo(a.latestAt);
        return byDate != 0 ? byDate : a.placeId.compareTo(b.placeId);
      });
  return items;
}
