---
title: 'F27 — Faixa de preço reportada por quem pagou + valor para rachar'
type: 'feature'
created: '2026-10-12'
status: 'done'
baseline_commit: '8da9724aff94066ca9da69dcbcf12d316966311b'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-f15-recorrencia.md'
  - '{project-root}/docs/lean-inception/jornada-bianca.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** "Cabe no orçamento?" é a pergunta que Toni (passo 5) e o grupo da Bianca (passo 8, "vai rachar") fazem antes de sair, e o app não responde. Preço de cardápio/dono fica desatualizado; o sinal confiável é quanto quem foi pagou.

**Approach:** Campo opcional "Quanto gastou por pessoa?" na avaliação e na visita (F15), em 5 faixas: até R$ 30 · R$ 30–60 · R$ 60–100 · R$ 100–150 · R$ 150+. O local passa a mostrar a faixa típica relatada pelos amigos (mediana, usando o relato mais recente de cada pessoa) com a contagem de relatos e quem relatou; o detalhe mostra a distribuição e uma estimativa para rachar ("Para 4 pessoas: R$ 120–240") com seletor de quantidade.

## Boundaries & Constraints

**Always:** Sempre opcional (nunca bloqueia envio); 1 toque para escolher, 1 para limpar. Valor gravado como `priceBand` inteiro 1–5 ou `null`; chave opcional nas Rules (builds antigos continuam válidos) — `hasOnly` inclui, `hasAll` não exige. Agregado só com relatos de amigos e do próprio usuário, 1 por pessoa (o mais recente); nunca preço anônimo. Faixa típica = mediana das faixas (empate → faixa mais baixa); exibida só com ≥1 relato, sempre com a contagem ("3 relatos de amigos"). Estimativa = faixa × pessoas (2–12, padrão 2), última faixa "R$ 150+ por pessoa → a partir de R$ 300". Faixas e rótulos numa constante única com paridade Dart↔Rules (limites 1–5).

**Ask First:** Preço exato em reais; couvert/taxa de 10% (F28); preço vindo do dono.

**Never:** Média de reais inventada; preço agregado de quem o usuário não segue.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Avaliar com preço | eixos + "R$ 30–60" | review com `priceBand: 2` | N/A |
| Visita com preço | "Voltei aqui" + "até R$ 30" | visit com `priceBand: 1` | N/A |
| Sem preço | nada escolhido | `priceBand: null` | N/A |
| Forja via SDK | 0, 6, "2", 2.5 | negado | Rules |
| Build antigo | review/visita sem a chave | aceita | N/A |
| Agregado | Ana 2 (há 1 mês) e 3 (ontem), Bia 2, Caio 4 | relatos usados: Ana 3, Bia 2, Caio 4 → mediana 3 "R$ 60–100 por pessoa · 3 relatos" | N/A |
| Empate | Ana 1, Bia 2 | "até R$ 30" (mais baixa) | N/A |
| Sem relatos | ninguém informou | nada de preço no card; detalhe mostra "Ninguém informou o preço ainda" | N/A |
| Rachar | faixa 3, 4 pessoas | "Para 4 pessoas: R$ 240–400" | N/A |
| Rachar última faixa | faixa 5, 3 pessoas | "Para 3 pessoas: a partir de R$ 450" | N/A |

</frozen-after-approval>

## Code Map

- `firebase/firestore.rules:275-284` `reviewRequiredKeys`/`reviewKeys` (padrão opcional do `hasPhoto`) e `:342-354` `visitKeys`/`validVisit` -- incluir `priceBand` opcional (`null` ou int 1–5)
- `app/lib/domain/models/place_activity*.dart` (Review/Visit em biblioteca sealed) -- adicionar `priceBand`
- `app/lib/domain/feed.dart:86` -- `FeedItem`/`TrustSource` (idas por pessoa) para o agregado
- `app/lib/data/firebase/firestore_review_repository.dart`, `firestore_visit_repository.dart` -- payload/parse (leitura tolerante: ausente = null; inválido invalida o doc, como os eixos do F14)
- `app/lib/ui/review/review_view.dart` + VM, `app/lib/ui/visit/visit_sheet.dart` + VM -- seletor de faixa
- `app/lib/ui/feed/widgets/feed_card.dart`, `trust_sources.dart`, `app/lib/ui/place/place_detail_view.dart`, `app/lib/ui/nearby/nearby_view.dart` -- exibição

## Tasks & Acceptance

**Execution:**
- [x] `firebase/tests/**` + `firebase/firestore.rules` -- testes vermelhos (forja, chave ausente aceita, 1–5 e null aceitos) para review e visita, depois Rules
- [x] `app/lib/domain/price_band.dart` + testes -- faixas, rótulos, mediana com empate, relato mais recente por pessoa, estimativa para N pessoas, paridade com Rules
- [x] `app/lib/data/**` + testes -- payload e parse em reviews e visitas
- [x] `app/lib/ui/core/price_band_picker.dart` + `app/lib/ui/review/**` + `app/lib/ui/visit/**` + testes -- seletor acessível (chips com semântica "Até 30 reais por pessoa, selecionado"), limpar
- [x] `app/lib/ui/feed/**`, `app/lib/ui/place/**`, `app/lib/ui/nearby/**` + testes -- chip de preço no card e no Perto; no detalhe: faixa típica, distribuição (barras com rótulo acessível), quem relatou, estimativa com seletor de pessoas

**Acceptance Criteria:**
- Given Ana e Bia (seguidas) informaram R$ 30–60 no Mangai, when Toni vê o card, then lê "R$ 30–60 por pessoa · 2 relatos".
- Given o detalhe do Mangai, when a Bianca escolhe 4 pessoas, then vê "Para 4 pessoas: R$ 120–240".

## Verification

**Commands:**
- `cd app && flutter analyze` -- expected: No issues found
- `cd app && flutter test` -- expected: todos passam
- `cd firebase && export JAVA_HOME="/c/Program Files/Java/jdk-24" PATH="$JAVA_HOME/bin:$PATH" && firebase emulators:exec --only firestore "npm test"` -- expected: todos passam

## Spec Change Log

- Revisão 1 (patches, sem loopback): relatos limitados aos últimos 12 meses, desempate determinístico, aviso de dispersão no detalhe, uma única `PriceSection` com resumo compartilhado com o chip, acessibilidade (rótulo falado do rachar, headers, sem larguras fixas), agregação separada em `price_summary.dart`. KEEP: faixas e rótulos do intent, empate pela faixa mais baixa, chave opcional nas Rules.

## Suggested Review Order

**Integridade**

- Ponto de entrada: `priceBand` opcional, null ou inteiro 1–5, em review e visita.
  [`firestore.rules:291`](../../firebase/firestore.rules#L291)

**Domínio**

- Faixas, rótulos falados e estimativa para N pessoas.
  [`price_band.dart:13`](../../app/lib/domain/price_band.dart#L13)

- Agregado: relato mais recente por pessoa, 12 meses, mediana, dispersão.
  [`price_summary.dart:39`](../../app/lib/domain/price_summary.dart#L39)

**UI**

- Seletor opcional e acessível na avaliação e na visita.
  [`price_band_picker.dart:20`](../../app/lib/ui/core/price_band_picker.dart#L20)

- Detalhe: faixa típica, distribuição, quem relatou e rachar.
  [`price_section.dart:31`](../../app/lib/ui/place/price_section.dart#L31)
