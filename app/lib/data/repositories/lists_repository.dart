import '../../domain/models/place_list.dart';

class ListAccessDeniedException implements Exception {
  const ListAccessDeniedException();

  @override
  String toString() => 'ListAccessDeniedException';
}

abstract class ListsRepository {
  String newListId(String uid);

  Future<List<PlaceList>> listLists(String uid);

  Future<void> createList({
    required String uid,
    required String listId,
    required String name,
    required String? emoji,
    required List<String> placeIds,
    ListCredit? copiedFrom,
  });

  Future<void> setVisible({
    required String uid,
    required String listId,
    required bool visible,
  });

  Future<List<PlaceList>> listVisibleLists(String ownerUid);

  Future<int> copyCount({required String ownerUid, required String listId});

  Future<void> recordCopy({
    required String ownerUid,
    required String listId,
    required String copierUid,
    required String copiedListId,
  });

  Future<void> updateList({
    required String uid,
    required String listId,
    required String name,
    required String? emoji,
  });

  Future<void> deleteList({required String uid, required String listId});

  Future<void> setMembership({
    required String uid,
    required String listId,
    required String placeId,
    required bool member,
  });

  Future<void> removeEverywhere({
    required String uid,
    required String placeId,
    required Iterable<String> listIds,
  });
}
