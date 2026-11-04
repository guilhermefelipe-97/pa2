import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/models/user_profile.dart';
import '../../domain/photo_compression.dart';
import '../repositories/profile_editor_repository.dart';

class FirestoreProfileEditorRepository implements ProfileEditorRepository {
  FirestoreProfileEditorRepository(this.db);
  final FirebaseFirestore db;
  @override
  Future<void> save(
    UserProfile profile, {
    Uint8List? avatar,
    Uint8List? cover,
    bool removeAvatar = false,
    bool removeCover = false,
  }) async {
    if (!UserProfile.isValidName(profile.displayName) ||
        !UserProfile.validUsername(profile.username) ||
        profile.bio.length > UserProfile.maxBioLength ||
        profile.city.length > 80 ||
        !UserProfile.validInstagram(profile.instagram)) {
      throw const ProfileEditException(
        'Confira o nome, o @usuário e os limites dos campos.',
      );
    }
    for (final photo in [avatar, cover].whereType<Uint8List>()) {
      if (photo.length < 4 ||
          photo.length > maxPhotoBytes ||
          photo[0] != 255 ||
          photo[1] != 216) {
        throw const ProfileEditException(
          'Não foi possível usar a imagem selecionada.',
        );
      }
    }
    final user = db.collection('users').doc(profile.uid);
    final handle = db.collection('usernames').doc(profile.username);
    await db.runTransaction((tx) async {
      final previous = await tx.get(user);
      final reserved = await tx.get(handle);
      if (!previous.exists) {
        throw const ProfileEditException(
          'Perfil não encontrado. Entre novamente.',
        );
      }
      if (reserved.exists && reserved.data()?['uid'] != profile.uid) {
        throw const ProfileEditException(
          'Este @usuário já está em uso. Escolha outro.',
        );
      }
      final oldHandle = previous.data()?['username'] as String?;
      if (!reserved.exists) tx.set(handle, {'uid': profile.uid});
      tx.update(user, {
        'displayName': profile.displayName.trim(),
        'displayNameLower': profile.displayName.trim().toLowerCase(),
        'username': profile.username,
        'bio': profile.bio.trim(),
        'city': profile.city.trim(),
        'instagram': profile.instagram,
      });
      if (oldHandle != null &&
          oldHandle.isNotEmpty &&
          oldHandle != profile.username) {
        tx.delete(db.collection('usernames').doc(oldHandle));
      }
      for (final (kind, jpeg, remove) in [
        ('avatar', avatar, removeAvatar),
        ('cover', cover, removeCover),
      ]) {
        final media = user.collection('media').doc(kind);
        if (remove) {
          tx.delete(media);
        } else if (jpeg != null) {
          tx.set(media, {'jpeg': Blob(jpeg)});
        }
      }
    });
  }
}
