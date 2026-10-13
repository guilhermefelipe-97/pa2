/// Relato "Está aberto agora?" (F20): quem estava no local disse Sim
/// ([open] `true`) ou Não. Nunca anônimo e imutável; [createdAt] é a hora
/// do servidor.
class OpenReport {
  const OpenReport({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.placeId,
    required this.open,
    required this.createdAt,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String placeId;
  final bool open;
  final DateTime createdAt;
}

/// Relato a enviar (o id e o `createdAt` vêm do Firestore).
class NewOpenReport {
  const NewOpenReport({
    required this.authorId,
    required this.authorName,
    required this.placeId,
    required this.open,
  });

  final String authorId;
  final String authorName;
  final String placeId;
  final bool open;
}
