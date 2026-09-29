# NaÁrea — Sequenciador de Funcionalidades e MVP

> Fase 3 (Semanas 7–9) — Lean Inception + BMAD. Atividade do sequenciador: ordenar as funcionalidades em ondas de tamanho aproximadamente igual, entregando o mais impactante o mais cedo possível.
>
> Entradas: as 30 funcionalidades (`objetivos-e-funcionalidades.md`), os parâmetros de esforço/negócio/UX e o semáforo (`revisao-tecnica-negocio-ux.md`), e as combinações por passo de jornada (`funcionalidades-nas-jornadas.md`).

## Decisões tomadas antes de sequenciar

| Decisão | Resultado |
|---|---|
| **Usuário mais importante / jornada prioritária** | **Bianca**, jornada do sábado. Concentra o Objetivo 1 (confiança) e o Objetivo 2 (decisão em 2 toques) e valida a hipótese mais arriscada do produto: extrair sinal de qualidade de quem nunca publica. **Ponto de partida do sequenciador = F05** (feed "Amigos foram aqui"), a primeira funcionalidade do primeiro passo da jornada dela |
| **F07 (match de gosto)** | Entra **simplificada**: match binário ("gosto parecido: sim/não") em vez de percentual. Sai de 🔴/EEE para 🟡/EE |
| **F08 (gêmeo de gosto)** | **Fora do MVP.** Único cartão no quadrante X do semáforo ($ + ♥ + EEE), depende de um F07 que ainda não existe |
| **F19 (lugares para atividade)** | **Fora do MVP.** Nenhuma jornada a reivindica. Toni fica atendido pela metade "comida" (F17, F30); a metade "corrida" volta quando houver mapa de jornada que a sustente |

**Restam 28 cartões no sequenciador.**

## Regras aplicadas

| Regra | Enunciado | Status |
|---|---|---|
| 1 | Máximo 4 cartões por onda | ✅ nenhuma onda passa de 4 |
| 2 | No máximo 1 cartão vermelho por onda | ✅ nenhum 🔴 restante (F07 simplificada virou 🟡, F08 saiu) |
| 3 | Nenhuma onda com três cartões só amarelos/vermelhos | ✅ máximo de 2 🟡 por onda |
| 4 | Soma de esforço ≤ 6 "E" | ✅ maior onda = 6E |
| 5 | Soma de valor ≥ 5 "$" e ≥ 5 "♥" | ✅ menor onda = $5 / ♥5 |
| 6 | Dependência sempre em onda anterior | ✅ verificada cartão a cartão |

Conversão usada: E=1, EE=2, EEE=3 · $=1, $$=2, $$$=3 · ♥=1, ♥♥=2, ♥♥♥=3.

---

# O SEQUENCIADOR

## 🌊 Onda 1 — A tese virando tela

| Cartão | Funcionalidade | 🚦 | E | $ | ♥ | Por que aqui |
|---|---|---|---|---|---|---|
| **F05** | Feed "Amigos foram aqui" | 🟡 | EE | $$$ | ♥♥♥ | **Ponto de partida**: passo 1 da jornada da Bianca. Sem ele não existe produto |
| **F01** | Avaliação em 3 eixos | 🟢 | E | $$$ | ♥♥ | Dado primitivo — tudo depende dele |
| **F02** | Avaliação contextual | 🟡 | EE | $$ | ♥ | Decisão de arquitetura, não tela. Caríssima de corrigir depois |
| **F11** | "Quero ir" (salvar, fricção zero) | 🟢 | E | $$ | ♥♥♥ | Passo 3 da Bianca — o momento em que o produto ganha a persona |

**Totais**: 6E · $10 · ♥9 · 2 amarelos · 4 cartões ✅

> Onda mais pesada do sequenciador em risco: dois 🟡 e todo o esforço disponível. É deliberado — F02 e F05 são as duas decisões que, se forem tomadas errado agora, contaminam as oito ondas seguintes.

## 🌊 Onda 2 — Descobrir, salvar, decidir e avaliar

| Cartão | Funcionalidade | 🚦 | E | $ | ♥ | Dependência |
|---|---|---|---|---|---|---|
| **F06** | Card com fonte de confiança | 🟢 | E | $$$ | ♥♥♥ | ← F05 (onda 1) |
| **F12** | Listas nomeadas | 🟢 | E | $$ | ♥♥ | ← F11 (onda 1) |
| **F14** | Avaliação mínima válida | 🟢 | E | $$ | ♥♥♥ | ← F01 (onda 1) |
| **F10** | "Estou na rua agora" | 🟢 | E | $$ | ♥♥♥ | — |

**Totais**: 4E · $9 · ♥11 · 0 amarelos · 4 cartões ✅

> Onda inteiramente verde e barata, logo depois da mais arriscada. Aqui o ciclo da Bianca fecha pela primeira vez: ela vê de quem veio, salva, organiza e decide na rua.

