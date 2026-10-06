---
title: 'F10 — "Estou na rua agora": lugares a 300 m, decisão em 1 toque'
type: 'feature'
created: '2026-10-05'
status: 'done'
baseline_commit: 'c195223be30e754860f7c6cdc107512cc65be434'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-g0-catalogo-osm.md'
  - '{project-root}/docs/lean-inception/jornada-bianca.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** O momento de uso mais frequente — já na rua, decidir onde comer agora — não tem tela. Passo 6 do Toni e 7 da Bianca.

**Approach:** Nova aba "Perto" (Amigos · Perto · Quero ir · Pessoas). Ao abrir, pede a localização uma vez e lista os locais do catálogo num raio de 300 m, por distância, usando consulta por faixas de geohash no Firestore. No topo, um card "Sugestão" decide por ela: o local mais perto que algum amigo avaliou; sem nenhum, o mais perto salvo no "Quero ir"; sem nenhum, o mais perto. Chips de raio 300 m · 1 km · 3 km para ampliar. Cada item mostra distância, categoria, marcador "Quero ir" e, se houver, "Ana foi aqui". Toque abre o detalhe. "Aberto agora" fica para F20.

## Boundaries & Constraints

**Always:** Localização usada só em memória para montar a consulta; nunca gravada nem enviada além dos prefixos de geohash. Permissão pedida no contexto da aba, com explicação antes do pedido do sistema. Consultas: no máximo 9 faixas por raio, `limit` por faixa, filtro final por distância real (haversine) no cliente. Cache dos resultados por (geohash de precisão 7 da posição, raio) durante a sessão. Sinal de amigos vem das avaliações de quem o usuário segue (mesma fonte do feed, sem ler `reviews` inteira). Puxar para atualizar pega nova posição. Acessível: distância falada ("a 120 metros").

**Ask First:** Mapa; localização em segundo plano; ordenar por nota.

**Never:** Gravar localização; Google APIs; "aberto agora" (F20); rotas/direções embutidas.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Primeira vez | permissão nunca pedida | tela explicativa "Para mostrar o que está perto de você" + "Usar minha localização" → pedido do sistema | N/A |
| Negada | usuário nega / negado para sempre | mensagem + "Abrir configurações" (para sempre) ou "Tentar de novo" | N/A |
| GPS desligado | serviço de localização off | "Ative a localização do aparelho" + tentar de novo | N/A |
| Lista | Ponta Negra, 6 locais em 300 m | ordenados por distância com "80 m", "250 m"; locais a 301 m fora | rede falha → mensagem + "Tentar de novo" |
| Sugestão | Ana avaliou o 3º mais perto | card Sugestão = 3º, com "Ana foi aqui" e botão "Ver lugar" | N/A |
| Vazio | nada em 300 m | "Nada a 300 m" + botão "Ampliar para 1 km" | N/A |
| Ampliar | chip 1 km | refaz consulta; Sugestão recalculada | N/A |
| Fora de Natal | posição a 50 km | "Ainda não temos lugares por aqui" | N/A |
| Local sem coordenada | curado sem lat/lng | nunca aparece em Perto | N/A |
| Distância | 950 m / 1.240 m | "950 m" / "1,2 km" | N/A |

</frozen-after-approval>

## Code Map

- `firebase/seed/osm/geo.js:63` -- `geohash()` (precisão 9) já usado no snapshot; garantir `geohash` em todo doc com lat/lng em `firebase/seed/seed.js:147-162` (curados casados incluídos) + teste do seed
- `app/lib/domain/models/place.dart` -- já tem `lat`/`lng`; adicionar `geohash`
- `app/lib/data/repositories/place_repository.dart` + `firestore_place_repository.dart` -- adicionar `nearby(lat, lng, radiusMeters)`; reaproveitar parse tolerante e cache por id
- `app/lib/domain/geo.dart` (novo) -- geohash encode, `geohashQueryBounds(center, radius)` (algoritmo do geofire-common), haversine, `formatDistance`
- `app/lib/data/repositories/review_repository.dart` -- `fetchReviewsByAuthors` para o sinal "foi aqui"; `UserRepository.getFollowing`
- `app/lib/ui/saved/saved_places_store.dart` -- `isSaved` para a sugestão e o marcador
- `app/lib/ui/core/app_shell.dart:31-45` + `app/lib/routing/router.dart` -- nova aba "Perto" (ícone `near_me`), 2ª posição
- `app/lib/ui/core/save_button.dart`, `app/lib/ui/feed/widgets/place_photo.dart` -- reuso nos itens
- Pacote: `geolocator` (Android/iOS/web); permissões `ACCESS_COARSE_LOCATION`/`ACCESS_FINE_LOCATION` e `NSLocationWhenInUseUsageDescription` em pt-BR

## Tasks & Acceptance

**Execution:**
- [x] `firebase/seed/**` + testes -- `geohash` garantido em todo doc com coordenadas
- [x] `app/lib/domain/geo.dart` + testes -- encode, bounds (comparar com vetores conhecidos do geofire-common), haversine, formatação
- [x] `app/lib/data/**` + testes -- `nearby` (faixas + filtro + ordenação), serviço `LocationService` abstrato sobre `geolocator` com estados (ok, negado, negado para sempre, serviço off)
- [x] `app/lib/ui/nearby/**` + testes -- `NearbyViewModel` (permissão, raio, sugestão, cache, refresh), `NearbyView` (explicação, lista, sugestão, chips, vazio, erros)
- [x] `app/lib/ui/core/app_shell.dart`, `app/lib/routing/**`, plataformas + testes -- aba e permissões

**Acceptance Criteria:**
- Given Bianca em Ponta Negra com localização liberada, when abre "Perto", then em 1 toque no card Sugestão chega ao detalhe do lugar mais perto que um amigo avaliou.
- Given nada em 300 m, when toca "Ampliar para 1 km", then vê os locais até 1 km.

## Verification

**Commands:**
- `cd app && flutter analyze` -- expected: No issues found
- `cd app && flutter test` -- expected: todos passam
- `cd firebase && npx mocha tests/osm.test.js` -- expected: todos passam
- `cd firebase && export JAVA_HOME="/c/Program Files/Java/jdk-24" PATH="$JAVA_HOME/bin:$PATH" && firebase emulators:exec --only firestore "npm test"` -- expected: todos passam

## Spec Change Log

- Revisão adversarial pulada por decisão do usuário em 2026-10-05 (commit direto com testes passando).
