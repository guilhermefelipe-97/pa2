import 'dart:typed_data';
import 'package:naarea/data/repositories/profile_editor_repository.dart';
import 'package:naarea/data/repositories/profile_media_repository.dart';
import 'package:naarea/data/repositories/account_repository.dart';
import 'package:naarea/data/repositories/reputation_repository.dart';
import 'package:naarea/data/repositories/profile_stats_repository.dart';
import 'package:naarea/data/repositories/auth_repository.dart';
import 'package:naarea/domain/models/user_profile.dart';
import 'package:naarea/domain/models/review.dart';
import 'fakes.dart';

class FakeProfileMedia extends ProfileMediaRepository {
  final bytes = <String, Uint8List>{};
  @override
  Future<Uint8List?> get(String uid, String kind) async => bytes['$uid/$kind'];
  @override
  void invalidate(String uid) => notifyListeners();
}

class FakeProfileEditor implements ProfileEditorRepository {
  FakeProfileEditor(this.users, this.media);
  final FakeUserRepository users;
  final FakeProfileMedia media;
  int writes = 0;
  bool fail = false;
  @override
  Future<void> save(
    UserProfile profile, {
    Uint8List? avatar,
    Uint8List? cover,
    bool removeAvatar = false,
    bool removeCover = false,
  }) async {
    if (fail) {
      throw const ProfileEditException('Falha de conexão. Tente novamente.');
    }
    if (users.profiles.values.any(
      (p) => p.uid != profile.uid && p.username == profile.username,
    )) {
      throw const ProfileEditException(
        'Este @usuário já está em uso. Escolha outro.',
      );
    }
    users.profiles[profile.uid] = profile;
    for (final (kind, data, remove) in [
      ('avatar', avatar, removeAvatar),
      ('cover', cover, removeCover),
    ]) {
      if (remove) {
        media.bytes.remove('${profile.uid}/$kind');
      } else if (data != null) {
        media.bytes['${profile.uid}/$kind'] = data;
      }
    }
    writes++;
  }
}

class FakeAccountRepository implements AccountRepository {
  @override
  Future<void> refresh() async {}
  String currentEmail = 'conta@exemplo.com';
  String? requestedEmail;
  int passwordChanges = 0;
  @override
  String? get email => currentEmail;
  @override
  Future<void> requestEmailChange({
    required String email,
    required String currentPassword,
  }) async {
    if (currentPassword != 'senha-atual') {
      throw const AuthException('Senha atual incorreta.');
    }
    requestedEmail = email;
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (currentPassword != 'senha-atual') {
      throw const AuthException('Senha atual incorreta.');
    }
    passwordChanges++;
  }
}

class FakeProfileStats implements ProfileStatsRepository {
  FakeProfileStats(this.users, this.reviews);
  final FakeUserRepository users;
  final FakeReviewRepository reviews;
  @override
  Future<ProfileTotals> totals(String uid) async => ProfileTotals(
    reviews: reviews.stored.where((r) => r.authorId == uid).length,
    visits: 0,
    following: users.followingByUser[uid]?.length ?? 0,
  );
}

class PreviewProfileReplies implements ReputationRepository {
  @override
  Future<OwnerReply?> replyFor(String id) async => id == 'profile-preview'
      ? OwnerReply(
          'owner',
          'Equipe Café da Praça',
          'Obrigado pela visita! Ficamos felizes que você tenha gostado do café. Esperamos receber vocês novamente.',
          DateTime.now().subtract(const Duration(days: 1)),
        )
      : null;
  @override
  Future<ReviewPage> reviewsForPlace(String placeId, {String? after}) async =>
      (reviews: <Review>[], next: null);
  @override
  Future<void> reply(String uid, String reviewId, String text) async =>
      throw UnimplementedError();
}
