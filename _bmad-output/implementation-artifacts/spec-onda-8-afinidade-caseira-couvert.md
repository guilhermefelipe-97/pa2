---
title: 'Onda 8 — Gosto parecido, comida caseira e couvert/taxa'
type: 'feature'
created: '2026-11-04'
status: 'review'
baseline_commit: '68ce2d2'
review_loop_iteration: 0
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

Entregar F07 (versão binária), F30 e F28, a onda 8 do sequenciador, a partir da onda 7 (`feat/onda-7`).
Decisões da usuária em 04/11/2026: F07 com pelo menos 3 locais em comum e diferença média ≤ 1 ponto; selo no perfil e
no card do feed, sem mudar a ordem; F28 confirmado com 2 pessoas e maioria; Rules testadas no emulador com JDK 21
portátil (sem alterar o Java do PC).

## Boundaries & Constraints

**Always:**
- **F07 — Gosto parecido (sim/não):** compara o usuário com outra pessoa nos locais que os dois avaliaram. Em cada local
  vale a avaliação mais recente de cada um; compara eixo a eixo só os eixos que os dois deram. "Gosto parecido" quando
  há pelo menos 3 locais em comum com algum eixo comparável e a diferença média absoluta das notas comparadas é ≤ 1.
  Nunca percentual. Selo "Gosto parecido" no perfil da pessoa (com "em N lugares em comum") e ao lado do nome no card
  do feed Amigos. A ordem do feed não muda. Cálculo puro e testável; nunca compara a pessoa com ela mesma.
- **F30 — Comida caseira:** três tags comunitárias novas no mesmo mecanismo do F18: `marmita`, `quentinha`,
  `self-service` (por quilo). Confirmadas por 3 autores distintos, último voto de cada pessoa, sem o titular. No
  formulário de avaliação e no filtro do feed aparecem num grupo "Comida caseira". A tag `caseiro` existente continua.
- **F28 — Couvert e taxa de 10%:** perguntas opcionais "Cobrou couvert?" e "A taxa de 10% veio na conta?" (sim/não/sem
  resposta) na avaliação e no "Voltei aqui". Campos `couvert` e `serviceFee` opcionais (ausente, null ou bool). Na
  ficha, para cada pergunta: relato mais recente de cada pessoa nos últimos 12 meses (mesmas idas usadas no preço
  F27); com 2 ou mais pessoas mostra a maioria e a contagem ("Cobra couvert · 3 de 4 relatos"); empate mostra
  "Relatos divergentes"; menos de 2 pessoas não mostra conclusão.
- Rules: aceitar as tags novas e os dois campos booleanos opcionais em `reviews` e `visits`, sem abrir outras chaves.
  Builds antigos (sem os campos) continuam aceitos. Testes de Rules novos rodando no emulador.
- Português do Brasil. Dados antigos sem os campos continuam válidos.

**Ask First:** Deploy de Rules/índices/Hosting; publicar APK; mudar limiares.

**Never:** Percentual de afinidade; reordenar o feed por afinidade; F08 (sugestão de gêmeo de gosto); tag ou couvert
informados pelo dono do local.

## I/O & Edge-Case Matrix

| Caso | Resultado exigido |
|---|---|
| 2 locais em comum, notas iguais | Sem selo (amostra insuficiente) |
| 3 locais, diferença média 1,0 | Gosto parecido |
| 3 locais, diferença média 1,2 | Sem selo |
| Locais em comum sem eixo comparável | Não contam como local em comum |
| Perfil próprio | Sem selo |
| 3 autores marcam "marmita" | Tag confirmada; filtro Marmita encontra o local |
| Titular marca a tag | Rules já negam avaliação do titular |
| Couvert: 1 relato | Sem conclusão |
| Couvert: 2 sim, 1 não | "Cobra couvert · 2 de 3 relatos" |
| Couvert: 1 sim, 1 não | "Relatos divergentes" |
| `couvert: "sim"` ou chave extra | Negado pelas Rules |

</frozen-after-approval>

## Code Map

- `app/lib/domain/taste_match.dart` (novo): regra do F07.
- `app/lib/domain/food_tags.dart`, `ui/dietary/food_filter_options.dart`, `ui/dietary/food_tag_chips.dart`: tags do F30.
- `app/lib/domain/bill_extras.dart` (novo): resumo do F28; modelos `place_activity_*.dart`, repositórios de review/visit, formulários e view models de avaliação/visita, ficha.
- `firebase/firestore.rules`, `firebase/tests/firestore.rules.test.js`.
- Perfil (`ui/profile/`) e card do feed (`ui/feed/widgets/`) para o selo.

## Spec Change Log

- 2026-11-04: para não mudar telas e testes existentes, a tag `caseiro` e as demais continuam na posição e com o texto
  de antes; o grupo "Comida caseira" reúne só as três novas, depois delas. No formulário, "self-service" aparece como
  "self-service por quilo". As perguntas de couvert/taxa ficam num bloco recolhível "Na conta: couvert e taxa
  (opcional)", que abre sozinho se já houver resposta. Testes antigos de visita e filtro passaram a rolar até o
  botão antes de tocar (o formulário ficou mais alto); as verificações não mudaram.

## Verification

app: `flutter analyze`; `flutter test`. firebase: `npm run test:emulator` com JDK 21 portátil só no processo.

## Resultado da implementação local — 04/11/2026

- `flutter analyze --no-pub`: os mesmos 6 avisos `empty_catches` de antes, nenhum erro.
- `flutter test --no-pub`: **1.234 testes passaram**, 1 ignorado (mapa manual). Antes da onda: 1.217.
- `npm run test:emulator` (JDK 21 portátil só no processo): **355 testes passaram** (antes 352).
- Novos testes: `test/domain/wave8_test.dart`, `test/ui/wave8_widgets_test.dart`, 3 casos de Rules.
- Limitação do F07: compara com as 100 avaliações mais recentes do usuário (limite por lote do repositório).
- Rules mudaram (tags e campos `couvert`/`serviceFee`): precisam de deploy, com autorização, antes do APK novo.
- Nenhum commit, deploy ou APK nesta etapa.
