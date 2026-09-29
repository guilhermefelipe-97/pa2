# NaÁrea — Funcionalidades nas Jornadas

> Fase 3 (Semanas 7–9) — Lean Inception + BMAD. Atividade de cruzamento: o grupo das jornadas lê o passo a passo em voz alta, o grupo das funcionalidades identifica as combinações e prega o post-it no passo correspondente.
>
> Entradas: os três mapas de jornada (`jornada-toni.md`, `jornada-paola.md`, `jornada-bianca.md`) e as 30 funcionalidades de `objetivos-e-funcionalidades.md`.
>
> **Identificador do post-it** = o número da funcionalidade no corte de 30 (`F01`–`F30`). Combinações novas, surgidas durante a leitura e ainda fora do corte, recebem `N31`+ e estão isoladas no fim do documento — elas **não** entram no MVP sem decisão explícita.

## Como ler as tabelas

| Coluna | O que significa |
|---|---|
| **Post-its** | Funcionalidades já pregadas no passo pela própria jornada |
| **Novos post-its** | Combinações identificadas *durante esta atividade* — a funcionalidade existe no corte de 30, mas a jornada não a tinha citado |
| **Leitura do grupo** | Por que a combinação atende ou melhora aquele passo |

---

## Jornada 1 — Toni (almoço no intervalo do plantão)

| # | Passo | Post-its | Novos post-its | Leitura do grupo |
|---|---|---|---|---|
| 1 | Gatilho | — | — | Passo fora do app. Nenhuma funcionalidade atende — e não deveria |
| 2 | Abertura | F17 | — | Perfil alimentar fixado carrega o feed já filtrado |
| 3 | Descoberta | F05, F06 | **F07** | O feed melhora se ordenar por match de gosto, não só por "tem amigo" — o colega de plantão que come igual a ele vale mais que o contato genérico |
| 4 | Refinamento | F30, F18 | — | Combinação forte: a tag vem de quem avaliou e alimenta a categoria de comida caseira |
| 5 | Checagem de custo | F27 | **F28** | Se a pergunta é "cabe no orçamento", couvert e taxa entram na mesma checagem — hoje estavam só na Bianca |
| 6 | Decisão | — | **F10** | Toni está na rua, com 40 min. "Estou na rua agora" (raio de 300m, aberto agora, 1 toque) é exatamente este passo — a jornada tinha registrado F10 como *não coberta*, e o cruzamento mostra que ela é o passo 6 |
| 7 | Chegada | F20 | **F29** | Ele teme fila tanto quanto cozinha fechada. Fila ao vivo melhora o passo sem custo novo |
| 8 | Experiência | — | — | Passo fora do app, por desenho |
| 9 | Contribuição leve | F15 | **F02** | A recorrência só é sinal confiável porque cada visita carrega horário e contexto — o passo depende de F02 |
| 10 | Reforço de rede | F14 | **F03, F16** | F03 impede que ele reavalie no mesmo dia e infle o sinal; F16 permite avaliar sem expor rotina de plantão |

**Achado desta jornada**: F10 e F19 estavam marcadas como não usadas. O cruzamento resolveu F10 (é o passo 6). **F19 continua órfã** — porque a segunda necessidade do Toni (lugares para correr) nunca virou jornada. Ou se escreve o mapa da corrida, ou F19 sai do MVP por falta de jornada que a justifique.

---

## Jornada 2 — Paola (queda no movimento do jantar)

| # | Passo | Post-its | Novos post-its | Leitura do grupo |
|---|---|---|---|---|
| 1 | Gatilho | — | — | Percepção de salão, fora do app |
| 2 | Acesso | F22 | — | Verificação de titularidade é pré-requisito, não melhoria |
| 3 | Diagnóstico | F23, F01 | — | Combinação central: a série temporal só existe porque o dado nasce em 3 eixos |
| 4 | Correlação | F02 | — | O recorte por horário é o que isola o turno da noite |
| 5 | Leitura qualitativa | F02, F18 | **F15** | Recorrência caindo no turno da noite é o sinal mais precoce que ela tem — aparece antes de a média se mover |
| 6 | Tentação | F04, F03 | **F26** | A suspensão automática precisa estar *visível* neste passo, não só na etapa 10: é ela que torna a manipulação economicamente inútil |
| 7 | Ação legítima | F24 | — | Rota de reputação dela |
| 8 | Correção operacional | — | — | Passo fora do app. É a prova de que o dado serviu |
| 9 | Investimento | F25 | **F23** | O painel precisa mostrar o funil do Destaque (impressões → visitas → salvamentos), senão ela compra às cegas |
| 10 | Freio | F26 | — | Fecha o Objetivo 3 |
| 11 | Acompanhamento | F23, F15 | **F20** | Quem confirma "está aberto agora" no jantar é o mesmo cliente que ela está tentando recuperar |

