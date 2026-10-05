// Categoria e cozinha em pt-BR a partir das tags `amenity` e `cuisine` do OSM.

const AMENITIES = [
  'restaurant',
  'fast_food',
  'pub',
  'bar',
  'cafe',
  'ice_cream',
  'food_court',
  'biergarten',
];

const AMENITY_LABEL = {
  restaurant: 'Restaurante',
  fast_food: 'Lanchonete',
  pub: 'Pub',
  bar: 'Bar',
  cafe: 'Café',
  ice_cream: 'Sorveteria',
  food_court: 'Praça de alimentação',
  biergarten: 'Cervejaria',
};

// Cozinhas que viram a própria categoria (a 1ª reconhecida vence).
const CUISINE_CATEGORY = {
  pizza: 'Pizzaria',
  burger: 'Hamburgueria',
  sushi: 'Japonês',
  japanese: 'Japonês',
  steak_house: 'Churrascaria',
  barbecue: 'Churrascaria',
  churrascaria: 'Churrascaria',
  seafood: 'Frutos do mar',
  fish: 'Frutos do mar',
  ice_cream: 'Sorveteria',
  coffee_shop: 'Café',
  bakery: 'Padaria',
  tapioca: 'Tapiocaria',
  acai: 'Açaí',
  'açaí': 'Açaí',
  regional: 'Comida regional',
  brazilian: 'Comida brasileira',
  italian: 'Italiano',
  chinese: 'Chinês',
  arab: 'Árabe',
  mexican: 'Mexicano',
  vegetarian: 'Vegetariano',
  vegan: 'Vegano',
};

// Rótulos de COZINHA (o que se come), independentes dos de categoria (o tipo
// de lugar). Sinônimos apontam para o mesmo rótulo e são deduplicados.
const CUISINE_LABEL = {
  pizza: 'Pizza',
  burger: 'Hambúrguer',
  sushi: 'Sushi',
  japanese: 'Japonesa',
  chinese: 'Chinesa',
  korean: 'Coreana',
  thai: 'Tailandesa',
  indian: 'Indiana',
  asian: 'Asiática',
  italian: 'Italiana',
  french: 'Francesa',
  portuguese: 'Portuguesa',
  peruvian: 'Peruana',
  mexican: 'Mexicana',
  arab: 'Árabe',
  lebanese: 'Árabe',
  international: 'Internacional',
  regional: 'Comida regional',
  local: 'Comida regional',
  brazilian: 'Brasileira',
  steak_house: 'Churrasco',
  barbecue: 'Churrasco',
  churrascaria: 'Churrasco',
  seafood: 'Frutos do mar',
  fish: 'Peixe',
  chicken: 'Frango',
  sandwich: 'Sanduíche',
  hot_dog: 'Cachorro-quente',
  pastel: 'Pastel',
  crepe: 'Crepe',
  tapioca: 'Tapioca',
  kebab: 'Kebab',
  vegetarian: 'Vegetariana',
  vegan: 'Vegana',
  buffet: 'Bufê',
  ice_cream: 'Sorvete',
  acai: 'Açaí',
  'açaí': 'Açaí',
  coffee_shop: 'Café',
  cafe: 'Café',
  coffee: 'Café',
  bakery: 'Padaria',
  cake: 'Bolos',
  dessert: 'Sobremesas',
  donut: 'Donuts',
  juice: 'Sucos',
};

/** Valores de `cuisine` ("pizza;italian" → ["pizza", "italian"]). */
function cuisineKeys(cuisine) {
  return String(cuisine ?? '')
    .split(';')
    .map((c) => c.trim().toLowerCase())
    .filter(Boolean);
}

function humanize(key) {
  const s = key.replace(/_/g, ' ');
  return s.charAt(0).toUpperCase() + s.slice(1);
}

/** Categoria pt-BR: a cozinha refina restaurante/lanchonete; o resto segue o `amenity`. */
function categoryFor(amenity, cuisine) {
  const base = AMENITY_LABEL[amenity] ?? 'Local';
  if (amenity !== 'restaurant' && amenity !== 'fast_food') return base;
  for (const key of cuisineKeys(cuisine)) {
    if (CUISINE_CATEGORY[key]) return CUISINE_CATEGORY[key];
  }
  return base;
}

/** Cozinha legível ("pizza;italian" → "Pizza, Italiano"); "" se ausente. */
function cuisineLabel(cuisine) {
  const labels = [];
  for (const key of cuisineKeys(cuisine)) {
    const label = CUISINE_LABEL[key] ?? humanize(key);
    if (!labels.includes(label)) labels.push(label);
  }
  return labels.join(', ');
}

/** Vocabulário de categorias (OSM + as que só os curados usam). */
const CATEGORIES = [
  ...new Set([...Object.values(AMENITY_LABEL), ...Object.values(CUISINE_CATEGORY), 'Mercado', 'Feira']),
];

module.exports = { AMENITIES, CATEGORIES, categoryFor, cuisineLabel };
