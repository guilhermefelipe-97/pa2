/// Um local salvo em "Quero ir" (F11).
class SavedPlace {
  const SavedPlace({required this.placeId, required this.savedAt});

  final String placeId;

  /// `createdAt` do servidor.
  final DateTime savedAt;
}

/// "Quero ir": `users/{uid}/saved/{placeId}`, privado (só o dono lê/escreve).
abstract class SavedRepository {
  /// Salvos do usuário, do mais recente para o mais antigo.
  Future<List<SavedPlace>> listSaved(String uid);

  /// Cria o doc só com `createdAt` do servidor (as Rules negam update: não
  /// chamar para um local já salvo).
  Future<void> save({required String uid, required String placeId});

  Future<void> remove({required String uid, required String placeId});

  /// `createdAt` do servidor se `saved/{placeId}` existe; `null` se não
  /// existe. Usado para confirmar um save que falhou porque o doc já existia
  /// (set em doc existente vira update, negado pelas Rules) ou cuja resposta
  /// se perdeu, e para trocar o relógio do cliente pela hora real.
  Future<DateTime?> savedAtOf({required String uid, required String placeId});
}
