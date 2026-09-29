# NaÁrea — Revisão Técnica, de Negócio e de UX

> Fase 3 (Semanas 7–9) — Lean Inception + BMAD. Aplicada às 30 funcionalidades de `objetivos-e-funcionalidades.md`.
>
> Duas ferramentas, dois eixos de análise diferentes — não confundir:
> 1. **Gráfico do semáforo**: o quanto **sabemos** sobre como construir (confiança técnica) e sobre o que construir (confiança de negócio/UX). Não mede quanto valor a funcionalidade gera — mede quanta certeza temos sobre ela.
> 2. **Tabela esforço/negócio/UX**: quanto **trabalho** ela dá, quanto **retorno** ela traz, e quanto os usuários vão **amar** ela.
>
> Uma funcionalidade pode ter confiança alta nos dois eixos do semáforo (sabemos exatamente o que e como fazer) e ainda assim ter valor de negócio baixo na tabela — são perguntas diferentes.

## 1. Gráfico do semáforo

Eixo X = confiança técnica (como fazer). Eixo Y = confiança de negócio/UX (o que fazer). 🟢 alto nos dois · 🟡 um dos dois em dúvida · 🔴 baixa confiança em pelo menos um eixo, risco relevante · **X** = os dois baixos, candidata a descartar ou esclarecer antes de seguir.

| # | Funcionalidade | Confiança técnica (como) | Confiança negócio/UX (o quê) | Cor | Nota |
|---|---|---|---|---|---|
| 01 | Avaliação em 3 eixos | Alta | Alta | 🟢 | Mudança de schema simples, requisito bem definido pela Paola |
| 02 | Avaliação contextual | Média | Alta | 🟡 | Falta especificar quais campos de contexto valem por categoria (restaurante ≠ rota de corrida) |
| 03 | Bloqueio de reavaliação | Alta | Alta | 🟢 | Regra de negócio simples, guardrail já definido na Fase 1 |
| 04 | Log de auditoria | Alta | Alta | 🟢 | Padrão de implementação conhecido, requisito de Integridade já resolvido |
| 05 | Feed "Amigos foram aqui" | Média | Alta | 🟡 | Depende de um grafo social (quem segue quem) que ainda não foi modelado |
| 06 | Card com fonte de confiança | Alta | Alta | 🟢 | É composição de dado que o 05 já traz — só UI |
| 07 | Match de gosto (%) | **Baixa** | Média | 🔴 | Métrica de afinidade por sobreposição/concordância não está especificada — precisa de spike técnico antes de estimar esforço de verdade |
| 08 | Sugestão de "gêmeo de gosto" | **Baixa** | **Baixa** | 🔴 **X** | Depende do 07 não resolvido; o próprio corte de 30 já marca isso como corte de risco reintroduzido — candidata forte a esclarecer melhor ou descartar do MVP |
| 09 | Modo decisão | Média | Alta | 🟡 | Heurística cruza 4-5 fatores (dia, hora, distância, clima, companhia) sem pesos definidos |
| 10 | "Estou na rua agora" | Alta | Alta | 🟢 | Geofencing por raio é padrão conhecido |
| 11 | "Quero ir" | Alta | Alta | 🟢 | CRUD simples, necessidade central da Bianca já validada |
| 12 | Listas nomeadas | Alta | Alta | 🟢 | Extensão direta do 11 |
| 13 | Copiar lista com crédito | Média | Alta | 🟡 | Falta definir o que acontece quando a lista original muda depois de copiada (versionar? snapshot?) |
| 14 | Avaliação mínima válida | Alta | Alta | 🟢 | Simplificação de UI sobre modelo já existente |
| 15 | Recorrência | Alta | Alta | 🟢 | Contagem sobre dado que o app já coleta |
| 16 | Modo silencioso | Média | Alta | 🟡 | Cruza dois sistemas (feed + agregação) que precisam concordar sobre "conta no dado, some do feed" |
| 17 | Perfil alimentar | Alta | Alta | 🟢 | Tags fixas + filtro de feed, padrão conhecido |
| 18 | Crowd-tagging | Média | Alta | 🟡 | Falta definir o N mínimo de confirmações por categoria |
| 19 | Categoria "Lugares para atividade" | Alta | Média | 🟡 | Campos como "segurança percebida" são subjetivos — como validar/agregar isso não está fechado |
| 20 | "Está aberto agora?" | Alta | Alta | 🟢 | Flag + timestamp, resolve falha conhecida dos concorrentes |
| 21 | Card compartilhável com deep link | Média | Alta | 🟡 | Deep link + preview rico fora do app é trabalho de infraestrutura de plataforma, não só de produto |
| 22 | Perfil de dono verificado | Média | Alta | 🟡 | Processo de verificação de titularidade (documento? aprovação manual?) ainda não desenhado |
| 23 | Painel com série temporal | Média | Alta | 🟡 | Fartamente justificado o que fazer; o como (agregação temporal + visualização) é o item de front+back mais pesado do corte |
| 24 | Resposta do estabelecimento | Alta | Alta | 🟢 | Campo rotulado vinculado à avaliação, sem ambiguidade |
| 25 | Slot patrocinado (Destaque) | Alta | Alta | 🟢 | Sem leilão nem lógica de ads complexa no MVP — é um card fixo e rotulado |
| 26 | Suspensão automática do Destaque | Alta | Alta | 🟢 | Regra simples: nota abaixo do piso desativa o slot |
| 27 | Faixa de preço reportada | Alta | Alta | 🟢 | Campo numérico agregado, sem ambiguidade |
| 28 | Couvert / taxa 10% | Alta | Alta | 🟢 | Campos booleanos confirmados pela comunidade |
| 29 | Fila ao vivo + histórica | Média | Alta | 🟡 | "Ao vivo" exige reporte ativo e regra de decaimento (quando a informação vira obsoleta) |
| 30 | Categorias de comida caseira | Alta | Alta | 🟢 | Categoria + atributos, mesmo padrão do 19 sem a subjetividade dos campos |

