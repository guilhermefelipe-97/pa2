import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/data/firebase/firestore_lists_repository.dart';

void main() {
  group('FirestoreListsRepository', () {
    late FakeFirebaseFirestore db;
    late FirestoreListsRepository repo;

    setUp(() {
      db = FakeFirebaseFirestore();
      repo = FirestoreListsRepository(db);
    });

    test('createList grava o schema exato das Rules', () async {
      final id = repo.newListId('me');
      await repo.createList(
        uid: 'me',
        listId: id,
        name: 'Sábado com as meninas',
        emoji: '🎉',
        placeIds: ['mangai'],
      );
      final data = (await db.doc('users/me/lists/$id').get()).data()!;
      expect(data.keys.toSet(), {
        'name',
        'emoji',
        'placeIds',
        'createdAt',
        'updatedAt',
      });
      expect(data['name'], 'Sábado com as meninas');
      expect(data['emoji'], '🎉');
      expect(data['placeIds'], ['mangai']);
      expect(data['createdAt'], isA<Timestamp>());
      expect(data['updatedAt'], isA<Timestamp>());
    });

    test('listLists: só do usuário, da mais antiga para a mais nova', () async {
      Future<void> put(String uid, String id, String name, DateTime at) =>
          db.doc('users/$uid/lists/$id').set({
            'name': name,
            'emoji': null,
            'placeIds': ['a'],
            'createdAt': Timestamp.fromDate(at),
            'updatedAt': Timestamp.fromDate(at),
          });
      await put('me', 'nova', 'Nova', DateTime.utc(2026, 9, 20));
      await put('me', 'velha', 'Velha', DateTime.utc(2026, 9, 1));
      await put('outra', 'x', 'X', DateTime.utc(2026, 9, 5));

      final lists = await repo.listLists('me');
      expect(lists.map((l) => l.id), ['velha', 'nova']);
      expect(lists.first.name, 'Velha');
      expect(lists.first.emoji, isNull);
      expect(lists.first.placeIds, ['a']);
    });

    test('updateList renomeia, troca emoji e mantém createdAt', () async {
      await repo.createList(
        uid: 'me',
        listId: 'l',
        name: 'A',
        emoji: null,
        placeIds: [],
      );
      final before = (await db.doc('users/me/lists/l').get()).data()!;
      await repo.updateList(uid: 'me', listId: 'l', name: 'B', emoji: '🍕');
      final data = (await db.doc('users/me/lists/l').get()).data()!;
      expect(data['name'], 'B');
      expect(data['emoji'], '🍕');
      expect(data['createdAt'], before['createdAt']);
    });

    test('setMembership: arrayUnion / arrayRemove', () async {
      await repo.createList(
        uid: 'me',
        listId: 'l',
        name: 'A',
        emoji: null,
        placeIds: ['a'],
      );
      await repo.setMembership(
        uid: 'me',
        listId: 'l',
        placeId: 'b',
        member: true,
      );
      await repo.setMembership(
        uid: 'me',
        listId: 'l',
        placeId: 'b',
        member: true,
      );
      expect((await db.doc('users/me/lists/l').get()).data()!['placeIds'], [
        'a',
        'b',
      ]);
      await repo.setMembership(
        uid: 'me',
        listId: 'l',
        placeId: 'a',
        member: false,
      );
      expect((await db.doc('users/me/lists/l').get()).data()!['placeIds'], [
        'b',
      ]);
    });

    test('removeEverywhere apaga o salvo e tira das listas', () async {
      await db.doc('users/me/saved/a').set({'createdAt': Timestamp.now()});
      for (final id in ['l1', 'l2', 'l3']) {
        await repo.createList(
          uid: 'me',
          listId: id,
          name: id,
          emoji: null,
          placeIds: ['a', 'b'],
        );
      }
      await repo.removeEverywhere(
        uid: 'me',
        placeId: 'a',
        listIds: ['l1', 'l2'],
      );
      expect((await db.doc('users/me/saved/a').get()).exists, isFalse);
      expect((await db.doc('users/me/lists/l1').get()).data()!['placeIds'], [
        'b',
      ]);
      expect((await db.doc('users/me/lists/l2').get()).data()!['placeIds'], [
        'b',
      ]);
      expect((await db.doc('users/me/lists/l3').get()).data()!['placeIds'], [
        'a',
        'b',
      ]);
    });

    test('deleteList apaga só a lista', () async {
      await db.doc('users/me/saved/a').set({'createdAt': Timestamp.now()});
      await repo.createList(
        uid: 'me',
        listId: 'l',
        name: 'A',
        emoji: null,
        placeIds: ['a'],
      );
      await repo.deleteList(uid: 'me', listId: 'l');
      expect((await db.doc('users/me/lists/l').get()).exists, isFalse);
      expect((await db.doc('users/me/saved/a').get()).exists, isTrue);
    });
  });
}
