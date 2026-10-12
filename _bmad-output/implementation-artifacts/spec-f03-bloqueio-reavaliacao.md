---
title: 'F03 — Bloqueio de reavaliação antes de 30 dias'
type: 'feature'
created: '2026-10-12'
status: 'done'
baseline_commit: '12f1f59bc0b42055714e7307150a98677b041ea1'
review_loop_iteration: 0
context:
  - '{project-root}/docs/lean-inception/visao-restricoes.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-g2-catalogo-brasil-photon.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Guardrail obrigatório da Fase 1 (`visao-restricoes.md:52`): um usuário não pode reavaliar o mesmo local antes de um período mínimo. Hoje nada impede várias avaliações seguidas, o que infla o sinal (Toni, passo 10; Paola, passo 6 "pedir para conhecidos avaliarem").

**Approach:** Período mínimo de 30 dias entre avaliações do mesmo usuário no mesmo local, garantido no servidor por um doc-trava determinístico `reviewLocks/{uid}_{placeId}` com `lastAt`, gravado no mesmo batch da avaliação; as Rules só aceitam a avaliação se a trava for criada agora ou atualizada com `lastAt` anterior a 30 dias. O app consulta a trava antes de abrir a avaliação e explica o bloqueio com a data de liberação, oferecendo "Registrar visita" (F15) como alternativa — por ora o botão aparece desabilitado com "em breve" até o F15 existir.

## Boundaries & Constraints

**Always:** Regra no servidor (Rules), não só na UI. Trava ligada à avaliação: a review só é aceita se `getAfter(trava).lastAt == request.time`; a trava só é escrita se `existsAfter` da review do mesmo batch (id da review gravado na trava como `reviewId`). Trava legível só pelo dono; nunca apagável. 30 dias = `duration.value(30, 'd')` nas Rules e constante única no app. Avaliações anteriores ao F03 (sem trava) não bloqueiam a 1ª avaliação pós-F03. Mensagem: "Você avaliou este lugar em 12/10. Pode avaliar de novo a partir de 11/11." (datas em UTC-3).

**Ask First:** Mudar o período; permitir editar avaliação em vez de criar outra (F04).

**Never:** Apagar/editar avaliações; bloquear salvar/visitar; prazo diferente por categoria.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| 1ª avaliação | sem trava | batch: review + `reviewLocks/me_X {lastAt, reviewId, placeId}` | N/A |
| Antes de 30 dias | trava com `lastAt` há 10 dias | app não abre o formulário: tela/linha "Você avaliou… Pode avaliar de novo a partir de…" | se forçar via SDK → Rules negam |
| Após 30 dias | trava com `lastAt` há 31 dias | avaliação aceita; trava atualizada | N/A |
| Forja via SDK | review sem trava no batch; trava sem review; trava de outro uid; `lastAt` do cliente; apagar trava; ler trava alheia | negado | Rules |
| Avaliação legada | review antiga, sem trava | 1ª avaliação nova permitida | N/A |
| Corrida | dois envios simultâneos | só um passa (o 2º vê a trava) | "Não foi possível salvar" no 2º |
| Detalhe do local | usuário bloqueado | CTA "Avaliar de novo" vira texto "Pode avaliar de novo a partir de 11/11" | N/A |

</frozen-after-approval>

## Code Map

- `firebase/firestore.rules` `validReview`/`match /reviews` -- adicionar exigência `getAfter(reviewLocks/$(uid)_$(placeId)).data.lastAt == request.time`; novo `match /reviewLocks/{lockId}` (id = `uid + '_' + placeId`, create/update validados, read só dono, delete negado)
- `firebase/tests/firestore.rules.test.js` -- usar `withSecurityRulesDisabled` para semear travas antigas (`lastAt` no passado)
- `app/lib/data/firebase/firestore_review_repository.dart:34` `createReview` -- batch atual (local G2 + review + foto); incluir a trava; retry de corrida já existente deve continuar correto
- `app/lib/data/repositories/review_repository.dart` -- novo `reviewLockOf(uid, placeId) -> DateTime?`
- `app/lib/ui/review/review_view_model.dart` + `review_view.dart` -- checar trava ao abrir; estado bloqueado
- `app/lib/ui/place/place_detail_view_model.dart` + view -- CTA "Avaliar de novo" (F11) respeita a trava
- `app/lib/domain/models/day_period.dart` -- UTC-3 para datas exibidas
- `app/test/support/fakes.dart` -- fake com travas

## Tasks & Acceptance

**Execution:**
- [x] `firebase/tests/**` + `firebase/firestore.rules` -- testes vermelhos da matriz, depois Rules
- [x] `app/lib/domain/review_lock.dart` + testes -- `reviewAllowedAt(lastAt)`, constante de 30 dias, formatação da mensagem
- [x] `app/lib/data/**` + testes -- trava no batch; `reviewLockOf`
- [x] `app/lib/ui/review/**`, `app/lib/ui/place/**` + testes -- estado bloqueado no formulário e no detalhe; botão "Registrar visita" desabilitado "em breve"

**Acceptance Criteria:**
- Given Toni avaliou o Mangai hoje, when tenta avaliar de novo, then vê "Pode avaliar de novo a partir de <hoje+30>" e nenhum formulário de notas.
- Given um cliente modificado que ignora a UI, when grava uma 2ª avaliação no mesmo dia, then as Rules negam.

## Verification

**Commands:**
- `cd app && flutter analyze` -- expected: No issues found
- `cd app && flutter test` -- expected: todos passam
- `cd firebase && export JAVA_HOME="/c/Program Files/Java/jdk-24" PATH="$JAVA_HOME/bin:$PATH" && firebase emulators:exec --only firestore "npm test"` -- expected: todos passam

## Spec Change Log

- Revisão 1 (coordenador, 13 correções): trava movida para `users/{uid}/reviewLocks/{placeId}` (leitura `isOwner`, sem ambiguidade do `_`; `getAfter` único no `validReview`); backfill `firebase/seed/backfill-review-locks.js` (`npm run backfill:locks`, `--dry-run`) e ordem de deploy no README (Rules + APK juntos, depois o backfill); leitura da trava com timeout de 5 s (formulário e detalhe; o detalhe não espera a trava); falha no envio reconsulta a trava e mostra o bloqueio; mensagem com hora ("a partir de 11/11 às 20h", hora arredondada para cima no minuto) e Timer no detalhe até a liberação; botão "Registrar visita" removido (fica para o F15); `toNatalTime` privado (`formatDayMonth`/`formatDayMonthHour`). KEEP: 30 dias nas Rules (`duration.value(30, 'd')`, paridade testada), trava no mesmo batch da review, avaliação legada sem trava não bloqueia a 1ª nova.

## Suggested Review Order

**Integridade**

- Ponto de entrada: trava do dono, renovável só após 30 dias, nunca apagável.
  [`firestore.rules:58`](../../firebase/firestore.rules#L58)

- Review exige a trava gravada no mesmo batch, apontando para ela.
  [`firestore_review_repository.dart:34`](../../app/lib/data/firebase/firestore_review_repository.dart#L34)

**Regra no app**

- Prazo único de 30 dias e mensagem com data e hora (UTC-3).
  [`review_lock.dart:8`](../../app/lib/domain/review_lock.dart#L8)

- Consulta da trava ao abrir e ao falhar o envio, com timeout.
  [`review_view_model.dart:108`](../../app/lib/ui/review/review_view_model.dart#L108)

**Periféricos**

- Backfill das travas para avaliações anteriores ao F03.
  [`backfill-review-locks.js:1`](../../firebase/seed/backfill-review-locks.js#L1)
