import 'dart:typed_data';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/data/firebase/firestore_profile_editor_repository.dart';
import 'package:naarea/data/firebase/firestore_user_repository.dart';
import 'package:naarea/data/repositories/profile_editor_repository.dart';
import 'package:naarea/domain/models/user_profile.dart';

void main() {
  test('Instagram salva, recarrega e rejeita URL e excesso', () async {
    final db = FakeFirebaseFirestore();
    final users = FirestoreUserRepository(db);
    await users.createProfile(uid: 'me', displayName: 'Bianca');
    final repo = FirestoreProfileEditorRepository(db);
    await repo.save(
      const UserProfile(
        uid: 'me',
        displayName: 'Bianca',
        username: 'bianca.cafes',
        instagram: 'bianca.cafes',
      ),
    );
    expect((await users.getProfile('me'))!.instagram, 'bianca.cafes');
    await expectLater(
      repo.save(
        const UserProfile(
          uid: 'me',
          displayName: 'Bianca',
          username: 'bianca.cafes',
          instagram: 'https://instagram.com/bianca',
        ),
      ),
      throwsA(isA<ProfileEditException>()),
    );
    expect((await users.getProfile('me'))!.instagram, 'bianca.cafes');
  });
  test(
    'grava @ e bio, reserva nome e fotos sem alterar avaliações antigas',
    () async {
      final db = FakeFirebaseFirestore();
      final users = FirestoreUserRepository(db);
      await users.createProfile(uid: 'me', displayName: 'Ana');
      await db.doc('reviews/antiga').set({
        'authorId': 'me',
        'authorName': 'Ana',
      });
      final repo = FirestoreProfileEditorRepository(db);
      final jpeg = Uint8List.fromList([255, 216, 255, 217]);
      await repo.save(
        const UserProfile(
          uid: 'me',
          displayName: 'Ana Silva',
          username: 'ana.silva',
          bio: 'Cafés e viagens.',
          city: 'Natal',
        ),
        avatar: jpeg,
        cover: jpeg,
      );
      final p = (await users.getProfile('me'))!;
      expect(p.username, 'ana.silva');
      expect(p.bio, 'Cafés e viagens.');
      expect((await db.doc('usernames/ana.silva').get()).data()!['uid'], 'me');
      expect((await db.doc('users/me/media/cover').get()).exists, isTrue);
      expect(
        (await db.doc('reviews/antiga').get()).data()!['authorName'],
        'Ana',
      );
      await repo.save(
        const UserProfile(
          uid: 'me',
          displayName: 'Ana Silva',
          username: 'ana.cafes',
        ),
        removeCover: true,
      );
      expect((await db.doc('usernames/ana.silva').get()).exists, isFalse);
      expect((await db.doc('usernames/ana.cafes').get()).data()!['uid'], 'me');
      expect((await db.doc('users/me/media/cover').get()).exists, isFalse);
      expect((await users.searchByName('@ana.ca')).single.uid, 'me');
    },
  );
  test('@ ocupado não altera perfil nem grava foto parcialmente', () async {
    final db = FakeFirebaseFirestore();
    await FirestoreUserRepository(
      db,
    ).createProfile(uid: 'me', displayName: 'Ana');
    await db.doc('usernames/ocupado').set({'uid': 'outro'});
    final repo = FirestoreProfileEditorRepository(db);
    await expectLater(
      repo.save(
        const UserProfile(
          uid: 'me',
          displayName: 'Ana Nova',
          username: 'ocupado',
        ),
        cover: Uint8List.fromList([255, 216, 255, 217]),
      ),
      throwsA(isA<ProfileEditException>()),
    );
    expect((await db.doc('users/me').get()).data()!['displayName'], 'Ana');
    expect((await db.doc('users/me/media/cover').get()).exists, isFalse);
  });
}
