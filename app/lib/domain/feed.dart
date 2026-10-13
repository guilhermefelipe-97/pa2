import 'models/place.dart';
import 'models/place_activity.dart';
import 'models/scores.dart';

/// Um card do feed "Amigos foram aqui": um local e as idas de quem o
/// usuário segue — avaliações e visitas sem nota ("Voltei aqui", F15) —, da
/// mais recente para a mais antiga.
class FeedItem {
  /// [activities] em qualquer ordem (ao menos uma ida: avaliação ou visita).
  FeedItem({required this.place, required Iterable<PlaceActivity> activities})
    : activities = List.unmodifiable(
        [...activities]..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      ),
      assert(activities.isNotEmpty);

  /// Local do card (foto, bairro, categoria). Quando o local não está na
  /// lista de `places`, é um Place mínimo com o nome desnormalizado da ida.
  final Place place;

  /// Avaliações e visitas, da mais recente para a mais antiga.
  final List<PlaceActivity> activities;

  /// Só as avaliações, mais recentes primeiro. Vazia quando só houve visitas.
  late final List<Review> reviews = activities.whereType<Review>().toList();

  /// Só as visitas sem nota (F15), mais recentes primeiro.
  late final List<Visit> visits = activities.whereType<Visit>().toList();

  String get placeId => place.id;
  String get placeName => place.name;

  DateTime get latestAt => activities.first.createdAt;

  /// Total de idas (avaliações + visitas) de quem aparece aqui.
  int get trips => activities.length;

  /// Nomes distintos dos autores, do mais recente para o mais antigo.
  List<String> get authorNames {
    final seen = <String>{};
    final names = <String>[];
    for (final a in activities) {
      if (seen.add(a.authorId)) names.add(a.authorName);
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
  /// pessoa ([sources]). Visitas não têm nota e não entram: só com visitas
  /// é `null`. Calculada uma vez.
  late final AxisAverages? averages = reviews.isEmpty
      ? null
      : AxisAverages.of(reviews.map((r) => r.scores));

  /// Quem foi (F06/F15): uma fonte por autor distinto, com a ida mais
  /// recente dele aqui (avaliação ou visita), a avaliação mais recente (dona
  /// dos eixos, se houver) e quantas vezes foi ao local (avaliações +
  /// visitas); da fonte mais recente para a mais antiga (empate: por id do
  /// autor). Calculada uma vez.
  late final List<TrustSource> sources = _sourcesOf(activities);

  /// Selo de recorrência (F15): quem mais voltou aqui, com 2 idas ou mais
  /// (empate: a ida mais recente); `null` quando ninguém voltou.
  TrustSource? get recurrent {
    TrustSource? best;
    for (final s in sources) {
      if (s.trips < 2) continue;
      if (best == null || s.trips > best.trips) best = s;
    }
    return best;
  }

  /// [activities] já vem da mais recente para a mais antiga: a primeira ida
  /// de cada autor é a mais recente dele.
  static List<TrustSource> _sourcesOf(List<PlaceActivity> activities) {
    final latest = <String, PlaceActivity>{};
    final latestReview = <String, Review>{};
    final count = <String, int>{};
    for (final a in activities) {
      latest.putIfAbsent(a.authorId, () => a);
      if (a is Review) latestReview.putIfAbsent(a.authorId, () => a);
      count[a.authorId] = (count[a.authorId] ?? 0) + 1;
    }
    return [
      for (final e in latest.entries)
        TrustSource(
          latest: e.value,
          latestReview: latestReview[e.key],
          trips: count[e.key]!,
        ),
    ]..sort((a, b) {
      final byDate = b.latest.createdAt.compareTo(a.latest.createdAt);
      return byDate != 0 ? byDate : a.authorId.compareTo(b.authorId);
    });
  }
}

/// Uma pessoa que foi ao local: a ida mais recente dela ali ([latest],
/// avaliação ou visita), a avaliação mais recente ([latestReview], dona dos
/// eixos mostrados; `null` quando ela só registrou visitas) e quantas vezes
/// foi ao local ([trips] = avaliações + visitas).
class TrustSource {
  TrustSource({required this.latest, Review? latestReview, required this.trips})
    : latestReview = latestReview ?? (latest is Review ? latest : null),
      assert(trips >= 1);

  final PlaceActivity latest;
  final Review? latestReview;
  final int trips;

  String get authorId => latest.authorId;
  String get authorName => latest.authorName;

  /// Só registrou visitas aqui: a linha não tem eixos.
  bool get onlyVisits => latestReview == null;

  /// A ida mais recente é uma visita depois de uma avaliação: os eixos são
  /// de uma ida anterior (a linha marca "avaliou há…").
  bool get reviewIsOlder => latestReview != null && latest is Visit;
}

/// "Ana voltou 3 vezes" (F15); [trips] = idas da pessoa ao local. Sem o
/// emoji: o selo acrescenta o ícone 🔁 decorativo.
String recurrenceLabel(String name, int trips) => '$name voltou $trips vezes';

/// "5 idas de 3 amigos" (detalhe, F15; o selo acrescenta o 🔁). [friends]
/// não conta o próprio usuário; [ownTrips] são as idas dele. `null` quando
/// ninguém voltou (nenhuma pessoa com 2 idas ou mais).
String? placeRecurrenceLabel({
  required int trips,
  required int friends,
  required int ownTrips,
  required bool anyoneReturned,
}) {
  if (!anyoneReturned || trips < 2) return null;
  final idas = '$trips idas';
  final friendsPart = friends == 1 ? '1 amigo' : '$friends amigos';
  if (ownTrips == 0) return '$idas de $friendsPart';
  if (friends == 0) return '$idas suas';
  return '$idas suas e de $friendsPart';
}

/// Formata a frase de quem foi ao local.
String formatVisitors(List<String> names) {
  if (names.isEmpty) return '';
  if (names.length == 1) return '${names.first} foi aqui';
  final head = names.sublist(0, names.length - 1).join(', ');
  return '$head e ${names.last} foram aqui';
}

/// Agrupa idas (avaliações e visitas, F15) por local; os cards são
/// ordenados pela ida mais recente de cada local. [places] (por id) fornece
/// foto/bairro/categoria. Função pura.
List<FeedItem> groupActivitiesIntoFeed(
  Iterable<PlaceActivity> activities, {
  Map<String, Place> places = const {},
}) {
  final byPlace = <String, List<PlaceActivity>>{};
  for (final a in activities) {
    byPlace.putIfAbsent(a.placeId, () => []).add(a);
  }
  final items =
      byPlace.entries.map((e) {
        final place =
            places[e.key] ??
            Place(
              id: e.key,
              name: _newest(e.value).placeName,
              category: '',
              neighborhood: '',
              city: '',
              inCatalog: false,
            );
        return FeedItem(place: place, activities: e.value);
      }).toList()..sort((a, b) {
        final byDate = b.latestAt.compareTo(a.latestAt);
        return byDate != 0 ? byDate : a.placeId.compareTo(b.placeId);
      });
  return items;
}

/// Nome do local para o fallback: o da avaliação mais recente (como antes
/// do F15) ou, sem avaliação, o da visita mais recente.
PlaceActivity _newest(List<PlaceActivity> list) {
  PlaceActivity? best;
  for (final a in list) {
    final better =
        best == null ||
        (a is Review && best is! Review) ||
        ((a is Review) == (best is Review) &&
            a.createdAt.isAfter(best.createdAt));
    if (better) best = a;
  }
  return best!;
}
