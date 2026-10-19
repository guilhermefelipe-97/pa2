---
title: 'F15 — Recorrência como sinal: "Voltei aqui"'
type: 'feature'
created: '2026-10-12'
status: 'done'
baseline_commit: '4fe63b84179f023c0c32b7b45e7d7cd190f8226b'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-f03-bloqueio-reavaliacao.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-f06-card-fonte-de-confianca.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** "Vezes que voltou" é o sinal mais honesto do produto (Objetivo 1, hipótese 3), mas hoje só existe como contagem de avaliações — e o F03 impede avaliar de novo antes de 30 dias, então quem volta toda semana (Toni, Bianca "virou o nosso lugar") não gera sinal nenhum.

**Approach:** Nova ação leve "Voltei aqui" (visita): sem notas, com companhia opcional, contexto derivado da hora (F02). Limite de 1 visita a cada 12 h por usuário e local, garantido no servidor por trava `users/{uid}/visitLocks/{placeId}` no mesmo batch (padrão do F03). Recorrência = avaliações + visitas da mesma pessoa no local. Feed, detalhe e Perto passam a mostrar a recorrência acima das notas: "🔁 Ana voltou 3 vezes", e visitas também colocam o local no feed de quem segue (como atividade sem notas).

## Boundaries & Constraints

**Always:** Visita nunca anônima (autor e nome do perfil validados como na review), imutável, `createdAt` do servidor, local existente (criado no mesmo batch se descoberto — G2). Trava de 12 h = constante única com paridade testada Rules↔Dart. Recorrência por pessoa conta avaliações + visitas; linha de fonte só com visitas mostra "voltou · há 2 dias" sem eixos. Selo de recorrência aparece quando alguém tem ≥2 idas. Leituras: visitas dos seguidos com `whereIn` em lotes de 30 (mesmo corte consistente das reviews), índice `visits(authorId ASC, createdAt DESC)` e, para o detalhe, `visits(placeId ASC, authorId ASC, createdAt DESC)`. Bloqueio de reavaliação (F03) passa a oferecer "Registrar visita" como alternativa ativa.

**Ask First:** Visita por geolocalização automática; contar visitas de quem não segue; ranking do feed por recorrência.

**Never:** Notas na visita; editar/apagar visita; recorrência agregada anônima ("120 pessoas voltaram").

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Registrar | detalhe → "Voltei aqui" → companhia opcional → Confirmar | batch: `visits/{id}` + trava; SnackBar "Visita registrada" | falha → "Não foi possível registrar" |
| Antes de 12 h | trava há 3 h | botão desabilitado: "Você registrou uma visita às 13h. De novo a partir das 01h." | via SDK → Rules negam |
| Feed com visita | Ana só visitou X (sem avaliar) | card de X com linha "Ana · voltou · há 2 h", sem eixos | N/A |
| Recorrência | Ana: 1 avaliação + 2 visitas em X | linha de Ana com eixos da avaliação e "foi 3 vezes"; selo "🔁 Ana voltou 3 vezes" | N/A |
| Detalhe | 3 amigos, 5 idas no total | "🔁 5 idas de 3 amigos" acima das médias; lista mostra visitas como itens sem nota | N/A |
| Bloqueado no F03 | formulário de avaliação bloqueado | botão "Registrar visita" ativo, abre o mesmo fluxo | N/A |
| Local descoberto | só no Photon | local criado no batch da visita | Rules |
| Forja via SDK | sem trava; trava de outro; `authorName` diferente do perfil; chave extra; `createdAt` do cliente; update/delete | negado | Rules |

</frozen-after-approval>

## Code Map

