part of 'place_activity.dart';

/// "Voltei aqui" (F15): uma ida ao local sem notas, já gravada. Imutável;
/// nunca anônima; o período do dia é derivado do `createdAt` do servidor.
class Visit extends PlaceActivity {
  const Visit({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.placeId,
    required this.placeName,
    required this.createdAt,
    this.companion,
  });

  @override
  final String id;
  @override
  final String authorId;
  @override
  final String authorName;
  @override
  final String placeId;
  @override
  final String placeName;
  @override
  final Companion? companion;
  @override
  final DateTime createdAt;
}

/// Dados que o cliente envia para registrar uma visita. Sem `createdAt` (é
/// sempre o do servidor) e sem notas (Never do F15).
class NewVisit {
  const NewVisit({
    required this.authorId,
    required this.authorName,
    required this.placeId,
    required this.placeName,
    this.companion,
  });

  final String authorId;
  final String authorName;
  final String placeId;
  final String placeName;
  final Companion? companion;
}
