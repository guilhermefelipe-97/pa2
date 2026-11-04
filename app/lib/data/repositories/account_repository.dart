abstract class AccountRepository {
  Future<void> refresh();
  String? get email;
  Future<void> requestEmailChange({
    required String email,
    required String currentPassword,
  });
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });
}
