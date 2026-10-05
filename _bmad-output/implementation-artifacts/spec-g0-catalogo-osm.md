---
title: 'G0 — Catálogo de locais de Natal importado do OpenStreetMap'
type: 'feature'
created: '2026-10-05'
status: 'done'
baseline_commit: 'e33de3e981dba12a7468485c01247489756e8c46'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-onda-1-fundacao-avaliacao-feed.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-feed-rico-fotos-comentario-visual.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Os locais vêm de um seed manual de 20 itens. Não escala, não tem coordenada (bloqueia F10) e o seletor lê a coleção inteira a cada abertura.

**Approach:** Script Node importa do OpenStreetMap (Overpass, sem cartão nem chave) todos os locais de comer/beber de Natal (~650), com bairro calculado por polígono dos 38 bairros oficiais do OSM, coordenadas, geohash, cozinha, endereço e horário bruto. Gera um snapshot versionado e o grava em `places` via Admin SDK. O app passa a buscar por tokens (sem ler a coleção inteira) e a ler só os locais que aparecem no feed. Google Places foi descartado (exige cartão; Demo Key não traz fotos).

## Boundaries & Constraints

**Always:** Crédito "© OpenStreetMap" (ODbL) no seletor e no detalhe, e em `firebase/seed/CREDITOS.md`. Os 20 locais curados mantêm o id (reviews existentes apontam para eles): quando há casamento único por nome normalizado, recebem os dados do OSM e o duplicado do OSM não é criado. Import idempotente e reproduzível offline a partir do snapshot. `places` continua só-leitura para o cliente. Nenhuma tela lê `places` inteira.

**Ask First:** Outra fonte de dados paga ou com chave. Mudar o schema de `reviews`.

**Never:** Google Places/Demo Key; scraping; mapa embutido; horário interpretado (é F20); foto do usuário (spec próprio).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Importar | Overpass responde | `osm-natal.json` com id `osm-{n|w|r}{id}`, nome, categoria pt-BR, bairro, lat/lng, geohash (9), tokens | Overpass falha → aborta sem tocar no snapshot |
| Fora dos bairros | ponto sem polígono | `neighborhood` = `addr:suburb` ou "" | N/A |
| Curado duplicado | "Mangai" no OSM e no seed | doc `mangai-natal` ganha lat/lng/osmId; sem doc `osm-…` | ambíguo (2+ casamentos) → mantém os dois e loga |
| Buscar | "camar" | até 20 locais cujo token começa com "camar", sem acento/caixa | erro → mensagem + "Tentar de novo" |
| Busca curta | 0–1 caractere | sugestões: locais curados com foto | N/A |
| Feed | reviews de 12 locais | 1 leitura por local (`whereIn` de id em lotes de 30), cache em memória | local ausente → Place mínimo com `placeName` (comportamento atual) |

</frozen-after-approval>

## Code Map

- `firebase/seed/seed.js` + `places.json` + `CREDITOS.md` -- seed atual (20 curados, Admin SDK, batch 500, idempotente); evolui para ler o snapshot
- `scripts/seed-emulador.ps1` -- roda `npm run seed` no emulador
- `app/lib/domain/models/place.dart` -- adicionar `lat`, `lng`, `cuisine`, `address`, `openingHours` (bruto), `source` (`osm`|`curated`)
- `app/lib/data/repositories/place_repository.dart` -- `listPlaces()` vira `search(query)`, `suggestions()`, `getPlaces(ids)`
- `app/lib/data/firebase/firestore_place_repository.dart:12` -- parse tolerante (`_fromData`) reaproveitado
- `app/lib/ui/review/place_picker_view_model.dart` -- `_normalize` (folding de acento) vai para `app/lib/domain/search_tokens.dart`, compartilhado com o script por regras idênticas
- `app/lib/ui/feed/feed_view_model.dart:118` -- `_placesById` de `listPlaces()` → `getPlaces(ids do feed)`
- `app/lib/ui/place/place_detail_view.dart:30` -- subtítulo; adicionar endereço, cozinha e crédito OSM
- `app/test/support/fakes.dart:132` -- `FakePlaceRepository.listPlaces`
- `firebase/firestore.indexes.json` -- índice `places(searchTokens CONTAINS, nameLower ASC)`

## Tasks & Acceptance

