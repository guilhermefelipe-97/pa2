---
title: 'F11 — "Quero ir": salvar local em 1 toque, privado'
type: 'feature'
created: '2026-10-05'
status: 'done'
baseline_commit: 'bbbff0d3dff123f4c88877c1be7ad9be9de28008'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-g0-catalogo-osm.md'
  - '{project-root}/docs/lean-inception/jornada-bianca.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Passo 3 da jornada da Bianca ("Depois eu vejo"): ela vê um lugar no feed e não tem como guardá-lo sem avaliar. Último cartão pendente da Onda 1.

**Approach:** Botão "Quero ir" (marcador) no card do feed, no detalhe do local e no resultado do seletor — 1 toque, otimista, com "Desfazer". Salvos ficam em `users/{uid}/saved/{placeId}`, legíveis só pelo dono. Nova aba "Quero ir" numa barra de navegação inferior (Amigos · Quero ir · Pessoas) lista os salvos, do mais recente ao mais antigo. O detalhe do local passa a abrir por `placeId` sozinho (carrega local e avaliações dos amigos), para ser alcançável a partir dos salvos.

## Boundaries & Constraints

**Always:** Fricção zero: nenhum diálogo, nenhum campo, nenhum login extra. Privado por padrão: Rules negam leitura/escrita a terceiros. Estado do botão consistente entre feed, detalhe, seletor e aba (fonte única: um repositório observável com o conjunto de ids salvos, carregado uma vez por sessão). Falha ao salvar/remover reverte o otimismo e mostra "Não foi possível salvar". Acessível: botão com rótulo "Salvar em Quero ir"/"Remover de Quero ir" e `toggled`. Design no padrão do app (tema existente, animação curta no marcador).

**Ask First:** Tornar salvos visíveis a outras pessoas. Contadores públicos de salvamentos.

**Never:** Listas nomeadas (F12); compartilhar (F13/F21); notas privadas no salvo; avaliar a partir do salvo de forma diferente do fluxo atual.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Salvar | toque no marcador vazio | ícone preenche já; doc `saved/{placeId}` com só `createdAt` = servidor; SnackBar "Salvo em Quero ir" + "Desfazer" | falha → volta a vazio + "Não foi possível salvar" |
| Remover | toque no marcador cheio | ícone esvazia já; doc apagado; SnackBar com "Desfazer" | falha → volta a cheio |
| Toques rápidos | 3 toques seguidos | estado final = último toque; nunca 2 escritas concorrentes para o mesmo id | idem |
| Forja via SDK | salvar em outro uid, campo extra, `createdAt` do cliente, local inexistente, update | negado | Rules |
| Aba vazia | nada salvo | ilustração + "Toque no marcador de um lugar para guardar aqui" + botão "Ver o que os amigos foram" | N/A |
| Aba | 3 salvos | cards compactos (foto/fallback, nome, bairro · categoria, "salvo há 2 h"), mais recente primeiro; toque abre o detalhe | erro de rede → mensagem + "Tentar de novo" |
| Local sumiu do catálogo | salvo aponta para id ausente | item omitido da aba | N/A |
| Detalhe por URL | `/local/:id` sem `extra` | carrega local + avaliações dos amigos ali; sem avaliações → "Nenhum amigo avaliou ainda" + botão Avaliar | id inexistente → "Local não encontrado" + voltar |

</frozen-after-approval>

## Code Map

- `firebase/firestore.rules:37-50` -- padrão de `users/{uid}/following/{t}` (dono, `createdAt == request.time`, `hasOnly`) a replicar em `saved/{placeId}`, com `exists(places/{placeId})`
- `firebase/tests/firestore.rules.test.js` -- suíte de Rules (mocha, emulator)
- `app/lib/data/repositories/user_repository.dart` + `firestore_user_repository.dart` -- estilo de repositório a seguir; criar `SavedRepository` (+ `FirestoreSavedRepository`) e um `SavedPlacesStore` (`ChangeNotifier`, ids salvos, toggle serializado por id)
- `app/lib/data/repositories/place_repository.dart` -- `getPlaces(ids)` com cache (G0) para resolver os salvos
- `app/lib/data/repositories/review_repository.dart` -- adicionar `fetchReviewsForPlace(placeId)` (`placeId ==`, `orderBy createdAt desc`, limit 50) para o detalhe autônomo; filtrar por quem o usuário segue no ViewModel
- `firebase/firestore.indexes.json` -- índice `reviews(placeId ASC, createdAt DESC)`
- `app/lib/routing/router.dart` + `routes.dart` -- hoje rotas soltas, feed com `AppBar.actions` (Pessoas/Sair) e FAB "Avaliar"; migrar para `StatefulShellRoute.indexedStack` com `NavigationBar`; rota `/local/:placeId` hoje redireciona ao feed sem `extra`
- `app/lib/ui/feed/widgets/feed_card.dart`, `app/lib/ui/place/place_detail_view.dart:38`, `app/lib/ui/review/place_picker_view.dart` -- pontos do botão
- `app/lib/main.dart:52` -- injeção dos providers
- `app/test/support/fakes.dart` -- fakes à mão

