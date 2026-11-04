import '../price_band.dart';
import 'companion.dart';
import 'day_period.dart';
import 'scores.dart';

part 'place_activity_review.dart';
part 'place_activity_visit.dart';

sealed class PlaceActivity {
  const PlaceActivity();

  bool get silent;
  String get id;
  String get authorId;
  String get authorName;
  String get placeId;
  String get placeName;
  Companion? get companion;

  PriceBand? get priceBand;

  DateTime get createdAt;

  DayPeriod get dayPeriod => DayPeriod.fromTimestamp(createdAt);
}
