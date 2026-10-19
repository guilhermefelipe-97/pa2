---
title: 'Onda 4 — Modo decisão (F09), copiar lista com crédito (F13), log de auditoria (F04) e Minhas avaliações'
type: 'feature'
created: '2026-10-19'
status: 'done'
baseline_commit: 'a1b9e1a526bf81908deda3a317cf175c6f18c688'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-f12-listas-nomeadas.md'
  - '{project-root}/docs/lean-inception/jornada-bianca.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Para fechar a jornada da Bianca ainda faltam três passos: decidir no sábado em até 2 toques (passo 7), copiar a lista de quem ela segue (passo 5) e ver as próprias avaliações (hoje o feed exclui o próprio uid). Além disso, a Integridade exige que avaliações, visitas e relatos tenham log de auditoria antes de o lado estabelecimento existir (onda 5).

**Approach:** Ficam num único spec, por decisão do humano ([K]), quatro entregas:
- **Minhas avaliações:** ícone "Você" na AppBar do feed abre o perfil próprio, que já existe.
- **F04:** um doc `auditLog` é gravado no mesmo batch de cada review, visita e relato, e as Rules exigem o par.
- **F13:** listas ganham a opção "Visível para quem me segue". Quem segue a autora vê essas listas no perfil dela e as copia como snapshot com crédito. A autora vê "copiada N vezes" (N32).
- **F09:** botão "Decidir por mim" no Quero ir. Toque 1 abre a escolha de companhia; toque 2 escolhe e mostra 1 lugar dos salvos do chip ativo, com "Outra opção".

## Boundaries & Constraints

**Always:**
- **Auditoria (F04):**
  - Coleção `auditLog/{coleção}-{docId}`. O id determinístico mantém o retry de ack perdido idempotente.
  - Chaves exatas: `actorUid`, `action` ('create'), `collection` ('reviews'|'visits'|'openReports'), `docId`, `placeId`, `at == request.time`.
  - Ninguém lê nem altera pelo app: read, update e delete são negados.
  - O create de `reviews`, `visits` e `openReports` exige `existsAfter` do doc de auditoria correspondente.
  - O create de auditoria exige `getAfter(alvo).authorId == auth.uid`, alvo novo (`!exists`) e `placeId` igual ao do alvo.
- **Listas e cópia (F13):**
  - Campos opcionais em `lists`: `visible` (bool) e o trio `copiedFromUid`/`copiedFromName`/`copiedFromListId`. Docs antigos sem eles continuam válidos.
  - O trio é gravado só no create e é imutável. `copiedFromName` tem de ser igual ao `displayName` da autora.
  - Leitura da lista: dono, ou `visible == true` e o leitor segue o dono (`users/{leitor}/following/{dono}`).
  - Cópia = nova lista com mesmo nome e emoji. Se o nome já existir, usa "`<nome>` (de `<Autora>`)", cortado em 40 caracteres. Os locais são salvos no Quero ir antes, e só os confirmados entram na lista (invariante lista ⊂ Quero ir do F12).
  - Contador de cópias: `users/{dono}/lists/{listId}/copies/{copiadorUid}` (`createdAt`).
    - Create só por quem segue a autora e com a lista visível.
    - Uma por pessoa, imutável.
    - A dona lê todos (contagem via `count()`); o copiador lê só o próprio.
- **Modo decisão (F09):**
  - O ranking é uma função pura de domínio, sem nota única exibida.
  - Sem localização, a distância sai do critério. O app nunca pede permissão aqui (`lastKnownPositionIfGranted`).
  - Falha em reviews, seguidos ou relatos não bloqueia a decisão: o critério que falhou é ignorado.

**Ask First:**
- Listas visíveis para quem não segue a autora.
- Cópia viva / sincronizada.
- Registrar no log tentativas negadas (exige Cloud Functions).
- Auditar outras coleções (lists, saved, follow).