## Tasks & Acceptance

**Execution:**
- [x] `firebase/tests/**` + `firebase/firestore.rules` -- testes vermelhos de `saved` (dono cria/lê/apaga; terceiro nega; `hasOnly(['createdAt'])`; `createdAt == request.time`; local inexistente nega; update nega), depois Rules
- [x] `app/lib/data/**` + testes -- `SavedRepository` (listar com `createdAt`, salvar, remover), `fetchReviewsForPlace`, índice
- [x] `app/lib/ui/saved/**` + `app/lib/ui/core/save_button.dart` + testes -- `SavedPlacesStore` (otimista, serializa por id, reverte em falha), `SaveButton` reutilizável, `SavedView`/`SavedViewModel`
- [x] `app/lib/ui/place/**` + testes -- `PlaceDetailViewModel` autônomo por `placeId` (usa `extra` quando houver para render imediato)
- [x] `app/lib/routing/**` + `app/lib/ui/core/app_shell.dart` + testes -- shell com `NavigationBar` (Amigos · Quero ir · Pessoas), FAB "Avaliar" mantido na aba Amigos, "Sair" no menu da aba Pessoas ou do feed

**Acceptance Criteria:**
- Given Bianca no feed, when toca o marcador do card, then o local aparece no topo da aba "Quero ir" sem recarregar o app.
- Given um local salvo, when ela abre o detalhe pela aba, then vê o marcador cheio e as avaliações dos amigos ali.
- Given app reaberto, when vai à aba "Quero ir", then os salvos continuam lá.

## Verification

**Commands:**
- `cd app && flutter analyze` -- expected: No issues found
- `cd app && flutter test` -- expected: todos passam
- `cd firebase && export JAVA_HOME="/c/Program Files/Java/jdk-24" PATH="$JAVA_HOME/bin:$PATH" && firebase emulators:exec --only firestore "npm test"` -- expected: todos passam

## Suggested Review Order

**Integridade e privacidade**

- Ponto de entrada: salvos só do dono, local existente, `createdAt` do servidor.
  [`firestore.rules:50`](../../firebase/firestore.rules#L50)

**Estado único dos salvos**

- Store otimista: serializa por id, reverte em falha, trata doc já existente.
  [`saved_places_store.dart:183`](../../app/lib/ui/saved/saved_places_store.dart#L183)

- Recarga que espera escritas em voo e preserva toggles.
  [`saved_places_store.dart:97`](../../app/lib/ui/saved/saved_places_store.dart#L97)

- Botão reutilizável: feedback imediato, "Desfazer", erro tardio.
  [`save_button.dart:21`](../../app/lib/ui/core/save_button.dart#L21)

**Navegação e telas**

- Shell com barra inferior; Hero desligado nas abas ocultas.
  [`router.dart:71`](../../app/lib/routing/router.dart#L71)

- Aba "Quero ir": cards compactos, vazio, erro e pull-to-refresh.
  [`saved_view.dart:20`](../../app/lib/ui/saved/saved_view.dart#L20)

- Detalhe autônomo por `placeId`, com "Você" e "Avaliar de novo".
  [`place_detail_view_model.dart:101`](../../app/lib/ui/place/place_detail_view_model.dart#L101)

- Só avaliações dos amigos do local: `placeId ==` + `authorId in` em lotes.
  [`firestore_review_repository.dart:83`](../../app/lib/data/firebase/firestore_review_repository.dart#L83)

**Periféricos**

- Índice reviews(placeId, authorId, createdAt DESC) — publicar antes do app.
  [`firestore.indexes.json:15`](../../firebase/firestore.indexes.json#L15)

- Barra inferior Amigos · Quero ir · Pessoas.
  [`app_shell.dart:6`](../../app/lib/ui/core/app_shell.dart#L6)
