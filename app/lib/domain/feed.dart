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

  /// Avaliação mais recente que tem foto do autor (ou `null`): a foto dela
  /// vira a capa do card, com crédito.
  Review? get latestPhoto {
    for (final r in reviews) {
      if (r.hasPhoto) return r;
    }
    return null;
  }

  /// Avaliações com foto, da mais recente para a mais antiga.
  List<Review> get photoReviews => [
    for (final r in reviews)
      if (r.hasPhoto) r,
  ];

  /// Média de cada um dos 3 eixos entre as avaliações do card (3 números,
  /// nunca uma nota única). Só no detalhe: o card mostra as notas de cada
  /// pessoa ([sources]). Calculada uma vez.
  late final AxisAverages averages = AxisAverages.of(
    reviews.map((r) => r.scores),
  );

  /// Quem foi (F06): uma fonte por autor distinto, com a avaliação mais
  /// recente dele aqui (por `createdAt`, qualquer que seja a ordem de
  /// [reviews]) e quantas vezes avaliou o local; da fonte mais recente para
  /// a mais antiga (empate: por id do autor). Calculada uma vez.
  late final List<TrustSource> sources = _sourcesOf(reviews);

  static List<TrustSource> _sourcesOf(List<Review> reviews) {
    final latest = <String, Review>{};
    final visits = <String, int>{};
    for (final r in reviews) {
      final current = latest[r.authorId];
      if (current == null || r.createdAt.isAfter(current.createdAt)) {
        latest[r.authorId] = r;
      }
      visits[r.authorId] = (visits[r.authorId] ?? 0) + 1;
    }
    return [
      for (final e in latest.entries)
        TrustSource(latest: e.value, visits: visits[e.key]!),
    ]..sort((a, b) {
      final byDate = b.latest.createdAt.compareTo(a.latest.createdAt);
      return byDate != 0 ? byDate : a.authorId.compareTo(b.authorId);
    });
  }
}

/// Uma pessoa que foi ao local: a avaliação mais recente dela ali (dona dos
/// eixos mostrados) e quantas avaliações deixou no local.
class TrustSource {
  const TrustSource({required this.latest, required this.visits})
    : assert(visits >= 1);

  final Review latest;
  final int visits;

  String get authorId => latest.authorId;
  String get authorName => latest.authorName;
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
              inCatalog: false,
            );
        return FeedItem(place: place, reviews: sorted);
      }).toList()..sort((a, b) {
        final byDate = b.latestAt.compareTo(a.latestAt);
        return byDate != 0 ? byDate : a.placeId.compareTo(b.placeId);
      });
  return items;
}