- `firebase/firestore.rules` -- padrão `match /reviewLocks/{placeId}` + `validReview` (F03) e `places` create (G2) a replicar em `visits` e `visitLocks`
- `firebase/firestore.indexes.json` -- novos índices de `visits`
- `app/lib/domain/feed.dart:70-99` -- `sources`/`TrustSource` contam só reviews; passar a aceitar visitas (`FeedItem` com reviews + visits; `TrustSource.latest` pode ser visita)
- `app/lib/domain/review_lock.dart` -- padrão de prazo/mensagem a reutilizar para 12 h
- `app/lib/data/repositories/review_repository.dart` + `firestore_review_repository.dart` -- padrão de batch (local G2 + doc + trava, retry de corrida); novo `VisitRepository`
- `app/lib/ui/feed/feed_view_model.dart:119`, `app/lib/ui/nearby/nearby_view_model.dart:398`, `app/lib/ui/place/place_detail_view_model.dart`, `app/lib/ui/profile/profile_view_model.dart:119` -- onde buscar visitas junto das reviews
- `app/lib/ui/feed/widgets/trust_sources.dart` -- linha de fonte (com/sem eixos), selo
- `app/lib/ui/review/review_view.dart` -- tela de bloqueio do F03 (ganha "Registrar visita")
- `app/lib/domain/models/companion.dart`, `day_period.dart` -- contexto

## Tasks & Acceptance

**Execution:**
- [x] `firebase/tests/**` + `firebase/firestore.rules` + índices -- testes vermelhos (matriz "Forja", 12 h, local descoberto no batch), depois Rules
- [x] `app/lib/domain/**` + testes -- modelo `Visit`, prazo de 12 h com paridade, `FeedItem`/`TrustSource` com visitas, recorrência por pessoa e por local
- [x] `app/lib/data/**` + testes -- `VisitRepository` (criar em batch, por autores em lotes, por local + autores, trava)
- [x] `app/lib/ui/visit/**` + testes -- fluxo "Voltei aqui" (sheet com companhia opcional, estados, trava)
- [x] `app/lib/ui/feed/**`, `app/lib/ui/place/**`, `app/lib/ui/nearby/**`, `app/lib/ui/profile/**`, `app/lib/ui/review/**` + testes -- visitas no feed, selo, detalhe, perfil, Perto (sinal de amigos inclui visitas), "Registrar visita" no bloqueio

**Acceptance Criteria:**
- Given Toni avaliou o Mangai há 5 dias e volta hoje, when toca "Voltei aqui", then a visita é registrada e quem o segue vê "🔁 Toni voltou 2 vezes" no card.
- Given Toni registrou uma visita há 2 h, when tenta de novo, then vê até quando está bloqueado e as Rules negam via SDK.

## Verification

**Commands:**
- `cd app && flutter analyze` -- expected: No issues found
- `cd app && flutter test` -- expected: todos passam
- `cd firebase && export JAVA_HOME="/c/Program Files/Java/jdk-24" PATH="$JAVA_HOME/bin:$PATH" && firebase emulators:exec --only firestore "npm test"` -- expected: todos passam

## Spec Change Log

- Revisão 1 (patches, sem loopback): corte comum entre avaliações e visitas (`loadFriendActivities`), `PlaceActivity` sealed, envio com timeout de 15 s e ack perdido verificado pela trava, sheet não fechável durante o envio, mensagem de trava com data, selo sem emoji no texto. KEEP: trava de 12 h no mesmo batch, visita sem notas, "voltou N vezes" conforme o intent.

## Suggested Review Order

**Integridade**

- Ponto de entrada: visita do autor, local existente, trava de 12 h no batch.
  [`firestore.rules:369`](../../firebase/firestore.rules#L369)

- Trava renovável só após 12 h, nunca apagável.
  [`firestore.rules:74`](../../firebase/firestore.rules#L74)

- Batch visita + trava (+ local descoberto), timeout e ack perdido.
  [`firestore_visit_repository.dart:68`](../../app/lib/data/firebase/firestore_visit_repository.dart#L68)

**Recorrência**

- Fontes por pessoa contam idas (avaliações + visitas).
  [`feed.dart:86`](../../app/lib/domain/feed.dart#L86)

- Avaliações e visitas dos seguidos com corte comum.
  [`load_visits.dart:34`](../../app/lib/ui/core/load_visits.dart#L34)

**UI**

- Sheet "Voltei aqui": companhia opcional, bloqueio, não fecha durante envio.
  [`visit_sheet.dart:22`](../../app/lib/ui/visit/visit_sheet.dart#L22)

**Periféricos**

- Prazo único de 12 h com paridade testada nas Rules.
  [`visit_lock.dart:8`](../../app/lib/domain/visit_lock.dart#L8)
