// Importa do OpenStreetMap (Overpass API, sem chave nem cartão) os locais de
// comer/beber de Natal/RN e os 38 bairros oficiais, e grava o snapshot
// versionado `seed/osm-natal.json`. Só grava em `places` com o flag explícito
// `--seed` (mesmas variáveis de ambiente do `npm run seed`); sem ele, rode
// `npm run seed` depois (lê o snapshot, offline e reproduzível).
//
//   npm run import:osm                       # só o snapshot
//   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 GCLOUD_PROJECT=demo-naarea npm run import:osm -- --seed
//
// Dados © colaboradores do OpenStreetMap, licença ODbL 1.0 (ver seed/CREDITOS.md).
// O snapshot existente NÃO é tocado se o Overpass falhar, se vierem menos de
// 34 bairros ou menos de 80% dos locais do snapshot anterior.
const fs = require('node:fs');
const path = require('node:path');
const { buildSnapshot, checkSnapshot } = require('./osm/places');
const { AMENITIES } = require('./osm/category');

const SNAPSHOT = path.join(__dirname, 'osm-natal.json');
const USER_AGENT = 'NaArea-import-osm/1.0 (projeto academico PA2; Natal/RN)';
const ENDPOINTS = (process.env.OVERPASS_URL || 'https://overpass-api.de/api/interpreter,https://overpass.private.coffee/api/interpreter')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);

// Município de Natal: relação 301091 (IBGE 2408102) → área 3600301091.
const QUERY = `[out:json][timeout:180];
area(id:3600301091)->.natal;
nwr["amenity"~"^(${AMENITIES.join('|')})$"]["name"](area.natal);
out center tags;
rel["boundary"="administrative"]["admin_level"="10"](area.natal);
out geom;`;

async function fetchOverpass(endpoint) {
  const res = await fetch(endpoint, {
    method: 'POST',
    headers: {
      'User-Agent': USER_AGENT,
      'Content-Type': 'application/x-www-form-urlencoded',
      Accept: 'application/json',
    },
    body: new URLSearchParams({ data: QUERY }),
    signal: AbortSignal.timeout(240_000),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const json = await res.json(); // erro de parse (HTML de "too busy") → lança
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

  const snapshot = buildSnapshot(elements);
  const previous = fs.existsSync(SNAPSHOT) ? JSON.parse(fs.readFileSync(SNAPSHOT, 'utf8')) : undefined;
  const problem = checkSnapshot(snapshot, previous);
  if (problem) throw new Error(`Resposta suspeita: ${problem}; snapshot não alterado.`);
  const semBairro = snapshot.places.filter((p) => !p.neighborhood).length;

  // Escrita atômica: arquivo temporário + rename; o .tmp não fica para trás.
  const tmp = `${SNAPSHOT}.tmp`;
  try {
    fs.writeFileSync(tmp, `${JSON.stringify(snapshot, null, 2)}
`, 'utf8');
    fs.renameSync(tmp, SNAPSHOT);
  } catch (err) {
    fs.rmSync(tmp, { force: true });
    throw err;
  }

  console.log(
    `Snapshot gravado: ${snapshot.places.length} locais, ${snapshot.neighborhoods.length} bairros ` +
      `(${semBairro} sem bairro) em ${path.relative(process.cwd(), SNAPSHOT)}.`,
  );

  if (process.argv.includes('--seed')) {
    await require('./seed').seedPlaces();
  } else {
    console.log('Rode "npm run seed" (ou repita com "-- --seed") para gravar em `places`.');
  }
}

main().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
