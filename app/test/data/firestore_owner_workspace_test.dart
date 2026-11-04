import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/data/firebase/firestore_owner_workspace_repository.dart';
import 'package:naarea/data/repositories/owner_workspace_repository.dart';

void main() {
  test(
    'apresentação vazia não inventa dados e salvar preserva cadastro e avaliações',
    () async {
      final db = FakeFirebaseFirestore();
      final repo = FirestoreOwnerWorkspaceRepository(db);
      expect((await repo.presentation('p')).description, '');
      await db.doc('places/p').set({
        'name': 'Café',
        'openingHours': 'Tu-Su 12:00-22:00',
      });
      await db.doc('reviews/r').set({'comment': 'Gostei', 'authorId': 'ana'});
      await repo.save(
        'p',
        'me',
        const PlacePresentation(
          description: ' Café artesanal. ',
          hours: ' Terça a domingo, 12h–22h. ',
        ),
      );
      final data = await repo.presentation('p');
      expect(data.description, 'Café artesanal.');
      expect(data.hours, 'Terça a domingo, 12h–22h.');
      expect(
        (await db.doc('placePresentations/p').get()).data()!['updatedBy'],
        'me',
      );
      expect((await db.doc('places/p').get()).data()!['name'], 'Café');
      expect((await db.doc('reviews/r').get()).data()!['comment'], 'Gostei');
      await repo.save('p', 'me', const PlacePresentation());
      expect((await repo.presentation('p')).hours, '');
      await expectLater(
        repo.save('p', 'me', PlacePresentation(description: 'x' * 1001)),
        throwsArgumentError,
      );
      await expectLater(
        repo.save('p', 'me', PlacePresentation(hours: 'x' * 501)),
        throwsArgumentError,
      );
    },
  );
  test(
    'contagens e média incluem todas as páginas e eixos preenchidos',
    () async {
      final db = FakeFirebaseFirestore();
      final repo = FirestoreOwnerWorkspaceRepository(db);
      for (var i = 0; i < 27; i++) {
        await db.doc('reviews/$i').set({
          'placeId': 'p',
          'food': 5,
          'ambience': i < 3 ? 3 : null,
          'service': null,
        });
      }
      for (var i = 0; i < 4; i++) {
        await db.doc('ownerReplies/$i').set({
          'placeId': 'p',
          'authorId': 'old-owner',
        });
      }
      final result = await repo.summary('p');
      expect(result.reviews, 27);
      expect(result.unanswered, 23);
      expect(result.rating, 4.8);
      final empty = await repo.summary('empty');
      expect(empty.reviews, 0);
      expect(empty.unanswered, 0);
      expect(empty.rating, isNull);
    },
  );
}
