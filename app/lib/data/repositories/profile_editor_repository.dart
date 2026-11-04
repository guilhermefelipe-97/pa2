import 'dart:typed_data';
import '../../domain/models/user_profile.dart';

class ProfileEditException implements Exception {
  const ProfileEditException(this.message);
  final String message;
}

abstract class ProfileEditorRepository {
  Future<void> save(
    UserProfile profile, {
    Uint8List? avatar,
    Uint8List? cover,
    bool removeAvatar = false,
    bool removeCover = false,
  });
}
