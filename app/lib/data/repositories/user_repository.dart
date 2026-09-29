import '../../domain/models/user_profile.dart';

abstract class UserRepository {
  Future<void> createProfile({required String uid, required String displayName});

  Future<UserProfile?> getProfile(String uid);

  /// Busca por prefixo de `displayNameLower`.
  Future<List<UserProfile>> searchByName(String query, {int limit = 20});

  Future<Set<String>> getFollowing(String uid);

  Future<void> follow({required String uid, required String targetUid});

  Future<void> unfollow({required String uid, required String targetUid});
}
