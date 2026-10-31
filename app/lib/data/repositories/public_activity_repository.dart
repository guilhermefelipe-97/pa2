import '../activity_batch.dart';
import '../../domain/models/place_activity.dart';

/// Consulta exclusiva do Amigos: limites e cortes contam só idas públicas.
abstract class PublicActivityRepository<T extends PlaceActivity> {
  Future<ActivityBatch<T>> fetchPublicByAuthors(List<String> authors);
}
