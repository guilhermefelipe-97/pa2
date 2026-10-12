---
title: 'G2 — Catálogo do Brasil inteiro sob demanda (Photon/OSM)'
type: 'feature'
created: '2026-10-12'
status: 'done'
baseline_commit: 'c5d18bd0b6a98ea30600092e4c2b1970df58fdc4'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-g0-catalogo-osm.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-f10-estou-na-rua-agora.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** O catálogo só cobre Natal (seed de 594 locais). Fora de Natal, "Perto" e a busca do seletor ficam vazios. Importar o Brasil inteiro estoura o plano Spark (20 mil gravações/dia, 1 GiB) e o Overpass público é instável (504/timeout em testes de 2026-10-12).

**Approach:** Descoberta ao vivo pelo Photon (photon.komoot.io, dados OSM, sem chave nem cartão, com CORS): "Perto" usa `/reverse` com raio e filtros `osm_tag=amenity:*`; a busca do seletor usa `/api` com `q`, viés pela posição do usuário e filtro de amenities, restrita ao Brasil. O Firestore guarda só locais com interação: na 1ª avaliação ou salvamento, o app cria `places/osm-{n|w|r}{id}` (mesmo esquema de id do seed de Natal, sem duplicatas). Locais já no Firestore (Natal, ou criados por alguém) são mesclados aos resultados do Photon, mantendo os dados do Firestore.

## Boundaries & Constraints

**Always:** Ids `osm-[nwr][0-9]+` a partir de `osm_type`/`osm_id` do Photon. Rules: cliente logado só *cria* `places/{id}` (nunca update/delete), id no padrão acima, chaves exatas, nome 1–120 aparado, categoria do vocabulário existente, lat/lng numéricos dentro do retângulo do Brasil, `geohash` coerente em formato (9 chars base32), `source == 'osm'`, `createdBy == uid`, `createdAt == request.time`; avaliação e salvamento continuam exigindo o doc existir — o app cria o local no mesmo batch da avaliação e antes do salvamento. Categoria em pt-BR pelo mesmo mapeamento do seed (portar `category.js` para Dart, paridade por fixture compartilhada). Endpoint do Photon configurável (`--dart-define=PHOTON_URL`), `User-Agent`/`Referer` identificando o app, timeout de 10 s, cache em memória por (célula geohash 7, raio) e por consulta. Crédito "© colaboradores do OpenStreetMap" onde houver dado do Photon. Fora do Brasil (`countrycode != BR`) nada aparece.

**Ask First:** Instância própria do Photon; outra API; importar outras cidades em massa.

**Never:** Overpass ao vivo no app; Google; gravar no Firestore locais só vistos (sem interação); editar local existente pelo app.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Perto em SP | posição na Sé, 1 km | lista do Photon por distância, com categoria pt-BR e bairro (`district`) | Photon falha/timeout → "Não foi possível buscar lugares por perto" + "Tentar de novo" |
| Perto em Natal | local também no Firestore | um item só (id igual), dados do Firestore + sinal de amigos | N/A |
| Buscar | "pizzaria" em Fortaleza | resultados do Photon perto do usuário (sem posição: viés no centro do Brasil, só BR), mesclados aos do Firestore | erro → mensagem + "Tentar de novo" |
| Avaliar local novo | local só no Photon | batch: `places/osm-n123` + review; feed de amigos mostra o local | Rules negam forja → "Não foi possível salvar" |
| Salvar local novo | idem | cria `places/…` e depois `saved/…`; se o local já existir, segue | falha → reverte, como hoje |
| Corrida | dois usuários criam o mesmo local | o 2º encontra o doc existente e segue (create vira no-op) | N/A |
| Forja via SDK | id fora do padrão, coords fora do BR, chave extra, update, delete, `createdBy` de outro | negado | Rules |
| Fora do Brasil | posição em Lisboa | "Ainda não temos lugares por aqui" | N/A |
| Sem nome | feature do Photon sem `name` | descartada | N/A |

</frozen-after-approval>

## Code Map