**Execution:**
- [x] `firebase/seed/osm/*.js` + `firebase/tests/osm.test.js` -- funções puras testadas primeiro: normalização/tokens (prefixos ≥2 de cada palavra, sem acento), categoria pt-BR por `amenity`+`cuisine`, point-in-polygon (ray casting, multipolígono), geohash, casamento com curados
- [x] `firebase/seed/importar-osm.js` -- Overpass (User-Agent próprio): locais `amenity ∈ restaurant|fast_food|pub|bar|cafe|ice_cream|food_court|biergarten` com nome + polígonos `admin_level=10` de Natal → `firebase/seed/osm-natal.json`
- [x] `firebase/seed/seed.js` + `package.json` -- grava curados + snapshot com `nameLower`, `searchTokens`, `updatedAt`; script `import:osm`
- [x] `app/lib/domain/**` + testes -- `Place` com campos novos; `searchTokens`/`normalizeQuery` puros
- [x] `app/lib/data/**` + testes -- `search` (`array-contains` do token normalizado + `orderBy nameLower`, limit 20), `suggestions` (curados com foto), `getPlaces` (lotes de 30, cache)
- [x] `app/lib/ui/**` + testes -- seletor: busca com debounce 300ms, skeleton, chips de categoria, vazio "Nenhum local com esse nome", crédito OSM; feed lê só seus locais; detalhe mostra endereço, cozinha e crédito
- [x] `firebase/firestore.indexes.json`, `app/README.md` -- índice e passo a passo do import

**Acceptance Criteria:**
- Given emulador com seed, when busco "camarões" no seletor, then aparecem os locais correspondentes com bairro e consigo avaliar.
- Given o feed carregado, when inspeciono as leituras, then nenhuma consulta lê `places` sem filtro.
- Given `npm run import:osm` rodado duas vezes, then o snapshot e a coleção ficam idênticos (idempotente).

## Design Notes

Tokens: `"Camarões Potiguar"` → `ca, cam, …, camaroes, po, pot, …, potiguar`. Consulta usa só o 1º termo digitado (`array-contains` aceita um valor) e filtra os demais termos no cliente. ~650 docs × ~25 tokens cabe folgado no Spark.

## Verification

**Commands:**
- `cd app && flutter analyze` -- expected: No issues found
- `cd app && flutter test` -- expected: todos passam
- `cd firebase && npx mocha tests/osm.test.js` -- expected: todos passam
- `cd firebase && export JAVA_HOME="/c/Program Files/Java/jdk-24" PATH="$JAVA_HOME/bin:$PATH" && firebase emulators:exec --only firestore "npm test"` -- expected: todos passam

## Suggested Review Order

**Import do OpenStreetMap**

- Ponto de entrada: baixa, valida o snapshot e só grava no Firestore com `--seed`.
  [`importar-osm.js:51`](../../firebase/seed/importar-osm.js#L51)

- Sanidade contra resposta parcial do Overpass (bairros e queda de volume).
  [`importar-osm.js:69`](../../firebase/seed/importar-osm.js#L69)

- Elementos OSM → snapshot; dedupe node/way pelo geohash.
  [`places.js:84`](../../firebase/seed/osm/places.js#L84)

- Bairro por polígono (ray casting em multipolígono).
  [`geo.js:13`](../../firebase/seed/osm/geo.js#L13)

- Curado ↔ OSM: nome + bairro compatível, ou `osmId` forçado.
  [`match.js:24`](../../firebase/seed/osm/match.js#L24)

**Seed idempotente**

- Compara forma canônica e grava só o que mudou; `updatedAt` estável.
  [`seed.js:67`](../../firebase/seed/seed.js#L67)

**Busca por tokens (paridade JS ↔ Dart)**

- Folding de acento + NFD; prefixos ≥2 por palavra.
  [`tokens.js:49`](../../firebase/seed/osm/tokens.js#L49)

- Mesmas regras no app, travadas pela fixture compartilhada.
  [`search_tokens.dart:35`](../../app/lib/domain/search_tokens.dart#L35)

- Termo mais longo vai ao servidor; demais filtrados no cliente.
  [`firestore_place_repository.dart:39`](../../app/lib/data/firebase/firestore_place_repository.dart#L39)

- Feed lê só seus locais: lotes de 30, cache de ausentes e em voo.
  [`firestore_place_repository.dart:66`](../../app/lib/data/firebase/firestore_place_repository.dart#L66)

**UI**

- Debounce e descarte de respostas antigas no seletor.
  [`place_picker_view_model.dart:98`](../../app/lib/ui/review/place_picker_view_model.dart#L98)

- Guarda contra toque duplo ao abrir a avaliação.
  [`place_picker_view.dart:29`](../../app/lib/ui/review/place_picker_view.dart#L29)

- Detalhe com endereço, cozinha e crédito ODbL.
  [`place_detail_view.dart:230`](../../app/lib/ui/place/place_detail_view.dart#L230)

**Periféricos**

- Índice composto exigido pela busca em produção.
  [`firestore.indexes.json:15`](../../firebase/firestore.indexes.json#L15)

- Modelo com coordenadas, cozinha, endereço e origem.
  [`place.dart:53`](../../app/lib/domain/models/place.dart#L53)

- Seed testado no emulador (idempotência, remoção de campo).
  [`seed.test.js:1`](../../firebase/tests/seed.test.js#L1)
