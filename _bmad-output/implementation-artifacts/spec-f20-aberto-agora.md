---
title: 'F20 — "Está aberto agora?" confirmado por quem está lá'
type: 'feature'
created: '2026-10-12'
status: 'done'
baseline_commit: 'a9b25e60dc1b43a7c310fc8dc44004492b18c0cd'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-f10-estou-na-rua-agora.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-f15-recorrencia.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Horário cadastrado desatualizado é a falha mais comum dos concorrentes (Toni, passo 7: "não quero chegar e a cozinha ter fechado"). O "aberto agora" ficou fora do F10 por depender disso.

**Approach:** Quem está no local (a até 150 m, pela localização do aparelho) responde "Está aberto agora? Sim / Não" em 1 toque. Os relatos ficam em `openReports` com autor e hora do servidor, limitados a 1 a cada 30 min por pessoa e local (trava no mesmo batch, padrão F03/F15). O status exibido vem dos relatos das últimas 3 h: "Aberto · confirmado por Ana há 20 min", "Fechado · informado por Caio há 1 h", ou "Informações divergentes" quando há Sim e Não na última meia hora. Aparece no detalhe e no Perto, que ganha o filtro "Aberto agora (confirmado)".

## Boundaries & Constraints

**Always:** Relato nunca anônimo (autor = perfil), imutável, `createdAt` do servidor, local existente (criado no batch se descoberto — G2). Relatos de qualquer usuário contam (é fato, não gosto), sempre com o nome de quem informou. Botão só aparece quando a posição do aparelho está a ≤150 m do local (checagem no cliente; permissão pedida no contexto, nunca ao abrir o detalhe). Janela de 3 h, trava de 30 min e raio de 150 m como constantes únicas (paridade Rules↔Dart para a trava). Consulta do detalhe: `placeId ==` + `createdAt >=` agora−3 h, ordenada, limitada; Perto: mesma consulta com `placeId in` em lotes de 30 só para os itens visíveis; índice `openReports(placeId ASC, createdAt DESC)`. Falha nessa leitura nunca derruba a tela (status some).

**Ask First:** Horário de funcionamento do OSM; notificações; relatos de fila (F29).

**Never:** Inferir aberto/fechado sem relato; relato sem localização próxima pela UI; esconder quem informou.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Relatar | a 80 m do Mangai → "Sim" | batch `openReports/{id}` (`open: true`) + trava; status vira "Aberto · confirmado por você agora" | falha → "Não foi possível enviar" |
| Longe | a 2 km | sem botão de relato; status visível se houver | N/A |
| Sem permissão | localização não concedida | "Está aí agora? Confirme se está aberto" → explica e pede permissão no toque | negada → texto "Ative a localização para confirmar" |
| Antes de 30 min | trava há 10 min | botão desabilitado "Você informou às 20h10. De novo a partir das 20h40." | via SDK → Rules negam |
| Status | Ana Sim há 20 min, Caio Não há 2 h | "Aberto · confirmado por Ana há 20 min" (mais recente vence) | N/A |
| Divergente | Sim há 10 min e Não há 20 min | "Informações divergentes · 2 relatos na última meia hora" | N/A |
| Expirado | último relato há 3 h 05 min | sem status | N/A |
| Perto filtro | chip "Aberto agora (confirmado)" | só itens com status Aberto (não divergente) | leitura falha → chip desabilitado com aviso |
| Forja via SDK | outro autor, `open` não-bool, chave extra, `createdAt` do cliente, sem trava, update/delete | negado | Rules |

</frozen-after-approval>

## Code Map

- `firebase/firestore.rules` -- padrão de `visits` + `visitLocks` (F15) e `places` create (G2) para `openReports` + `users/{uid}/openReportLocks/{placeId}` (30 min, `duration.value(30, 'm')`)
- `firebase/firestore.indexes.json` -- índice `openReports(placeId ASC, createdAt DESC)`
- `app/lib/data/firebase/firestore_visit_repository.dart` -- referência de batch (local descoberto + doc + trava, timeout 15 s, ack perdido, corrida) a espelhar em `OpenReportRepository`
- `app/lib/domain/visit_lock.dart`, `review_lock.dart` -- padrão de prazo/mensagem com `formatHour`
- `app/lib/domain/geo.dart` -- haversine; `app/lib/data/services/location_service.dart` -- `currentPositionIfGranted`/`locate`
- `app/lib/ui/place/place_detail_view_model.dart` + view -- status e ação de relato
- `app/lib/ui/nearby/nearby_view_model.dart` + view -- status por item, filtro, sinal de amigos já carregado
- `app/lib/ui/core/app_clock.dart` -- relógio injetável

## Tasks & Acceptance

**Execution:**
- [x] `firebase/tests/**` + `firebase/firestore.rules` + índice -- testes vermelhos (matriz "Forja", 30 min, local descoberto no batch, consulta do detalhe e do Perto), depois Rules
- [x] `app/lib/domain/open_status.dart` + testes -- status a partir de relatos (mais recente, divergência em 30 min, expiração 3 h), rótulos e semântica, constantes com paridade
- [x] `app/lib/data/**` + testes -- `OpenReportRepository` (criar em batch, por local, por locais em lotes, trava)
- [x] `app/lib/ui/open/**` + `app/lib/ui/place/**` + testes -- status no detalhe, ação Sim/Não com proximidade, permissão, trava, estados
- [x] `app/lib/ui/nearby/**` + testes -- status nos itens e filtro "Aberto agora (confirmado)"

**Acceptance Criteria:**
- Given Ana está no Mangai e confirma "Sim", when Toni abre o Mangai ou o Perto nos 3 h seguintes, then vê "Aberto · confirmado por Ana há …".
- Given Toni a 2 km do local, when abre o detalhe, then não vê o botão de relatar.

## Verification

**Commands:**
- `cd app && flutter analyze` -- expected: No issues found
- `cd app && flutter test` -- expected: todos passam
- `cd firebase && export JAVA_HOME="/c/Program Files/Java/jdk-24" PATH="$JAVA_HOME/bin:$PATH" && firebase emulators:exec --only firestore "npm test"` -- expected: todos passam
