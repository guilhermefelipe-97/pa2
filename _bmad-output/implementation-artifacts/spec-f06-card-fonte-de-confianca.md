---
title: 'F06 — Card com fonte de confiança explícita'
type: 'feature'
created: '2026-10-05'
status: 'done'
baseline_commit: 'c3880421e7380e831cbb260be948eb4703327ba7'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-feed-rico-fotos-comentario-visual.md'
  - '{project-root}/docs/lean-inception/jornada-bianca.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** O card mostra "A e B foram aqui" e a média dos eixos misturada, mas não deixa claro *quem disse o quê*, nem qual a relação com quem está lendo. É a métrica do Objetivo 1 (decisão vinda de fonte rastreável) e o passo 2 da Bianca ("nome de quem foi vale mais que qualquer nota").

**Approach:** O card ganha um bloco "Quem foi": até 2 pessoas em destaque (a mais recente primeiro), cada uma com avatar, nome, selo "você segue", os 3 eixos *dela*, companhia + período, quantas vezes foi ali e tempo relativo; o restante vira "+N pessoas" que abre o detalhe. A média agregada sai do card (fica só no detalhe). Tocar numa pessoa abre uma tela de perfil simples (`/pessoa/:uid`): nome, Seguir/Deixar de seguir e as avaliações dela. Sem foto de perfil (decisão de 2026-10-05).

## Boundaries & Constraints

**Always:** Toda nota exibida no card tem dono visível (nunca número sem nome). Relação calculada no cliente a partir de `following` já carregado (sem leituras extras por card). Perfil reutiliza `fetchReviewsByAuthors([uid])` e `UserRepository`; respeita as Rules atuais (avaliações legíveis por logados). Acessível: cada linha de fonte é lida como "Ana, você segue, comida 5, ambiente 4, atendimento 5, com amigos à noite, foi 2 vezes, há 2 horas". Design consistente com o tema; card não cresce mais que ~25% em altura em relação ao atual (2 linhas compactas).

**Ask First:** Foto de perfil; mostrar avaliações de quem o usuário não segue no feed; ranking por recorrência (F15).

**Never:** Nota agregada no card; seguidores/seguindo públicos com contagem; editar perfil.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| 1 pessoa | Ana, 1 avaliação | linha de Ana com eixos dela; sem "+N" | N/A |
| Várias | Ana (há 1 h), Bia (há 2 dias), Caio, Duda | linhas de Ana e Bia; "+2 pessoas" | N/A |
| Mesma pessoa voltou | Ana com 3 avaliações ali | 1 linha de Ana com os eixos da mais recente e "foi 3 vezes" | N/A |
| Própria avaliação no feed | não ocorre (feed exclui o próprio uid) | — | — |
| Perfil | toque em "Ana" | `/pessoa/ana`: nome, botão Seguindo, avaliações dela (mais recentes primeiro, com local e eixos) | erro → mensagem + "Tentar de novo"; uid inexistente → "Pessoa não encontrada" |
| Perfil sem avaliações | Ana nunca avaliou | "Ana ainda não avaliou nenhum lugar" | N/A |
| Deixar de seguir no perfil | toque em Seguindo | vira Seguir; ao voltar, o feed recarrega sem os cards de Ana | falha → reverte + "Não foi possível atualizar" |
| Perfil próprio | toque no próprio nome (detalhe, "Você") | abre perfil sem botão Seguir, título "Você" | N/A |

</frozen-after-approval>

## Code Map

- `app/lib/ui/feed/widgets/feed_card.dart:99-170` -- hoje: avatar stack + headline, `AxisScores.averages`, citação, rodapé de período; substituir pelo bloco "Quem foi" (citação de comentário mantida)
- `app/lib/ui/feed/widgets/{author_avatar,axis_scores,review_tile}.dart` -- reaproveitar avatar, eixos por avaliação e tile
- `app/lib/domain/feed.dart` -- `FeedItem` (reviews por local, mais recente primeiro); adicionar `sources` puro: por autor distinto, review mais recente + contagem
- `app/lib/ui/feed/feed_view_model.dart` -- já carrega `following`; expor `isFollowing(uid)`
- `app/lib/ui/people/people_view_model.dart` -- seguir/deixar de seguir com reconciliação (reaproveitar padrão)
- `app/lib/data/repositories/{user_repository,review_repository}.dart` -- `getProfile`, `follow/unfollow`, `fetchReviewsByAuthors`
- `app/lib/routing/{router,routes}.dart` -- rota `/pessoa/:uid` fora do shell (como `/local/:placeId`)
- `app/lib/ui/place/place_detail_view.dart` -- nomes nos tiles passam a abrir o perfil

## Tasks & Acceptance

**Execution:**
- [x] `app/lib/domain/feed.dart` + testes -- `FeedItem.sources` (autor, review mais recente, visitas), ordenado pela mais recente
- [x] `app/lib/ui/feed/widgets/trust_sources.dart` + testes -- bloco "Quem foi" (2 linhas + "+N"), semântica completa; integrar no `FeedCard` removendo a média
- [x] `app/lib/ui/profile/**` + testes -- `ProfileViewModel`/`ProfileView` (perfil, seguir otimista, avaliações), estados vazio/erro/não encontrado
- [x] `app/lib/routing/**` + `app/lib/ui/place/place_detail_view.dart` + testes -- rota e navegação a partir do card e do detalhe; feed recarrega ao voltar se o `following` mudou

**Acceptance Criteria:**
- Given Bianca segue Ana e Ana avaliou o Mangai com comida 5, when Bianca vê o card, then lê "Ana · você segue" com 🍽️5 de Ana, e nenhum número sem nome.
- Given o card, when Bianca toca em "Ana", then vê o perfil de Ana com as avaliações dela.

## Verification

**Commands:**
- `cd app && flutter analyze` -- expected: No issues found
- `cd app && flutter test` -- expected: todos passam

## Spec Change Log

- Revisão 1 (patches, sem loopback): sincronização de "seguir" unificada em `FollowEvents` + `FollowStaleness` (feed, Pessoas, detalhe e perfil marcam `stale` e recarregam ao voltar a ficar visíveis); `AppShell` repassa `ModalRoute.isCurrent` às abas. Card cresceu ~+17% (dentro do teto de ~25%). KEEP: nenhuma nota sem dono no card; relação calculada do `following` já carregado.

## Suggested Review Order

**Fonte de confiança no card**

- Ponto de entrada: fontes por pessoa (mais recente, visitas), calculadas uma vez.
  [`feed.dart:70`](../../app/lib/domain/feed.dart#L70)

- Bloco "Quem foi": 2 linhas, "+N" como botão, semântica falada completa.
  [`trust_sources.dart:74`](../../app/lib/ui/feed/widgets/trust_sources.dart#L74)

- Linha da fonte: nome com reticências, eixos com dono, "você segue".
  [`trust_sources.dart:144`](../../app/lib/ui/feed/widgets/trust_sources.dart#L144)

**Perfil rastreável**

- Seguir otimista com Desfazer e aviso às outras telas.
  [`profile_view_model.dart:148`](../../app/lib/ui/profile/profile_view_model.dart#L148)

- Rota `/pessoa/:uid` fora do shell.
  [`router.dart:155`](../../app/lib/routing/router.dart#L155)

**Sincronização de "seguir"**

- Contador de versão + staleness por ViewModel.
  [`follow_events.dart:23`](../../app/lib/ui/core/follow_events.dart#L23)

- Abas ficam inativas quando há rota por cima do shell.
  [`app_shell.dart:23`](../../app/lib/ui/core/app_shell.dart#L23)