**Never:**
- Editar ou excluir avaliações (continua imutável).
- Exibir nota agregada única.
- Clima como fator.
- Listas colaborativas.
- Paginação no perfil.
- Backfill de auditoria para docs já existentes (o seed via admin não passa pelas Rules).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| Avaliar | review + foto + trava + place novo | batch inclui `auditLog/reviews-{id}` e passa nas Rules | ack perdido → retry com mesmo id |
| Forja | review sem auditoria; auditoria sem review, com outro `actorUid`, de doc antigo ou com `placeId` diferente | negado | Rules |
| Tornar visível | menu do chip → "Visível para quem me segue" | a legenda da AppBar vira "Quem te segue vê esta lista" | falha → reverte + SnackBar |
| Ver listas | perfil de quem eu sigo | seção "Listas" com as visíveis (emoji, nome, n locais); não sigo → seção oculta | falha → seção oculta |
| Copiar | lista de 12 locais, 3 já salvos | "Copiar lista" → nova lista com os 12 + copies/{eu}; SnackBar "Lista copiada" com "Ver" | falha → desfaz os saves feitos e avisa |
| Copiar de novo / limite | já copiei; tenho 30 listas | 2ª cópia é criada sem novo registro de cópia; 30 listas → botão desabilitado com aviso | N/A |
| Crédito | chip de lista copiada | menu mostra "Copiada de Ana", que abre o perfil | N/A |
| Contador | dona abre o menu da lista | "Copiada 3 vezes" (oculto se 0) | falha → oculto |
| Decidir | 5 salvos, toque "Amigos" | 1 lugar + motivo ("2 pessoas que você segue foram com amigos à noite") + "Ver local" / "Outra opção" | N/A |
| Fechados / sem salvos | todos com "Fechado" relatado; chip vazio | "Nenhum lugar desta lista está aberto agora"; botão desabilitado se não há salvos | N/A |
| Fim das opções | "Outra opção" após o último | "Essas eram todas as opções" e volta ao 1º | N/A |
| Você | toca o ícone "Você" no feed | abre `/pessoa/{meuUid}` com título "Você" | N/A |

</frozen-after-approval>

## Code Map

- `firebase/firestore.rules` -- review `:349-381` (`validReview`, `getAfter` da trava em `:353`), visit `:402-426`, openReport `:443-464`, lists `:108-122` + `listKeys`/`validList` `:182-203` (`hasAll` exige todos os campos: os opcionais ficam fora dele), following `:36-45` (`users/A/following/B` = A segue B), padrão de path `lockPath` `:345`
- `firebase/tests/firestore.rules.test.js` -- helpers `addReview` `:139`, `reviewWithPhotoBatch` `:181`, `addVisit` `:1198`, `addOpenReport` `:1496` (incluir a auditoria, senão os testes existentes quebram); lists `:328-474`; batch máximo `:1035-1043` (limite de acessos)
- `app/lib/data/firebase/firestore_review_repository.dart:146-202`, `firestore_visit_repository.dart:159-193`, `firestore_open_report_repository.dart:129-156` -- `_commit` de cada um; o id já é gerado no cliente antes do batch
- `app/lib/data/firebase/firestore_lists_repository.dart` -- `_parse` `:37`, `createList` `:60`, `updateList` `:78`; `app/lib/data/repositories/lists_repository.dart` -- interface
- `app/lib/domain/models/place_list.dart` -- `copyWith`, `nameKey`, `maxLists`/`maxPlaces`
- `app/lib/ui/lists/lists_store.dart` -- `create` `:341-401` (um local só; fluxo save→createList→`_undoAutoSave`), `_reconcile` `:279`; `app/lib/ui/saved/saved_places_store.dart` `setSaved` `:220`
- `app/lib/ui/saved/saved_view.dart` -- AppBar `:35-49` (sem `actions`), `_ActiveListChip` menu `:359-370`, hint de semântica `:380`; `saved_view_model.dart` `items` `:90` (salvos do chip ativo), `selectedList` `:48`
- `app/lib/ui/profile/profile_view.dart` `_Header` `:163-217` (seção Listas entre `:205` e `:206`); `profile_view_model.dart` `load` `:121-168`
- `app/lib/domain/open_status.dart` `openStatusesByPlace` `:96`, `openReportsSince` `:36`; `app/lib/ui/nearby/nearby_view_model.dart:439-466` -- padrão de leitura opcional de relatos
- `app/lib/domain/geo.dart` `distanceMeters` `:196`; `app/lib/data/services/location_service.dart` `lastKnownPositionIfGranted`
- `app/lib/domain/models/place_activity.dart:30` `dayPeriod`; `app/lib/domain/models/scores.dart` (sem nota única)
- `app/lib/ui/feed/feed_view.dart` AppBar `actions` `:94-109`; `feed_view_model.dart` (não expõe uid)
- `app/lib/routing/router.dart` -- saved `:153-161` (sem clock), pessoa `:207-225`; `app/lib/main.dart` providers `:95-159`
- `app/test/support/{fakes,app_harness}.dart` -- `FakeListsRepository` `:556`, `FakeUserRepository` `:86`, `pumpApp`; FakeFirebaseFirestore faz batch não atômico