- `firebase/firestore.rules` `match /places/{placeId}` -- hoje `write: if false`; passa a permitir `create` validado
- `firebase/seed/osm/category.js` + `tokens.js` + `geo.js` -- mapeamento de categoria, tokens e geohash a portar/compartilhar com Dart (fixtures em `firebase/tests/fixtures/`)
- `app/lib/data/repositories/place_repository.dart:18-39` -- `search`, `suggestions`, `getPlaces`, `nearby`; implementação composta: Photon (descoberta) + Firestore (persistidos), com `ensurePersisted(Place)`
- `app/lib/data/firebase/firestore_place_repository.dart` -- parse tolerante, `nearby` por geohash (continua para os persistidos)
- `app/lib/domain/geo.dart` -- geohash/haversine já existentes
- `app/lib/data/firebase/firestore_review_repository.dart` `createReview` -- batch atual (review + foto); incluir criação do local quando ainda não persistido
- `app/lib/ui/saved/saved_places_store.dart` -- salvar exige o local persistido antes
- `app/lib/ui/nearby/nearby_view_model.dart`, `app/lib/ui/review/place_picker_view_model.dart` -- consomem o repositório; mensagens de erro do Photon
- `app/lib/data/services/location_service.dart` -- posição para viés da busca (sem pedir permissão no seletor se ainda não concedida)
- `app/lib/main.dart` -- injeção e `PHOTON_URL`

## Tasks & Acceptance

**Execution:**
- [x] `firebase/tests/**` + `firebase/firestore.rules` -- testes vermelhos da criação de `places` (matriz "Forja", corrida = create em doc existente negado e app trata), depois Rules
- [x] `app/lib/domain/osm_category.dart` + fixture compartilhada + testes -- porta do mapeamento de categoria com paridade JS↔Dart
- [x] `app/lib/data/photon/photon_client.dart` + testes -- `/reverse` e `/api` com `MockClient` (parse, filtro BR, sem nome, ids, timeout, endpoint configurável)
- [x] `app/lib/data/**` + testes -- repositório composto (merge por id, cache, `ensurePersisted` idempotente) e batch review+local
- [x] `app/lib/ui/**` + testes -- Perto e seletor usando o repositório composto; erros; crédito OSM; salvar/avaliar local novo

**Acceptance Criteria:**
- Given Bianca em São Paulo, when abre "Perto", then vê lugares reais a até 300 m (ampliando se preciso) e consegue avaliar um deles; a avaliação aparece no feed de quem a segue.
- Given o mesmo local avaliado por duas pessoas, then existe um único `places/osm-…` no Firestore.

## Verification

**Commands:**
- `cd app && flutter analyze` -- expected: No issues found
- `cd app && flutter test` -- expected: todos passam
- `cd firebase && npx mocha tests/osm.test.js` -- expected: todos passam
- `cd firebase && export JAVA_HOME="/c/Program Files/Java/jdk-24" PATH="$JAVA_HOME/bin:$PATH" && firebase emulators:exec --only firestore "npm test"` -- expected: todos passam

**Manual checks (if no CLI):**
- `flutter run -d chrome` com localização simulada em SP (DevTools → Sensors): Perto lista locais; avaliar um cria `places/osm-…`.

## Spec Change Log

- Revisão 1 (patches, sem loopback): criação de `places` pelo cliente sem `searchTokens`/`nameLower` (busca de criados vem do Photon); ids sem zero à esquerda; review usa o nome do local já gravado; Perto mostra os gravados quando o Photon falha; Photon recebe só posição aproximada (célula/3 casas); 429 com backoff de 60 s; caches LRU+TTL. KEEP: ids `osm-…` iguais ao seed, local criado no mesmo batch da review, dado do Firestore vence no merge.

## Suggested Review Order

**Integridade**

- Ponto de entrada: cliente só cria local, com id OSM, coords no Brasil e autor.
  [`firestore.rules:168`](../../firebase/firestore.rules#L168)

- Review + local no mesmo batch; nome do gravado; retry seguro em corrida.
  [`firestore_review_repository.dart:34`](../../app/lib/data/firebase/firestore_review_repository.dart#L34)

- Criação idempotente do local (salvar), preservando o erro original.
  [`firestore_place_repository.dart:158`](../../app/lib/data/firebase/firestore_place_repository.dart#L158)

**Descoberta**

- Merge Photon + Firestore; gravados reservados na busca.
  [`catalog_place_repository.dart:35`](../../app/lib/data/catalog/catalog_place_repository.dart#L35)

- Perto resiliente (parcial/capped) com filtro haversine pela posição exata.
  [`catalog_place_repository.dart:106`](../../app/lib/data/catalog/catalog_place_repository.dart#L106)

- Cliente Photon: célula geohash 7 + margem, 429/backoff, cache LRU+TTL.
  [`photon_client.dart:124`](../../app/lib/data/photon/photon_client.dart#L124)

**Periféricos**

- Garantia do local antes do salvo, compartilhada com os testes.
  [`place_repository.dart:89`](../../app/lib/data/repositories/place_repository.dart#L89)
