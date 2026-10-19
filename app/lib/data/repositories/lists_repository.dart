import '../../domain/models/place_list.dart';

/// A lista de outra pessoa não pode ser lida: quem lê não segue a dona (ou
/// deixou de seguir). As Rules negam; a tela trata como "não disponível".
class ListAccessDeniedException implements Exception {
  const ListAccessDeniedException();

  @override
  String toString() => 'ListAccessDeniedException';
}

/// Listas nomeadas (F12): `users/{uid}/lists/{listId}`, privadas por padrão
/// (F13: `visible` abre a lista para quem segue a dona). Toda escrita grava
/// `updatedAt` do servidor; `createdAt` só na criação.
abstract class ListsRepository {
  /// Id novo (gerado no cliente) para criar a lista de forma otimista.
  String newListId(String uid);

  /// Listas do usuário, da mais antiga para a mais nova.
  Future<List<PlaceList>> listLists(String uid);

  /// Cria a lista. Com [copiedFrom] (F13), grava o crédito (só aqui: depois
  /// ele é imutável).
  Future<void> createList({
    required String uid,
    required String listId,
    required String name,
    required String? emoji,
    required List<String> placeIds,
    ListCredit? copiedFrom,
  });

  /// "Visível para quem me segue" (F13).
  Future<void> setVisible({
    required String uid,
    required String listId,
    required bool visible,
  });

  /// Listas visíveis de [ownerUid] (F13), da mais antiga para a mais nova.
  /// Só quem segue [ownerUid] pode ler: para os demais, lança
  /// [ListAccessDeniedException].
  Future<List<PlaceList>> listVisibleLists(String ownerUid);

  /// Quantas pessoas copiaram a lista (F13, N32). Só a dona conta.
  Future<int> copyCount({required String ownerUid, required String listId});

  /// Registra que [copierUid] copiou a lista (uma vez por pessoa). Já
  /// registrada (ou negada pelas Rules) completa sem erro: o contador é
  /// "uma por pessoa". Outros erros (rede) sobem.
  Future<void> recordCopy({
    required String ownerUid,
    required String listId,
    required String copierUid,
  });

  /// Renomeia / troca o emoji.
  Future<void> updateList({
    required String uid,
    required String listId,
    required String name,
    required String? emoji,
  });

  /// Exclui a lista e o contador de cópias dela (os locais continuam no
  /// "Quero ir").
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