## 🌊 Onda 3 — Confiança que se sustenta sozinha

| Cartão | Funcionalidade | 🚦 | E | $ | ♥ | Dependência |
|---|---|---|---|---|---|---|
| **F15** | Recorrência como sinal | 🟢 | E | $$$ | ♥♥ | ← F02 (onda 1) |
| **F20** | "Está aberto agora?" | 🟢 | E | $$ | ♥♥♥ | — |
| **F27** | Faixa de preço reportada | 🟢 | E | $$ | ♥♥ | — |
| **F03** | Bloqueio de reavaliação | 🟢 | E | $$ | ♥ | ← F01 (onda 1) |

**Totais**: 4E · $9 · ♥8 · 0 amarelos · 4 cartões ✅

---

# 🎯 MVP = ONDAS 1 + 2 + 3

**12 funcionalidades · 14E de esforço · $28 · ♥28**

### Hipóteses que este MVP valida

| # | Hipótese | Como se mede | Funcionalidades |
|---|---|---|---|
| 1 | Pessoas decidem onde ir quando a recomendação tem **fonte rastreável**, e não nota anônima | % de decisões originadas de card com fonte explícita (Objetivo 1) | F05, F06, F01, F15 |
| 2 | Dá para chegar à decisão em **2 toques / menos de 30s** sem exigir produção de conteúdo | taxa de sessões que terminam em decisão; tempo mediano (Objetivo 2) | F10, F11, F12 |
| 3 | **Comportamento passivo é dado de qualidade** — salvar e voltar valem mais que estrela | volume de salvamentos e de recorrência vs. volume de avaliações escritas | F11, F14, F15 |
| 4 | Informação vinda da **comunidade** (preço, aberto agora) bate a informação vinda do dono | taxa de confirmação/contestação dos campos comunitários | F20, F27 |

### O que o MVP deliberadamente **não** valida

- **Objetivo 3 (ciclo saudável dos dois lados)** — Paola não tem nada nas ondas 1–3. É intencional: o painel dela não tem sentido sem base de avaliações, e a monetização não pode ser testada antes de o freio existir. Entra a partir da onda 5.
- **Rede de afinidade além dos conhecidos** — F07 só chega na onda 8. Até lá, "confiança" significa contato, não gosto parecido.

### Jornadas cobertas pelo MVP

| Persona | Cobertura |
|---|---|
| **Bianca** | Passos 1–4, 7–9, 11 de 13 — o ciclo completo dela funciona, faltando copiar lista (F13), compartilhar (F21) e modo silencioso (F16) |
| **Toni** | Passos 3, 5, 6, 7, 9, 10 de 10 — decide com confiança, mas sem filtro alimentar (F17) nem comida caseira (F30) |
| **Paola** | Nenhum passo. Fora do MVP por desenho |

---

# INCREMENTOS

## 🌊 Onda 4 — Decisão assistida e curadoria

| Cartão | Funcionalidade | 🚦 | E | $ | ♥ | Dependência |
|---|---|---|---|---|---|---|
| **F09** | Modo decisão (máx. 2 toques) | 🟡 | EE | $$ | ♥♥♥ | ← F12, F10 (onda 2) |
| **F13** | Copiar lista com crédito | 🟡 | EE | $$ | ♥♥ | ← F12 (onda 2) |
| **F04** | Log de auditoria | 🟢 | EE | $$ | ♥ | ← F01 (onda 1) |

**Totais**: 6E · $6 · ♥6 · 2 amarelos · 3 cartões ✅

> F04 entra **antes** de qualquer funcionalidade do lado estabelecimento: quando a Paola chegar (onda 5), o log já tem que estar rodando. É o critério de aceite de Integridade da Fase 2.

## 🌊 Onda 5 — Abre o lado estabelecimento

| Cartão | Funcionalidade | 🚦 | E | $ | ♥ | Dependência |
|---|---|---|---|---|---|---|
| **F22** | Perfil de dono verificado | 🟡 | EE | $$$ | ♥ | — |
| **F18** | Crowd-tagging | 🟡 | EE | $$ | ♥♥ | ← F01 (onda 1) |
| **F17** | Perfil alimentar | 🟢 | E | $$ | ♥♥ | — |

**Totais**: 5E · $7 · ♥5 · 2 amarelos · 3 cartões ✅

> F18 vem **junto** com F22, não depois: no instante em que existe perfil de dono, as tags precisam já estar vindo de quem avaliou. É o guardrail contra manipulação do estabelecimento.

## 🌊 Onda 6 — Reputação legítima e receita

| Cartão | Funcionalidade | 🚦 | E | $ | ♥ | Dependência |
|---|---|---|---|---|---|---|
| **F25** | Slot patrocinado (Destaque) | 🟢 | EE | $$$ | ♥ | ← F22 (onda 5) |
| **F24** | Resposta do estabelecimento | 🟢 | E | $$ | ♥♥ | ← F22 (onda 5) |
| **F29** | Fila ao vivo + histórica | 🟡 | EE | $$ | ♥♥ | — |
| **F16** | Modo silencioso | 🟡 | E | $ | ♥♥ | ← F05, F01 (onda 1) |