**Leitura do semáforo**: 18 de 30 funcionalidades estão em 🟢, 10 em 🟡 e 2 em 🔴 — sendo a 08 a única no quadrante que a técnica manda questionar diretamente (**X**). Isso confirma o que o próprio corte de 30 já sinalizava: "gêmeo de gosto" foi reintroduzido por risco, não por clareza — vale gastar uma rodada de discussão em equipe só nela e no match de gosto (07) antes de comprometer esforço de implementação.

## 2. Tabela esforço, negócio e UX

Esforço: E (baixo) · EE (médio) · EEE (alto). Valor de negócio: $ (baixo) · $$ (médio) · $$$ (alto). Valor de UX: ♥ (baixo) · ♥♥ (médio) · ♥♥♥ (alto).

| # | Funcionalidade | Esforço | Valor de negócio | Valor de UX |
|---|---|---|---|---|
| 01 | Avaliação em 3 eixos | E | $$$ | ♥♥ |
| 02 | Avaliação contextual | EE | $$ | ♥ |
| 03 | Bloqueio de reavaliação | E | $$ | ♥ |
| 04 | Log de auditoria | EE | $$ | ♥ |
| 05 | Feed "Amigos foram aqui" | EE | $$$ | ♥♥♥ |
| 06 | Card com fonte de confiança | E | $$$ | ♥♥♥ |
| 07 | Match de gosto (%) | EEE | $$ | ♥♥ |
| 08 | Sugestão de "gêmeo de gosto" | EEE | $ | ♥ |
| 09 | Modo decisão | EE | $$ | ♥♥♥ |
| 10 | "Estou na rua agora" | E | $$ | ♥♥♥ |
| 11 | "Quero ir" | E | $$ | ♥♥♥ |
| 12 | Listas nomeadas | E | $$ | ♥♥ |
| 13 | Copiar lista com crédito | EE | $$ | ♥♥ |
| 14 | Avaliação mínima válida | E | $$ | ♥♥♥ |
| 15 | Recorrência | E | $$$ | ♥♥ |
| 16 | Modo silencioso | E | $ | ♥♥ |
| 17 | Perfil alimentar | E | $$ | ♥♥ |
| 18 | Crowd-tagging | EE | $$ | ♥♥ |
| 19 | Categoria "Lugares para atividade" | EE | $ | ♥♥ |
| 20 | "Está aberto agora?" | E | $$ | ♥♥♥ |
| 21 | Card compartilhável com deep link | EE | $$ | ♥♥ |
| 22 | Perfil de dono verificado | EE | $$$ | ♥ |
| 23 | Painel com série temporal | EEE | $$$ | ♥♥ |
| 24 | Resposta do estabelecimento | E | $$ | ♥♥ |
| 25 | Slot patrocinado (Destaque) | EE | $$$ | ♥ |
| 26 | Suspensão automática do Destaque | E | $$ | ♥ |
| 27 | Faixa de preço reportada | E | $$ | ♥♥ |
| 28 | Couvert / taxa 10% | E | $ | ♥♥ |
| 29 | Fila ao vivo + histórica | EE | $$ | ♥♥ |
| 30 | Categorias de comida caseira | E | $$ | ♥♥ |

## Leitura cruzada (semáforo × esforço/valor)

- **Melhor combinação (🟢 + baixo esforço + alto valor)**: 01, 06, 10, 11, 15, 20, 27 — candidatas naturais a entrar cedo no roteiro de implementação, sem necessidade de mais discussão.
- **Alto esforço mesmo estando 🟢 (23, 25, 07 quando resolvido)**: confiança não elimina o trabalho — 23 (painel com série temporal) é o item mais caro do corte mesmo com requisito claríssimo; vale isolar como entrega própria, não empacotar com o resto do Bloco 6.
- **🟡 que bloqueiam outras funcionalidades**: 05 (feed de amigos) é pré-requisito de 06, e sua confiança técnica depende de um grafo social ainda não desenhado — esse é o primeiro 🟡 a esclarecer, porque trava o Bloco 1 inteiro.
- **🔴/X que merecem decisão explícita da equipe**: 07 e 08 — antes de estimar esforço de verdade, a equipe precisa decidir se entram no MVP como estão, se viram versão simplificada (ex.: match de gosto binário — "temos gosto parecido: sim/não" — em vez de percentual), ou se saem do escopo do semestre.
