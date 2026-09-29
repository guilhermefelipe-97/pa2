import '../../domain/models/place.dart';

abstract class PlaceRepository {
  Future<List<Place>> listPlaces();
}