## Tasks & Acceptance

**Execution:**
- [x] `firebase/tests/firestore.rules.test.js` + `firebase/firestore.rules` -- testes vermelhos (auditoria: par obrigatório e forjas da matriz, read negado, batch máximo com auditoria passa; lists: opcionais, trio imutável e nome conferido, leitura por seguidor só se visível e negada para não-seguidor; copies: regras acima), depois as Rules -- integridade primeiro
- [x] `app/lib/data/firebase/audit_log.dart` + os 3 `_commit` + testes de repositório -- helper que adiciona a entrada ao batch; testes de chaves exatas e de retry com o mesmo id
- [x] `app/lib/domain/models/place_list.dart`, `app/lib/data/**/lists_repository*.dart`, `fakes.dart` + testes -- `visible`, `copiedFrom`; `setVisible`, `listVisibleLists(ownerUid)`, `copyCount`, `hasCopied`, `createList` com crédito, `recordCopy`
- [x] `app/lib/ui/lists/lists_store.dart` + testes -- `setVisible` otimista; `copyFrom(list, author)` (salva os locais, cria só com os confirmados, desfaz os saves em caso de falha, nome alternativo, limite de 30)
- [x] `app/lib/ui/saved/**` + testes -- itens de menu "Visível para quem me segue", "Copiada de X" e "Copiada N vezes"; legenda da AppBar; hint de semântica
- [x] `app/lib/ui/profile/**`, `app/lib/ui/lists/person_list_view.dart`, `routes.dart`/`router.dart` + testes -- seção "Listas" no perfil; rota `/pessoa/:uid/lista/:listId` com os locais e o botão "Copiar lista"
- [x] `app/lib/domain/decision.dart` + testes -- ranking puro (ver Design Notes), cobrindo os empates e a ausência de cada sinal
- [x] `app/lib/ui/decision/**`, `saved_view.dart`, `router.dart` + testes -- `DecisionViewModel` (seguidos, reviews, relatos, posição, clock) e sheet de 2 toques
- [x] `app/lib/ui/feed/**` + `test/ui/router_widget_test.dart` -- ícone "Você" (`Key('feed-me')`) → `Routes.person(uid)`
- [x] `docs/lean-inception/sequenciador-mvp.md` -- linha N32: decidido (contador de cópias na onda 4)

**Acceptance Criteria:**
- Given Bianca segue Ana e a lista "Sábado" de Ana está visível, when Bianca abre o perfil de Ana, toca a lista e "Copiar lista", then a lista aparece como chip no Quero ir com "Copiada de Ana", todos os locais estão salvos, e Ana vê "Copiada 1 vez".
- Given Bianca tem salvos e está com o chip "Sábado" ativo, when toca "Decidir por mim" e depois "Amigos", then vê exatamente 1 lugar daquela lista em no máximo 2 toques.
- Given qualquer avaliação, visita ou relato criado pelo app, when o batch confirma, then existe `auditLog/{coleção}-{id}` com o autor e o `at` do servidor.

## Design Notes

O ranking da F09 é lexicográfico, sem pesos a calibrar. Só contam as avaliações de quem você segue sobre o local candidato:

1. avaliações com mesma companhia **e** mesmo período do dia de agora;
2. avaliações com mesma companhia **ou** mesmo período;
3. total de avaliações;
4. média dos eixos preenchidos dessas avaliações (interna, nunca exibida);
5. distância crescente (sem posição ou sem coordenadas vai para o fim);
6. `savedAt` mais recente.

"Tanto faz" ignora a companhia. "Fechado" relatado sai antes de ordenar. O motivo exibido vem do critério que desempatou.

As avaliações vêm de `fetchReviewsByAuthors(seguidos)`, filtradas por `placeId ∈ candidatos`, no mesmo padrão do feed e do Perto. Consultar N locais estouraria leituras.

## Verification

