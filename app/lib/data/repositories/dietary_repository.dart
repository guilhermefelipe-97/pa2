abstract class DietaryRepository {
  Future<Set<String>> load(String uid);
  Future<void> save(String uid, Set<String> tags);
}
