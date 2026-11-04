// Importa do OpenStreetMap (Overpass API, sem chave nem cartão) os locais de
// comer/beber dos municípios da Grande Natal (fora Natal, que tem o próprio
// snapshot) e grava `seed/osm-grande-natal.json`, com a cidade de cada local.
// Só grava em `places` com `--seed` (mesmas variáveis de ambiente do
// `npm run seed`); sem ele, rode `npm run seed` depois.
//
//   npm run import:osm:grande-natal
//   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 GCLOUD_PROJECT=demo-naarea npm run import:osm:grande-natal -- --seed
//
// Dados © colaboradores do OpenStreetMap, licença ODbL 1.0 (ver seed/CREDITOS.md).
// O snapshot existente NÃO é tocado se o Overpass falhar, se faltar algum
// município, se algum vier sem locais ou se vierem menos de 80% dos locais
// do snapshot anterior.
const fs = require('node:fs');
const path = require('node:path');
const { buildMetroSnapshot, checkMetroSnapshot } = require('./osm/places');
const { AMENITIES } = require('./osm/category');

const SNAPSHOT = path.join(__dirname, 'osm-grande-natal.json');
const USER_AGENT = 'NaArea-import-osm/1.0 (projeto academico PA2; Natal/RN)';
const ENDPOINTS = (process.env.OVERPASS_URL || 'https://overpass-api.de/api/interpreter,https://overpass.private.coffee/api/interpreter')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);

/** Municípios (nome no OSM) além de Natal. Para incluir outro, acrescente aqui. */
const CITIES = [
  'Ceará-Mirim',
  'Extremoz',
  'Macaíba',
  'Nísia Floresta',
  'Parnamirim',
  'São Gonçalo do Amarante',
  'São José de Mipibu',
];

function escapeRegex(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// Municípios (admin_level 8) dentro do RN; para cada um, a própria área (com
// o nome), os locais e os bairros que existirem no OSM.
const QUERY = `[out:json][timeout:240];
area["ISO3166-2"="BR-RN"]["admin_level"="4"]->.rn;
area["boundary"="administrative"]["admin_level"="8"]["name"~"^(${CITIES.map(escapeRegex).join('|')})$"](area.rn)->.cidades;
foreach.cidades->.c(
  .c out tags;
  nwr["amenity"~"^(${AMENITIES.join('|')})$"]["name"](area.c);
  out center tags;
  rel["boundary"="administrative"]["admin_level"="10"](area.c);
  out geom;
);`;

async function fetchOverpass(endpoint) {
  const res = await fetch(endpoint, {
    method: 'POST',
    headers: {
      'User-Agent': USER_AGENT,
      'Content-Type': 'application/x-www-form-urlencoded',
      Accept: 'application/json',
    },
    body: new URLSearchParams({ data: QUERY }),
    signal: AbortSignal.timeout(300_000),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const json = await res.json();
  if (!Array.isArray(json.elements)) throw new Error('resposta sem "elements"');
  if (json.remark) throw new Error(`Overpass: ${json.remark}`);
  return json.elements;
}

async function main() {
  let elements;
  const errors = [];
  for (const endpoint of ENDPOINTS) {
    try {
      console.log(`Consultando ${endpoint}...`);
      elements = await fetchOverpass(endpoint);
      break;
    } catch (err) {
      errors.push(`${endpoint}: ${err.message || err}`);
    }
  }
  if (!elements) {
    throw new Error(`Overpass falhou; snapshot não alterado.\n  ${errors.join('\n  ')}`);
  }

  const snapshot = buildMetroSnapshot(elements);
  const previous = fs.existsSync(SNAPSHOT) ? JSON.parse(fs.readFileSync(SNAPSHOT, 'utf8')) : undefined;
  const problem = checkMetroSnapshot(snapshot, previous, CITIES);
  if (problem) throw new Error(`Resposta suspeita: ${problem}; snapshot não alterado.`);

  const tmp = `${SNAPSHOT}.tmp`;
  try {
    fs.writeFileSync(tmp, `${JSON.stringify(snapshot, null, 2)}\n`, 'utf8');
    fs.renameSync(tmp, SNAPSHOT);
  } catch (err) {
    fs.rmSync(tmp, { force: true });
    throw err;
  }

  console.log(`Snapshot gravado: ${snapshot.places.length} locais em ${path.relative(process.cwd(), SNAPSHOT)}.`);
  for (const c of snapshot.cities) {
    console.log(`  ${c.name}: ${c.places} locais, ${c.neighborhoods} bairros no OSM`);
  }

  if (process.argv.includes('--seed')) {
    await require('./seed').seedPlaces();
  } else {
    console.log('Rode "npm run seed" (ou repita com "-- --seed") para gravar em `places`.');
  }
}

module.exports = { CITIES, QUERY };

if (require.main === module) {
  main().catch((err) => {
    console.error(err.message || err);
    process.exit(1);
  });
}
