// Conversão da resposta do Overpass para o snapshot `osm-natal.json`.
const { AMENITIES, categoryFor, cuisineLabel } = require('./category');
const { neighborhoodAt, geohash } = require('./geo');
const { nameLower } = require('./tokens');

const TYPE_PREFIX = { node: 'n', way: 'w', relation: 'r' };

/** `osm-n123`, `osm-w456`, `osm-r789`. */
function placeId(el) {
  const p = TYPE_PREFIX[el.type];
  if (!p) throw new Error(`tipo OSM desconhecido: ${el.type}`);
  return `osm-${p}${el.id}`;
}

/** 7 casas (~1 cm) bastam e deixam o snapshot estável entre execuções. */
function round7(n) {
  return Math.round(n * 1e7) / 1e7;
}

function coords(el) {
  if (typeof el.lat === 'number' && typeof el.lon === 'number') return { lat: el.lat, lng: el.lon };
  if (el.center && typeof el.center.lat === 'number' && typeof el.center.lon === 'number') {
    return { lat: el.center.lat, lng: el.center.lon };
  }
  return null;
}

/** Bairros (relações `admin_level=10` com `out geom`) → {name, lines}. */
function parseNeighborhoods(elements) {
  const out = [];
  for (const el of elements) {
    if (el.type !== 'relation' || el.tags?.admin_level !== '10' || !el.tags?.name) continue;
    const lines = (el.members ?? [])
      .filter((m) => m.type === 'way' && Array.isArray(m.geometry) && m.geometry.length > 1)
      .map((m) => m.geometry.map((g) => ({ lat: g.lat, lng: g.lon })));
    if (lines.length) out.push({ name: el.tags.name.trim(), lines });
  }
  return out.sort((a, b) => a.name.localeCompare(b.name, 'pt-BR'));
}

function address(tags) {
  const street = (tags['addr:street'] ?? '').trim();
  const number = (tags['addr:housenumber'] ?? '').trim();
  if (!street) return '';
  return number ? `${street}, ${number}` : street;
}

/** Local OSM → registro do snapshot; null se não for local de comer/beber válido. */
function toPlace(el, neighborhoods) {
  const tags = el.tags ?? {};
  const name = (tags.name ?? '').trim();
  if (!name || !AMENITIES.includes(tags.amenity)) return null;
  const c = coords(el);
  if (!c) return null;
  const lat = round7(c.lat);
  const lng = round7(c.lng);
  const neighborhood = neighborhoodAt({ lat, lng }, neighborhoods) ?? (tags['addr:suburb'] ?? '').trim();
  return {
    id: placeId(el),
    osmId: `${el.type}/${el.id}`,
    name,
    category: categoryFor(tags.amenity, tags.cuisine),
    cuisine: cuisineLabel(tags.cuisine),
    neighborhood,
    city: 'Natal',
    address: address(tags),
    openingHours: (tags.opening_hours ?? '').trim(),
    lat,
    lng,
    geohash: geohash(lat, lng, 9),
  };
}

const TYPE_RANK = { way: 0, relation: 1, node: 2 };

function preferred(a, b) {
  const ra = TYPE_RANK[a.osmId.split('/')[0]];
  const rb = TYPE_RANK[b.osmId.split('/')[0]];
  if (ra !== rb) return ra < rb;
  return a.id < b.id;
}

/** Resposta do Overpass → snapshot determinístico (ordenado por id). */
function buildSnapshot(elements) {
  const neighborhoods = parseNeighborhoods(elements);
  // O mesmo local às vezes está mapeado como ponto (node) e como prédio
  // (way): mesmo nome normalizado + mesma célula de geohash de 7 (~150 m)
  // vira um só, preferindo o way (depois relation, depois node; empate: id).
  const byKey = new Map();
  for (const el of elements) {
    if (el.type === 'relation' && el.tags?.admin_level === '10') continue;
    const p = toPlace(el, neighborhoods);
    if (!p) continue;
    const key = `${nameLower(p.name)}|${p.geohash.slice(0, 7)}`;
    const current = byKey.get(key);
    if (!current || preferred(p, current)) byKey.set(key, p);
  }
  const places = [...byKey.values()].sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  return {
    source: 'OpenStreetMap',
    attribution: '© OpenStreetMap contributors',
    license: 'ODbL 1.0 (https://opendatacommons.org/licenses/odbl/)',
    neighborhoods: neighborhoods.map((n) => n.name),
    places,
  };
}

const MIN_NEIGHBORHOODS = 34; // Natal tem 38; menos = resposta incompleta
const MIN_RATIO = 0.8; // queda de 20%+ em relação ao snapshot anterior = suspeita

/** Motivo para NÃO gravar o snapshot novo, ou null se ele parece completo. */
function checkSnapshot(snapshot, previous) {
  const n = snapshot.places.length;
  const b = snapshot.neighborhoods.length;
  if (b < MIN_NEIGHBORHOODS) return `só ${b} bairros (mínimo ${MIN_NEIGHBORHOODS})`;
  if (n === 0) return 'nenhum local';
  const before = previous?.places?.length ?? 0;
  if (before > 0 && n < before * MIN_RATIO) {
    return `${n} locais contra ${before} no snapshot anterior (mínimo ${Math.ceil(before * MIN_RATIO)})`;
  }
  return null;
}

module.exports = { placeId, parseNeighborhoods, toPlace, buildSnapshot, checkSnapshot };
