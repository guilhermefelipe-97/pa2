import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';
import 'package:naarea/data/firebase/firestore_lists_repository.dart';
import 'package:naarea/domain/models/place_list.dart';

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

  group('FirestoreListsRepository (F13: visível e cópia com crédito)', () {
    late FakeFirebaseFirestore db;
    late FirestoreListsRepository repo;

    setUp(() {
      db = FakeFirebaseFirestore();
      repo = FirestoreListsRepository(db);
    });

    const credit = ListCredit(uid: 'ana', name: 'Ana', listId: 'sabado');

    test('createList com crédito grava o trio (e nada de visible)', () async {
      await repo.createList(
        uid: 'me',
        listId: 'l',
        name: 'Sábado',
        emoji: '🎉',
        placeIds: ['a'],
        copiedFrom: credit,
      );
      final data = (await db.doc('users/me/lists/l').get()).data()!;
      expect(data.keys.toSet(), {
        'name',
        'emoji',
        'placeIds',
        'copiedFromUid',
        'copiedFromName',
        'copiedFromListId',
        'createdAt',
        'updatedAt',
      });
      expect(data['copiedFromUid'], 'ana');
      expect(data['copiedFromName'], 'Ana');
      expect(data['copiedFromListId'], 'sabado');
      final list = (await repo.listLists('me')).single;
      expect(list.copiedFrom, credit);
      expect(list.visible, isFalse);
    });

    test('lista antiga (sem os opcionais) é privada e sem crédito', () async {
      await db.doc('users/me/lists/l').set({
        'name': 'A',
        'emoji': null,
        'placeIds': <String>[],
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      });
      final list = (await repo.listLists('me')).single;
      expect(list.visible, isFalse);
      expect(list.copiedFrom, isNull);
    });

    test('crédito incompleto ou fora do tipo é ignorado na leitura', () async {
      await db.doc('users/me/lists/l').set({
        'name': 'A',
        'emoji': null,
        'placeIds': <String>[],
        'copiedFromUid': 'ana',
        'copiedFromName': 7,
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      });
      expect((await repo.listLists('me')).single.copiedFrom, isNull);
    });

    test('setVisible grava visible e updatedAt; mantém o resto', () async {
      await repo.createList(
        uid: 'me',
        listId: 'l',
        name: 'A',
        emoji: null,
        placeIds: ['a'],
        copiedFrom: credit,
      );
      await repo.setVisible(uid: 'me', listId: 'l', visible: true);
      final data = (await db.doc('users/me/lists/l').get()).data()!;
      expect(data['visible'], isTrue);
      expect(data['updatedAt'], isA<Timestamp>());
      expect(data['copiedFromUid'], 'ana');
      expect((await repo.listLists('me')).single.visible, isTrue);
      await repo.setVisible(uid: 'me', listId: 'l', visible: false);
      expect((await repo.listLists('me')).single.visible, isFalse);
    });

    test(
      'listVisibleLists: só as visíveis da dona, mais antiga primeiro',
      () async {
        Future<void> put(String id, DateTime at, {Object? visible}) =>
            db.doc('users/ana/lists/$id').set({
              'name': id,
              'emoji': null,
              'placeIds': ['a', 'b'],
              'visible': ?visible,
              'createdAt': Timestamp.fromDate(at),
              'updatedAt': Timestamp.fromDate(at),
            });
        await put('nova', DateTime.utc(2026, 9, 20), visible: true);
        await put('velha', DateTime.utc(2026, 9, 1), visible: true);
        await put('privada', DateTime.utc(2026, 9, 2), visible: false);
        await put('antiga', DateTime.utc(2026, 9, 3));
        final lists = await repo.listVisibleLists('ana');
        expect(lists.map((l) => l.id), ['velha', 'nova']);
        expect(lists.first.placeIds, ['a', 'b']);
        expect(lists.first.visible, isTrue);
      },
    );

    test('recordCopy / copyCount (um doc por pessoa, sem ler antes)', () async {
      expect(await repo.copyCount(ownerUid: 'ana', listId: 'sabado'), 0);
      await repo.recordCopy(ownerUid: 'ana', listId: 'sabado', copierUid: 'me');
      await repo.recordCopy(
        ownerUid: 'ana',
        listId: 'sabado',
        copierUid: 'bia',
      );
      final doc = await db.doc('users/ana/lists/sabado/copies/me').get();
      expect(doc.data()!.keys.toSet(), {'createdAt'});
      expect(doc.data()!['createdAt'], isA<Timestamp>());
      expect(await repo.copyCount(ownerUid: 'ana', listId: 'sabado'), 2);
      expect(await repo.copyCount(ownerUid: 'ana', listId: 'outra'), 0);
    });

    test('recordCopy: 2ª cópia negada pelas Rules (vira update) = já '
        'registrada, sem erro; outro erro sobe', () async {
      final ref = db.doc('users/ana/lists/sabado/copies/me');
      whenCalling(Invocation.method(#set, null))
          .on(ref)
          .thenThrow(
            FirebaseException(
              plugin: 'cloud_firestore',
              code: 'permission-denied',
            ),
          );
      await repo.recordCopy(ownerUid: 'ana', listId: 'sabado', copierUid: 'me');
      final other = db.doc('users/ana/lists/sabado/copies/bia');
      whenCalling(Invocation.method(#set, null))
          .on(other)
          .thenThrow(
            FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
          );
      await expectLater(
        repo.recordCopy(ownerUid: 'ana', listId: 'sabado', copierUid: 'bia'),
        throwsA(isA<FirebaseException>()),
      );
    });

    test('deleteList apaga a lista e o contador de cópias dela', () async {
      await repo.createList(
        uid: 'ana',
        listId: 'sabado',
        name: 'Sábado',
        emoji: null,
        placeIds: ['a'],
      );
      await repo.createList(
        uid: 'ana',
        listId: 'outra',
        name: 'Outra',
        emoji: null,
        placeIds: [],
      );
      for (final u in ['me', 'bia', 'caio']) {
        await repo.recordCopy(ownerUid: 'ana', listId: 'sabado', copierUid: u);
      }
      await repo.recordCopy(ownerUid: 'ana', listId: 'outra', copierUid: 'me');
      await repo.deleteList(uid: 'ana', listId: 'sabado');
      expect((await db.doc('users/ana/lists/sabado').get()).exists, isFalse);
      expect(
        (await db.collection('users/ana/lists/sabado/copies').get()).docs,
        isEmpty,
      );
      expect(await repo.copyCount(ownerUid: 'ana', listId: 'outra'), 1);
    });

    test('deleteList com mais cópias que um batch: apaga todas', () async {
      await repo.createList(
        uid: 'ana',
        listId: 'sabado',
        name: 'Sábado',
        emoji: null,
        placeIds: [],
      );
      final copies = db.collection('users/ana/lists/sabado/copies');
      for (var i = 0; i < FirestoreListsRepository.maxBatchWrites + 20; i++) {
        await copies.doc('u$i').set({'createdAt': Timestamp.now()});
      }
      await repo.deleteList(uid: 'ana', listId: 'sabado');
      expect((await copies.get()).docs, isEmpty);
      expect((await db.doc('users/ana/lists/sabado').get()).exists, isFalse);
    });
  });
}