**Totais**: 6E · $8 · ♥7 · 2 amarelos · 4 cartões ✅

> F24 entra na mesma onda que F25 de propósito: a Paola não pode ganhar o canal de **comprar visibilidade** antes de ter o canal de **responder e corrigir**. Seria inverter a ordem moral do Objetivo 3.
>
> ⚠️ **Risco declarado**: o freio (F26) só chega na onda 7. Recomendação — manter F25 desligado em produção até F26 estar entregue. A regra 6 é respeitada, mas a integridade exige mais que a regra.

## 🌊 Onda 7 — Fecha o Objetivo 3 e a distribuição

| Cartão | Funcionalidade | 🚦 | E | $ | ♥ | Dependência |
|---|---|---|---|---|---|---|
| **F23** | Painel com série temporal | 🟡 | EEE | $$$ | ♥♥ | ← F22 (onda 5), F01/F02 (onda 1) |
| **F21** | Card compartilhável com deep link | 🟡 | EE | $$ | ♥♥ | ← F06 (onda 2) |
| **F26** | Suspensão automática do Destaque | 🟢 | E | $$ | ♥ | ← F25 (onda 6) |

**Totais**: 6E · $7 · ♥5 · 2 amarelos · 3 cartões ✅

> O item mais caro do corte (F23, EEE) fica isolado numa onda sem outro cartão pesado. Com ele, a necessidade central da Paola é atendida e o Objetivo 3 fecha — reputação, receita e freio.

## 🌊 Onda 8 — Afinidade e cauda cultural

| Cartão | Funcionalidade | 🚦 | E | $ | ♥ | Dependência |
|---|---|---|---|---|---|---|
| **F07** | Match de gosto (versão binária) | 🟡 | EE | $$ | ♥♥ | ← F01/F02 (onda 1) |
| **F30** | Categorias de comida caseira | 🟢 | E | $$ | ♥♥ | — |
| **F28** | Couvert / taxa 10% | 🟢 | E | $ | ♥♥ | — |

**Totais**: 4E · $5 · ♥6 · 1 amarelo · 3 cartões ✅

---

## Visão consolidada

| Onda | Cartões | Esforço | $ | ♥ | 🟡 | Entrega |
|---|---|---|---|---|---|---|
| 1 | F05, F01, F02, F11 | 6E | 10 | 9 | 2 | A tese virando tela |
| 2 | F06, F12, F14, F10 | 4E | 9 | 11 | 0 | Ciclo da Bianca fecha |
| 3 | F15, F20, F27, F03 | 4E | 9 | 8 | 0 | **🎯 fim do MVP** |
| 4 | F09, F13, F04 | 6E | 6 | 6 | 2 | Decisão assistida e curadoria |
| 5 | F22, F18, F17 | 5E | 7 | 5 | 2 | Abre o lado estabelecimento |
| 6 | F25, F24, F29, F16 | 6E | 8 | 7 | 2 | Reputação legítima e receita |
| 7 | F23, F21, F26 | 6E | 7 | 5 | 2 | Objetivo 3 fechado |
| 8 | F07, F30, F28 | 4E | 5 | 6 | 1 | Afinidade e cauda cultural |
| **Total** | **28 cartões** | **41E** | **61** | **57** | **11** | |

## Fora do sequenciador

| ID | Funcionalidade | Situação |
|---|---|---|
| F08 | Sugestão de "gêmeo de gosto" | Cortada do MVP. Reavaliar depois da onda 8, quando F07 tiver dado métrica real de afinidade |
| F19 | Categoria "Lugares para atividade" | Cortada do MVP por falta de jornada. Volta se o mapa da corrida do Toni for escrito |
| N31 | Anotação privada de evento interno no painel | Backlog pós-MVP. Candidata natural à onda 9, junto de F23 |
| N32 | Reconhecimento de quem cura listas | **Pergunta em aberto, não backlog.** A onda 4 entrega F13 (copiar lista) pressupondo curadoras que nenhuma funcionalidade do sequenciador produz. Precisa de decisão antes da onda 4 |

## Notas de rigor

- O semáforo em `revisao-tecnica-negocio-ux.md` resume "18 🟢 / 10 🟡 / 2 🔴"; a contagem cartão a cartão dá **17 🟢 / 11 🟡 / 2 🔴**. As ondas acima usam a cor de cada funcionalidade individualmente, não o resumo.
- A soma de esforço das 28 funcionalidades (41E) ocupa 85% da capacidade teórica das 8 ondas (48E). Não há folga para reestimativa para cima: se qualquer 🟡 virar mais caro na implementação, a onda correspondente estoura a regra 4 e algo precisa descer uma onda.
