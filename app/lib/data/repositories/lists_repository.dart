import '../../domain/models/place_list.dart';

/// Listas nomeadas (F12): `users/{uid}/lists/{listId}`, privadas. Toda
/// escrita grava `updatedAt` do servidor; `createdAt` só na criação.
abstract class ListsRepository {
  /// Id novo (gerado no cliente) para criar a lista de forma otimista.
  String newListId(String uid);

  /// Listas do usuário, da mais antiga para a mais nova.
  Future<List<PlaceList>> listLists(String uid);

  Future<void> createList({
    required String uid,
    required String listId,
    required String name,
    required String? emoji,
    required List<String> placeIds,
  });

  /// Renomeia / troca o emoji.
  Future<void> updateList({
    required String uid,
    required String listId,
    required String name,
    required String? emoji,
  });

  /// Exclui só a lista (os locais continuam no "Quero ir").
  Future<void> deleteList({required String uid, required String listId});

  /// Põe ([member] `true`) ou tira [placeId] da lista (`arrayUnion` /
  /// `arrayRemove`).
  Future<void> setMembership({
    required String uid,
    required String listId,
    required String placeId,
    required bool member,
  });

  /// Num único batch: apaga `saved/{placeId}` e tira [placeId] de cada lista
  /// de [listIds].
  Future<void> removeEverywhere({
    required String uid,
    required String placeId,
    required Iterable<String> listIds,
  });
}
