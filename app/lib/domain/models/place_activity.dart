import '../price_band.dart';
import 'companion.dart';
import 'day_period.dart';
import 'scores.dart';

part 'place_activity_review.dart';
part 'place_activity_visit.dart';

/// Uma ida de alguém a um local (F15): uma avaliação ([Review]) ou uma visita
/// sem notas ([Visit]). Fechada (`sealed`): um `switch` sobre as idas é
/// exaustivo, sem caso genérico. A recorrência conta as duas.
sealed class PlaceActivity {
  const PlaceActivity();

  String get id;
  String get authorId;
  String get authorName;
  String get placeId;
  String get placeName;
  Companion? get companion;

  /// Quanto a pessoa gastou por pessoa nesta ida (F27); `null` = não
  /// informou (ou build antigo, sem a chave).
  PriceBand? get priceBand;

  /// Timestamp do servidor.
  DateTime get createdAt;

  /// Derivado de [createdAt], nunca gravado (F02).
  DayPeriod get dayPeriod => DayPeriod.fromTimestamp(createdAt);
}
