import '../activity_batch.dart';
import '../../domain/models/place_activity.dart';

abstract class PublicActivityRepository<T extends PlaceActivity> {
  Future<ActivityBatch<T>> fetchPublicByAuthors(List<String> authors);
}
