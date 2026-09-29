/// Local avaliável (somente leitura para o cliente; populado via seed).
class Place {
  const Place({
    required this.id,
    required this.name,
    required this.category,
    required this.neighborhood,
    required this.city,
  });

  final String id;
  final String name;
  final String category;
  final String neighborhood;
  final String city;

  @override
  bool operator ==(Object other) => other is Place && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
