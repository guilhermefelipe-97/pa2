# Onda 8 — Gosto parecido, comida caseira e couvert/taxa

Spec: `_bmad-output/implementation-artifacts/spec-onda-8-afinidade-caseira-couvert.md`.

| Cartão | Onde está no app | Regra |
|---|---|---|
| **F07** Gosto parecido (sim/não) | Perfil da pessoa ("Gosto parecido · em N lugares em comum") e ao lado do nome no card do feed | Pelo menos 3 locais em comum com algum eixo comparável e diferença média ≤ 1 ponto. Última avaliação de cada um por local. Não muda a ordem do feed. |
| **F30** Comida caseira | Formulário de avaliação e filtro do feed, grupo "Comida caseira" | Tags `marmita`, `quentinha`, `self-service` (por quilo), confirmadas por 3 pessoas como as do F18. |
| **F28** Couvert e taxa de 10% | Avaliação e "Voltei aqui" (bloco "Na conta", recolhido); ficha do local | Relato mais recente de cada pessoa em 12 meses; com 2+ pessoas mostra a maioria; empate = "relatos divergentes". |

## Antes de ir ao ar (precisa de autorização)

- `firebase deploy --only firestore:rules`: sem isso, avaliações com as tags novas ou com couvert/taxa são negadas em
  produção.
- Continua pendente da onda 7: deploy do Hosting e do índice de `visits`.

## Limitações conhecidas

- F07 usa as 100 avaliações mais recentes de quem está vendo.
- F08 (sugerir gêmeo de gosto que você não segue) segue fora do MVP.
