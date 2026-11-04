abstract class FoodTagRepository {
  Future<Map<String, Map<String, int>>> confirmedFor(Iterable<String> placeIds);
}
