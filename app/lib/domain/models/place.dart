/// Local avaliável (somente leitura para o cliente; populado via seed).
class Place {
  const Place({
    required this.id,
    required this.name,
    required this.category,
    required this.neighborhood,
    required this.city,
    this.photoUrl,
    this.photoAuthor,
    this.photoLicense,
    this.photoIllustrative = false,
  });

  final String id;
  final String name;
  final String category;
  final String neighborhood;
  final String city;

  /// Foto de capa (URL pública com licença livre, fixada no seed). Pode faltar
  /// ou estar quebrada: a UI sempre tem um fallback.
  final String? photoUrl;

  /// Crédito da foto (CC BY / BY-SA exigem atribuição).
  final String? photoAuthor;
  final String? photoLicense;

  /// A foto não mostra o próprio local (ex.: o bairro ou um prato típico).
  final bool photoIllustrative;

  @override
  bool operator ==(Object other) => other is Place && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