**Commands:**
- `cd app && flutter analyze` -- expected: No issues found
- `cd app && flutter test` -- expected: todos passam
- `cd firebase && export JAVA_HOME="/c/Program Files/Java/jdk-24" PATH="$JAVA_HOME/bin:$PATH" && firebase emulators:exec --only firestore "npm test"` -- expected: todos passam

## Suggested Review Order

**Integridade — auditoria (F04)**

- Ponto de entrada: a coleção de auditoria e as chaves exatas; create só de doc novo, do mesmo autor e `placeId`.
  [`firestore.rules:560`](../../firebase/firestore.rules#L560)
- O create de review/visit/report exige o par via `existsAfter`; read/update/delete negados.
  [`firestore.rules:428`](../../firebase/firestore.rules#L428)
- O cliente injeta a entrada no mesmo batch; id determinístico mantém o retry idempotente.
  [`audit_log.dart:20`](../../app/lib/data/firebase/audit_log.dart#L20)
- Uso no commit da avaliação (constante da coleção).
  [`firestore_review_repository.dart:184`](../../app/lib/data/firebase/firestore_review_repository.dart#L184)

**Integridade — crédito e contador (F13)**

- Crédito endurecido: `copiedFromUid != uid`, segue a autora, origem existe e visível.
  [`firestore.rules:227`](../../firebase/firestore.rules#L227)
- `copies`: só segue+visível cria; dona conta e apaga; update negado.
  [`firestore.rules:137`](../../firebase/firestore.rules#L137)
- Registro direto (sem ler antes); `permission-denied` = já registrado (2ª cópia).
  [`lists_store.dart:525`](../../app/lib/ui/lists/lists_store.dart#L525)
- `deleteList` apaga as cópias no mesmo batch (lotes extras acima de 499).
  [`firestore_lists_repository.dart:181`](../../app/lib/data/firebase/firestore_lists_repository.dart#L181)

**Cópia de lista (F13) — fluxo**

- `copyFrom`: salva os locais, cria só com os confirmados, desfaz em falha, nome e limite.
  [`lists_store.dart:547`](../../app/lib/ui/lists/lists_store.dart#L547)
- Nome da cópia: corta o base por grafema, mantém " (de Autora)" e o número.
  [`place_list.dart:106`](../../app/lib/domain/models/place_list.dart#L106)
- Tela da lista: `permission-denied` = indisponível; copia só o que mostrou; "N de M".
  [`person_list_view_model.dart:146`](../../app/lib/ui/lists/person_list_view_model.dart#L146)
- Leitura das listas visíveis da pessoa; perfil mostra a seção só a quem segue.
  [`firestore_lists_repository.dart:38`](../../app/lib/data/firebase/firestore_lists_repository.dart#L38)

**Modo decisão (F09)**

- Ranking lexicográfico puro; "Fechado" sai antes; nenhuma nota exibida.
  [`decision.dart:108`](../../app/lib/domain/decision.dart#L108)
- Motivo só com fatos da própria opção (sem superlativo relativo).
  [`decision.dart:274`](../../app/lib/domain/decision.dart#L274)
- VM: seguidos + reviews + relatos + última posição; falha ignora o critério.
  [`decision_view_model.dart:115`](../../app/lib/ui/decision/decision_view_model.dart#L115)

**UI — entradas e menu**

- Botão "Decidir por mim" e menu do chip (visível, crédito, contador); `didUpdateWidget` zera a contagem.
  [`saved_view.dart:377`](../../app/lib/ui/saved/saved_view.dart#L377)
- Pedido de foco ignorado se a lista não existe mais.
  [`saved_view_model.dart:34`](../../app/lib/ui/saved/saved_view_model.dart#L34)
- Ícone "Você" no feed abre o próprio perfil.
  [`feed_view.dart:103`](../../app/lib/ui/feed/feed_view.dart#L103)
- Rota da lista da pessoa.
  [`routes.dart:15`](../../app/lib/routing/routes.dart#L15)

**Periféricos**

- Decisão de N32 registrada no sequenciador.
  [`sequenciador-mvp.md:188`](../../docs/lean-inception/sequenciador-mvp.md#L188)
- Testes: auditoria `firestore.rules.test.js:2037`, cópias `:649`, decisão, listas e foco em `app/test`.
  [`firestore.rules.test.js:2037`](../../firebase/tests/firestore.rules.test.js#L2037)
