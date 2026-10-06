---
title: 'F14 — Avaliação mínima válida (eixos opcionais, mínimo 1)'
type: 'feature'
created: '2026-10-05'
status: 'done'
baseline_commit: '03018805cc1b16459a1c5837200db6906d9a31a4'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-onda-1-fundacao-avaliacao-feed.md'
  - '{project-root}/docs/lean-inception/jornada-bianca.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Exigir os 3 eixos afasta quem quase nunca contribui (Bianca): sem avaliação mínima o produto não coleta dado de 1 das 3 personas. A Onda 1 tornou os 3 obrigatórios.

**Approach:** Cada eixo passa a ser opcional; a avaliação é válida com pelo menos 1 eixo de 1–5. Continua sem nota única agregada: eixo não avaliado é ausência (`null`), nunca zero nem média inventada. Tela de avaliação vira rápida: os 3 eixos com toque de 1–5 (carinhas/estrelas grandes), cada um com "Limpar", texto e foto continuam opcionais; Enviar habilita no 1º eixo tocado. Exibição em todo o app trata eixo ausente.

## Boundaries & Constraints

**Always:** Pelo menos 1 eixo inteiro 1–5; os outros `null`. Chaves continuam sempre presentes (schema exato das Rules). Médias por eixo ignoram ausências e contam quantas avaliações têm aquele eixo; eixo sem nenhuma nota no local não mostra número. Card/linha de fonte/tile mostram só os eixos avaliados, sem placeholders confusos; leitor de tela fala apenas os eixos presentes. Avaliações antigas (3 eixos) seguem idênticas.

**Ask First:** Nota única/emoji geral que preencha os 3 eixos; tornar eixo obrigatório de novo por categoria.

**Never:** Zero como "não avaliado"; média entre eixos; estrela agregada.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Só comida | food 4, demais vazios | review `food: 4, ambience: null, service: null` | N/A |
| Nenhum eixo | tudo vazio | Enviar desabilitado com dica "Toque em pelo menos um" | VM não chama repositório |
| Limpar eixo | food 4 → Limpar | eixo volta a vazio; Enviar desabilita se era o único | N/A |
| Forja via SDK | os 3 `null`; eixo 0/6/"5"/4.5; chave ausente | negado | Rules |
| Linha de fonte | Ana só com comida 4 | "🍽️ 4" apenas; fala "comida 4" | N/A |
| Médias no detalhe | 3 reviews: comida 4,5,–; ambiente –,–,– | comida 4,5 (2 avaliações); ambiente sem número ("sem notas") | N/A |
| Review antiga | 3 eixos | igual a hoje | N/A |

</frozen-after-approval>

## Code Map

- `firebase/firestore.rules:107,157-159` -- `validScore` obriga inteiro 1–5 nos 3; passar a `v == null || validScore(v)` + ao menos um não nulo
- `app/lib/domain/models/scores.dart` -- `Scores` com 3 `int` obrigatórios; `AxisAverages.of` divide por `list.length`; passar a `int?` com invariante "≥1 presente" e médias por eixo com contagem
- `app/lib/data/firebase/firestore_review_repository.dart:51-53` + `_fromDoc` -- grava/lê `null` (leitura tolerante já existente)
- `app/lib/ui/review/review_view_model.dart` + `review_view.dart` -- seletor 1–5 por eixo, `canSubmit`, limpar
- `app/lib/ui/feed/widgets/axis_scores.dart:9-16` -- formata eixo; omitir ausentes; `.averages` mostra "sem notas"
- `app/lib/ui/feed/widgets/trust_sources.dart:62-64` -- fala/exibe eixos
- `app/lib/ui/place/place_detail_view.dart:222` -- médias no detalhe
- `app/lib/ui/profile/profile_view.dart`, `app/lib/ui/feed/widgets/review_tile.dart` -- demais pontos que exibem eixos

## Tasks & Acceptance

**Execution:**
- [x] `firebase/tests/**` + `firebase/firestore.rules` -- testes vermelhos da matriz (forja, só 1 eixo aceito, os 3 null negado), depois Rules
- [x] `app/lib/domain/models/scores.dart` + testes -- `int?`, validação ≥1, `AxisAverages` com contagem por eixo
- [x] `app/lib/data/**` + testes -- payload com `null`; leitura
- [x] `app/lib/ui/review/**` + testes -- avaliação rápida (seleção grande por eixo, limpar, dica, Enviar)
- [x] `app/lib/ui/feed/**`, `app/lib/ui/place/**`, `app/lib/ui/profile/**` + testes -- exibição e semântica sem eixos ausentes

**Acceptance Criteria:**
- Given Bianca na tela de avaliação, when toca só 5 em ambiente e envia, then a avaliação é salva e aparece no feed de quem a segue com "✨ 5" e nenhum outro eixo.

## Verification

**Commands:**
- `cd app && flutter analyze` -- expected: No issues found
- `cd app && flutter test` -- expected: todos passam
- `cd firebase && export JAVA_HOME="/c/Program Files/Java/jdk-24" PATH="$JAVA_HOME/bin:$PATH" && firebase emulators:exec --only firestore "npm test"` -- expected: todos passam

## Suggested Review Order

**Integridade**

- Ponto de entrada: cada eixo `null` ou 1–5, ao menos um presente, chaves sempre presentes.
  [`firestore.rules:118`](../../firebase/firestore.rules#L118)

**Modelo**

- `Scores` com eixos opcionais e erro que nomeia o eixo.
  [`scores.dart:5`](../../app/lib/domain/models/scores.dart#L5)

- Média por eixo ignora ausências e guarda a contagem.
  [`scores.dart:63`](../../app/lib/domain/models/scores.dart#L63)

**UI**

- Seletor de estrelas acessível, adaptável à largura, com Limpar.
  [`review_view.dart:353`](../../app/lib/ui/review/review_view.dart#L353)

- Exibição só dos eixos avaliados; "(n)" quando difere do total.
  [`axis_scores.dart:19`](../../app/lib/ui/feed/widgets/axis_scores.dart#L19)
