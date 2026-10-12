/// Categoria e cozinha em pt-BR a partir das tags `amenity` e `cuisine` do
/// OpenStreetMap (G2).
///
/// PORTA FIEL de `firebase/seed/osm/category.js`: o seed de Natal e os locais
/// descobertos pelo Photon precisam cair no mesmo vocabulário (os chips do
/// seletor não duplicam e as Rules só aceitam categorias de
/// [osmCategories]). Os dois lados são testados contra a mesma fixture:
/// `firebase/tests/fixtures/osm-category.json`.
library;

/// Valores de `amenity` que são locais de comer/beber.
const osmAmenities = [
  'restaurant',
  'fast_food',
  'pub',
  'bar',
  'cafe',
  'ice_cream',
  'food_court',
  'biergarten',
];

const _amenityLabel = {
  'restaurant': 'Restaurante',
  'fast_food': 'Lanchonete',
  'pub': 'Pub',
  'bar': 'Bar',
  'cafe': 'Café',
  'ice_cream': 'Sorveteria',
  'food_court': 'Praça de alimentação',
  'biergarten': 'Cervejaria',
};

/// Cozinhas que viram a própria categoria (a 1ª reconhecida vence).
const _cuisineCategory = {
  'pizza': 'Pizzaria',
  'burger': 'Hamburgueria',
  'sushi': 'Japonês',
  'japanese': 'Japonês',
  'steak_house': 'Churrascaria',
  'barbecue': 'Churrascaria',
  'churrascaria': 'Churrascaria',
  'seafood': 'Frutos do mar',
  'fish': 'Frutos do mar',
  'ice_cream': 'Sorveteria',
  'coffee_shop': 'Café',
  'bakery': 'Padaria',
  'tapioca': 'Tapiocaria',
  'acai': 'Açaí',
  'açaí': 'Açaí',
  'regional': 'Comida regional',
  'brazilian': 'Comida brasileira',
  'italian': 'Italiano',
  'chinese': 'Chinês',
  'arab': 'Árabe',
  'mexican': 'Mexicano',
  'vegetarian': 'Vegetariano',
  'vegan': 'Vegano',
};

/// Rótulos de COZINHA (o que se come), independentes dos de categoria.
const _cuisineLabel = {
  'pizza': 'Pizza',
  'burger': 'Hambúrguer',
  'sushi': 'Sushi',
  'japanese': 'Japonesa',
  'chinese': 'Chinesa',
  'korean': 'Coreana',
  'thai': 'Tailandesa',
  'indian': 'Indiana',
  'asian': 'Asiática',
  'italian': 'Italiana',
  'french': 'Francesa',
  'portuguese': 'Portuguesa',
  'peruvian': 'Peruana',
  'mexican': 'Mexicana',
  'arab': 'Árabe',
  'lebanese': 'Árabe',
  'international': 'Internacional',
  'regional': 'Comida regional',
  'local': 'Comida regional',
  'brazilian': 'Brasileira',
  'steak_house': 'Churrasco',
  'barbecue': 'Churrasco',
  'churrascaria': 'Churrasco',
  'seafood': 'Frutos do mar',
  'fish': 'Peixe',
  'chicken': 'Frango',
  'sandwich': 'Sanduíche',
  'hot_dog': 'Cachorro-quente',
  'pastel': 'Pastel',
  'crepe': 'Crepe',
  'tapioca': 'Tapioca',
  'kebab': 'Kebab',
  'vegetarian': 'Vegetariana',
  'vegan': 'Vegana',
  'buffet': 'Bufê',
  'ice_cream': 'Sorvete',
  'acai': 'Açaí',
  'açaí': 'Açaí',
  'coffee_shop': 'Café',
  'cafe': 'Café',
  'coffee': 'Café',
  'bakery': 'Padaria',
  'cake': 'Bolos',
  'dessert': 'Sobremesas',
  'donut': 'Donuts',
  'juice': 'Sucos',
};

/// Categoria de quando o `amenity` não é de comer/beber (fora do
/// vocabulário: o app nunca cria local com ela).
const osmUnknownCategory = 'Local';

/// Valores de `cuisine` ("pizza;italian" → ["pizza", "italian"]).
List<String> _cuisineKeys(String? cuisine) => (cuisine ?? '')
    .split(';')
    .map((c) => c.trim().toLowerCase())
    .where((c) => c.isNotEmpty)
    .toList();

String _humanize(String key) {
  final s = key.replaceAll('_', ' ');
  return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// Categoria pt-BR: a cozinha refina restaurante/lanchonete; o resto segue o
/// `amenity`.
String osmCategoryFor(String? amenity, [String? cuisine]) {
  final base = _amenityLabel[amenity] ?? osmUnknownCategory;
  if (amenity != 'restaurant' && amenity != 'fast_food') return base;
  for (final key in _cuisineKeys(cuisine)) {
    final c = _cuisineCategory[key];
    if (c != null) return c;
  }
  return base;
}

/// Cozinha legível ("pizza;italian" → "Pizza, Italiana"); "" se ausente.
String osmCuisineLabel(String? cuisine) {
  final labels = <String>[];
  for (final key in _cuisineKeys(cuisine)) {
    final label = _cuisineLabel[key] ?? _humanize(key);
    if (!labels.contains(label)) labels.add(label);
  }
  return labels.join(', ');
}

/// Vocabulário de categorias (OSM + as que só os curados usam), na mesma
/// ordem do script. É a lista que as Rules aceitam ao criar um local.
final List<String> osmCategories = List.unmodifiable(<String>{
  ..._amenityLabel.values,
  ..._cuisineCategory.values,
  'Mercado',
  'Feira',
});