**Achado desta jornada**: nenhuma funcionalidade nova ficou órfã, mas o passo 9 revelou que **F25 sem F23 é venda sem prestação de contas**. As duas viram uma dupla obrigatória no sequenciador.

---

## Jornada 3 — Bianca (sábado com as amigas)

| # | Passo | Post-its | Novos post-its | Leitura do grupo |
|---|---|---|---|---|
| 1 | Gatilho passivo | F05 | **F25** | Único ponto da jornada dela em que o slot patrocinado é legítimo: ela está em consumo passivo, e o anúncio está rotulado e fora do feed de amigos |
| 2 | Interesse | F06 | — | Nome e foto são o que substituem a nota |
| 3 | Captura | F11 | — | Passo que define a persona |
| 4 | Organização | F12 | — | Sem lista, o "Quero ir" morre |
| 5 | Ampliação | F13 | — | Consumo passivo virando sinal |
| 6 | Expansão de rede | F07, F08 | — | O "diferentemente de" da Visão |
| 7 | Sábado — decisão | F09 | **F10** | Ela já saiu de casa: "estou na rua agora" e modo decisão são o mesmo momento por dois caminhos. Definir no sequenciador se são uma funcionalidade ou duas |
| 8 | Checagem do grupo | F27, F28 | — | A pergunta que o grupo faz antes de sair |
| 9 | Checagem de fila | F29 | — | Ausente nos concorrentes |
| 10 | Compartilhamento | F21 | **F13** | O card compartilhado puxa a lista de origem com crédito — é assim que a curadora ganha alcance fora do app |
| 11 | Pós-experiência | F14 | — | Texto nunca obrigatório |
| 12 | Discrição | F16 | — | Discrição sem anonimato |
| 13 | Sinal involuntário | F15 | **F02** | Mesmo achado da jornada do Toni: recorrência depende de contexto por visita |

**Achado desta jornada**: F13 apareceu duas vezes (passos 5 e 10) por caminhos diferentes — copiar e compartilhar. É a funcionalidade com maior alcance de rede do corte.

---

## Resultado do cruzamento

### Funcionalidades presentes nas três jornadas

`F02` · `F15` — contexto por avaliação e recorrência. São infraestrutura, não tela: se qualquer uma sair, as três jornadas quebram em algum passo. Vão no início do sequenciador.

### Funcionalidades que ganharam passo novo nesta atividade

| ID | Jornada onde apareceu | Passo |
|---|---|---|
| F02 | Toni, Bianca | Contribuição leve / Sinal involuntário |
| F03 | Toni | Reforço de rede |
| F07 | Toni | Descoberta |
| F10 | Toni, Bianca | Decisão / Sábado — decisão |
| F13 | Bianca | Compartilhamento |
| F15 | Paola | Leitura qualitativa |
| F16 | Toni | Reforço de rede |
| F20 | Paola | Acompanhamento |
| F23 | Paola | Investimento |
| F25 | Bianca | Gatilho passivo |
| F26 | Paola | Tentação |
| F28 | Toni | Checagem de custo |
| F29 | Toni | Chegada |

### Funcionalidade órfã — nenhuma jornada a reivindica

| ID | Funcionalidade | Encaminhamento |
|---|---|---|
| **F19** | Categoria "Lugares para atividade" + campos de rota | Escrever o mapa de jornada da corrida do Toni **ou** tirar F19 do MVP. Manter funcionalidade sem jornada contradiz o método |

### Passos sem funcionalidade — e está certo assim

Toni 1 e 8 · Paola 1 e 8 · nenhum na Bianca. São passos que acontecem fora do app (fome, comer, perceber a queda, treinar a equipe). Cobri-los seria expandir escopo, não atender persona.

---

## Combinações novas fora do corte de 30

Surgiram na leitura e **não entram no MVP sem decisão explícita**. Registradas para o backlog:

| ID | Funcionalidade | Passo que a pediu | Por que ficou de fora agora |
|---|---|---|---|
| **N31** | Anotação privada de evento interno na série temporal ("troquei a equipe da noite em julho") | Paola, passo 4 | Não toca guardrail e é barata, mas a Paola consegue fazer a correlação de cabeça no MVP |
| **N32** | Reconhecimento de quem cura listas (alcance, número de cópias) | Bianca, passo 5 | É o risco mais sério do corte: a jornada da Bianca **assume** curadoras que nenhuma funcionalidade alimenta. Se o MVP não gerar curadoria, F13 fica sem matéria-prima |

**Recomendação da analista**: N32 não é backlog comum — é uma dependência não declarada da jornada da Bianca. Tratar como pergunta em aberto no sequenciador, não como ideia guardada.
