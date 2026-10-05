// Casamento dos locais curados (places.json) com o snapshot do OSM e montagem
// dos documentos finais de `places`.
const { nameLower, searchTokens } = require('./tokens');

/** Campos que o curado recebe do OSM (nome, categoria, bairro e foto do curado ficam). */
const FROM_OSM = ['osmId', 'lat', 'lng', 'geohash', 'cuisine', 'address', 'openingHours'];

const byId = (a, b) => (a < b ? -1 : a > b ? 1 : 0);

/** Bairros compatíveis: iguais (sem acento/caixa) ou um dos dois ausente. */
function sameNeighborhood(a, b) {
  const x = nameLower(a ?? '');
  const y = nameLower(b ?? '');
  return !x || !y || x === y;
}

/**
 * Casa cada curado com um local do OSM.
 * - `osmId` no curado ("node/123") força o casamento;
 * - senão: mesmo nome normalizado (não vazio) e bairro compatível;
 * - casamento único (nos dois sentidos) → merge; 2+ candidatos, ou um local
 *   do OSM disputado por 2+ curados → ambíguo (mantém os dois).
 */
function matchCurated(curated, osmPlaces, log = () => {}) {
  const osmByOsmId = new Map(osmPlaces.map((p) => [p.osmId, p]));
  const osmByKey = new Map();
  for (const p of osmPlaces) {
    const k = nameLower(p.name);
    if (!k) continue;
    if (!osmByKey.has(k)) osmByKey.set(k, []);
    osmByKey.get(k).push(p);
  }

  const matches = new Map(); // curatedId → osm place
  const ambiguous = [];
  const forced = new Set(); // ids do OSM já tomados por osmId explícito
  const missingForced = new Set(); // curados com osmId que não existe no snapshot

  for (const c of curated) {
    if (!c.osmId) continue;
    const p = osmByOsmId.get(c.osmId);
    if (p) {
      matches.set(c.id, p);
      forced.add(p.id);
    } else {
      missingForced.add(c.id);
      log(`osmId ${c.osmId} de "${c.name}" (${c.id}) não está no snapshot — sem casamento`);
    }
  }

  const tentative = new Map(); // curatedId → osm place
  const claims = new Map(); // osm id → [curatedId]
  for (const c of curated) {
    if (c.osmId) continue;
    const k = nameLower(c.name);
    if (!k) continue;
    const candidates = (osmByKey.get(k) ?? [])
      .filter((p) => !forced.has(p.id) && sameNeighborhood(p.neighborhood, c.neighborhood))
      .sort((a, b) => byId(a.id, b.id));
    if (candidates.length === 0) continue;
    if (candidates.length > 1) {
      ambiguous.push({ curatedId: c.id, name: c.name, osmIds: candidates.map((p) => p.id) });
      continue;
    }
    const p = candidates[0];
    tentative.set(c.id, p);
    claims.set(p.id, [...(claims.get(p.id) ?? []), c.id]);
  }
  for (const c of curated) {
    const p = tentative.get(c.id);
    if (!p) continue;
    if (claims.get(p.id).length > 1) {
      ambiguous.push({ curatedId: c.id, name: c.name, osmIds: [p.id] });
    } else {
      matches.set(c.id, p);
    }
  }
  return { matches, ambiguous, missingForced };
}

function withSearchFields(doc) {
  return { ...doc, nameLower: nameLower(doc.name), searchTokens: searchTokens(doc.name) };
}

function stripEmpty(doc) {
  const out = {};
  for (const [k, v] of Object.entries(doc)) {
    if (v === '' || v === null || v === undefined) continue;
    out[k] = v;
  }
  return out;
}

/**
 * Documentos finais de `places` (sem `updatedAt`), ordenados por id:
 * curados (com dados do OSM quando casam) + OSM não casados.
 */
function buildPlaceDocs(curated, snapshot, log = () => {}) {
  const osmPlaces = snapshot?.places ?? [];
  const { matches, ambiguous } = matchCurated(curated, osmPlaces, log);
  for (const a of ambiguous) {
    log(`ambíguo: "${a.name}" (${a.curatedId}) casa com ${a.osmIds.join(', ')} — mantidos separados`);
  }
  const consumed = new Set([...matches.values()].map((p) => p.id));

  const docs = [];
  for (const c of curated) {
    const osm = matches.get(c.id);
    const { osmId: _forced, ...base } = c; // osmId só fica se o casamento existir
    const merged = { ...base, source: 'curated' };
    if (osm) {
      for (const k of FROM_OSM) if (osm[k] !== undefined && osm[k] !== '') merged[k] = osm[k];
      if (!merged.neighborhood) merged.neighborhood = osm.neighborhood;
    }
    docs.push(stripEmpty(withSearchFields(merged)));
  }
  for (const p of osmPlaces) {
    if (consumed.has(p.id)) continue;
    docs.push(stripEmpty(withSearchFields({ ...p, source: 'osm' })));
  }
  docs.sort((a, b) => byId(a.id, b.id));
  return { docs, matched: matches.size, ambiguous };
}

module.exports = { matchCurated, buildPlaceDocs };
