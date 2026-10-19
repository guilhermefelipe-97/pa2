/// Origem do local no catálogo.
enum PlaceSource {
  /// Importado do OpenStreetMap (`firebase/seed/importar-osm.js`).
  osm,

  /// Curado à mão (`firebase/seed/places.json`); pode ter dados do OSM
  /// mesclados (ver [Place.osmId]).
  curated;

  static PlaceSource parse(Object? value) =>
      value == 'osm' ? PlaceSource.osm : PlaceSource.curated;
}

/// Local avaliável. Populado via seed (Natal) ou criado pelo app na 1ª
/// interação com um local descoberto pelo Photon (G2); nunca editado pelo app.
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
    this.lat,
    this.lng,
    this.geohash,
    this.cuisine,
    this.address,
    this.openingHours,
    this.osmId,
    this.source = PlaceSource.curated,
    this.inCatalog = true,
    this.discovered = false,
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

  /// Coordenadas (OSM). Ausentes em curados sem par no OSM.
  final double? lat;
  final double? lng;

  /// Geohash (precisão 9) de [lat]/[lng], gravado pelo seed: é o campo das
  /// consultas por faixa do "Perto" (F10).
  final String? geohash;

  /// Tem coordenadas (pode aparecer no "Perto").
  bool get hasCoordinates => lat != null && lng != null;

  /// Cozinha legível em pt-BR ("Pizza, Italiano").
  final String? cuisine;

  /// Endereço ("Rua X, 123").
  final String? address;

  /// Horário bruto do OSM (`opening_hours`); interpretar fica para o F20.
  final String? openingHours;

  /// `node/123`, `way/456`... quando há dados do OSM.
  final String? osmId;

  final PlaceSource source;

  /// `false` no Place mínimo que o feed monta quando o id da avaliação não
  /// está no catálogo: sem doc em `places`, as Rules negam salvar.
  final bool inCatalog;

  /// Veio só da descoberta ao vivo (Photon/OSM, G2) e ainda não existe em
  /// `places`: a 1ª avaliação ou salvamento cria o doc (o app nunca grava
  /// local só visto).
  final bool discovered;

  /// Cópia com [discovered] trocado (único campo que muda no ciclo de vida
  /// do local no app: o resto vem do OSM/seed e o app nunca edita).
  Place copyWith({bool? discovered}) => Place(
    id: id,
    name: name,
    category: category,
    neighborhood: neighborhood,
    city: city,
    photoUrl: photoUrl,
    photoAuthor: photoAuthor,
    photoLicense: photoLicense,
    photoIllustrative: photoIllustrative,
    lat: lat,
    lng: lng,
    geohash: geohash,
    cuisine: cuisine,
    address: address,
    openingHours: openingHours,
    osmId: osmId,
    source: source,
    inCatalog: inCatalog,
    discovered: discovered ?? this.discovered,
  );

  /// Mesmo local, agora gravado em `places` (não é mais só descoberto).
  Place asPersisted() => discovered ? copyWith(discovered: false) : this;

  /// Tem dados vindos do OpenStreetMap (exige o crédito © OpenStreetMap).
  bool get hasOsmData => source == PlaceSource.osm || osmId != null;

  @override
  bool operator ==(Object other) => other is Place && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
