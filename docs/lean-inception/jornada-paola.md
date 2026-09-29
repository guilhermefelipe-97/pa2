# NaÁrea — Mapa de Jornada: Paola

> Fase 3 (Semanas 7–9) — Lean Inception + BMAD. Técnica: Mapa de Jornada do Usuário, ancorada na persona e nas 30 funcionalidades de `objetivos-e-funcionalidades.md`.

## Persona e objetivo

**Paola** — 45 anos, chef e dona de restaurante. Necessidade central: ver num lugar só o que os clientes acham da comida, do ambiente e do atendimento — hoje isso está espalhado entre nota única de outros apps, comentário de Instagram e conversa de salão.

**Objetivo desta jornada**: descobrir *por que* o movimento caiu, agir sobre a causa certa e recuperar reputação por um caminho legítimo — sem poder se auto-avaliar (guardrail da Fase 1).

*(A tensão que define esta persona: ela é a fonte de receita do produto e a parte com maior incentivo a manipular a avaliação. A jornada precisa dar a ela poder de correção sem dar poder de distorção.)*

## Ponto de partida

Duas semanas de movimento em queda no jantar. A Paola não sabe se é sazonalidade, se é preço, se é a equipe nova da noite. O gatilho é de negócio e difuso — sem um painel que separe os eixos, ela age no palpite e troca o que não estava quebrado.

## Jornada

| # | Etapa | Ação da Paola | Pensamento / Sentimento | Touchpoint (funcionalidade) | Dor ou oportunidade |
|---|---|---|---|---|---|
| 1 | Gatilho | Percebe queda no jantar por duas semanas seguidas | "Caiu o quê? A comida tá boa, eu provo todo dia" | — | Sem dado segmentado, ela culpa o alvo errado |
| 2 | Acesso | Entra no perfil de dono, já verificado como titular | "Pelo menos aqui eu falo como o restaurante, não como cliente" | Perfil de dono separado com verificação de titularidade (22) | Se não fosse separado, a linha entre dono e avaliador some — e o guardrail cai junto |
| 3 | Diagnóstico | Abre o painel e vê os 3 eixos em série temporal | "Comida estável, ambiente estável — **atendimento** despencou em julho" | Painel com série temporal dos 3 eixos (23) sobre avaliação em 3 eixos (01) | É a necessidade dela, literal: "num lugar só". Nota única teria escondido o problema numa média |
| 4 | Correlação | Cruza a queda com o que mudou na operação | "Julho foi quando trocou a equipe da noite" | Avaliação contextual — horário e contexto em toda avaliação (02) | O recorte por horário confirma: a queda é só no turno da noite |
| 5 | Leitura qualitativa | Lê as avaliações recentes do turno da noite | (incômodo, mas é informação que ela nunca teve organizada) | 02 + crowd-tagging (18) | As tags vêm de quem avaliou, não dela — ela não pode maquiar o rótulo do próprio negócio |
| 6 | Tentação | Pensa em pedir para conhecidos avaliarem bem | "Se eu chamar uns amigos pra dar cinco estrelas isso resolve" | Log de auditoria (04) + bloqueio de reavaliação (03) | **Momento crítico do produto**: o caminho fácil precisa estar fechado, e o caminho legítimo precisa estar visível na mesma tela |
| 7 | Ação legítima | Responde publicamente às avaliações do turno da noite | "Dá pra explicar o que mudou e o que eu vou fazer" | Resposta do estabelecimento, rotulada, nunca conta como avaliação (24) | É a rota dela para reputação: **responder e corrigir**, medida por índice de responsividade (Objetivo 3) |
| 8 | Correção operacional | Ajusta escala e treina a equipe da noite | "O problema é real, não é implicância de cliente" | — | O produto gerou mudança fora do app — é o sinal de que o dado serviu |
| 9 | Investimento | Compra o Destaque para recuperar movimento | "Agora que arrumei, quero ser visto de novo" | Slot patrocinado separado e rotulado, fora do feed de amigos (25) | Receita entra sem contaminar o feed de confiança — o anúncio é visível como anúncio |
| 10 | Freio | Sabe que o Destaque cai sozinho se a nota cair | "Não adianta pagar se o serviço piorar de novo" | Suspensão automática do Destaque abaixo do piso (26) | Alinha incentivo econômico e qualidade real — fecha o Objetivo 3 |
| 11 | Acompanhamento | Volta ao painel semanalmente e vê o eixo atendimento subir | (alívio e senso de controle) | 23 + recorrência como sinal de qualidade (15) | Recorrência mostra recuperação antes da nota média se mover |

## Leitura da jornada

- **Onde o produto ganha**: etapas 3–4. Separar os 3 eixos e carregar contexto em cada avaliação transforma "o movimento caiu" em "o atendimento da noite caiu desde julho". É diagnóstico, não termômetro — nenhum concorrente com nota única entrega isso.
- **Onde o produto é frágil**: etapa 6. Se o caminho legítimo (responder/corrigir) não estiver tão à mão quanto a tentação de manipular, a Paola procura o atalho fora do app — e a integridade do produto vira política, não arquitetura.
- **Achado que essa jornada confirma**: a tensão "ela quer visibilidade mas não pode se avaliar" se resolve sozinha quando a rota de reputação é responder e corrigir (24), com a monetização (25) freada pela suspensão automática (26).
- **Gap não coberto pelo corte de 30**: a Paola marcar eventos internos no gráfico ("troquei a equipe da noite em julho") ficou de fora — na etapa 4 ela faz essa correlação de cabeça. É a candidata mais forte para a primeira iteração pós-MVP, porque é anotação privada dela e não toca no guardrail de avaliação.
