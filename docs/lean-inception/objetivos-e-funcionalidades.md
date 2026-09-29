# NaÁrea — Objetivos do Produto e Funcionalidades

> Fase 3 (Semanas 7–9) — Lean Inception + BMAD. Ancorado nas personas Toni, Paola e Bianca.
>
> A sessão de brainstorming gerou 144 ideias e 127 funcionalidades candidatas. Este documento traz o **corte de 30**, obtido por convergência Impacto × Esforço. A lista completa e o processo estão preservados em `_bmad-output/brainstorming/brainstorm-funcionalidades-naarea-2026-09-08/` (`.memlog.md` e `brainstorm.html`).

## Objetivos do Produto

| # | Objetivo | Métrica |
|---|---|---|
| **1. Confiança** | Fazer com que a decisão de onde ir venha de pessoas reais e rastreáveis, nunca de nota anônima ou paga. | % de decisões originadas de card com fonte de confiança explícita (amigo, gêmeo de gosto, morador local) |
| **2. Decisão rápida** | Levar o usuário da abertura do app à decisão em até 2 toques e menos de 30s, sem exigir produção de conteúdo. | Taxa de sessões que terminam em decisão; tempo mediano até a decisão |
| **3. Ciclo saudável dos dois lados** | Dar ao estabelecimento um canal legítimo de reputação (responder e corrigir, nunca se auto-avaliar) que alimente a monetização sem corromper a avaliação. | Índice de responsividade médio; taxa de Destaques suspensos por queda de nota |

O Objetivo 2 amarra no critério de aceite de **Usabilidade** e o Objetivo 3 no log de auditoria da **Integridade**, ambos definidos em `tradeoffs-arquitetura.md`.

## Personas de referência

| Persona | Papel | Necessidade central |
|---|---|---|
| **Toni** — 33a, técnico de enfermagem | Consumidor | Encontrar comida caseira/saudável e lugares para correr, com base em onde seus contatos vão |
| **Paola** — 45a, chef e dona de restaurante | Estabelecimento | Ver num lugar só o que os clientes acham da comida, do ambiente e do atendimento |
| **Bianca** — 27a, publicitária | Consumidora silenciosa | Confiar em quem segue para decidir rápido, sem ter que produzir conteúdo em troca |

## Método do corte

Convergência **Impacto × Esforço**, calibrada para um MVP acadêmico de um semestre. Cada funcionalidade candidata foi pontuada por: quantos dos 3 Objetivos do Produto atende, quantas personas serve, esforço de implementação, e se é guardrail obrigatório das Fases 1 e 2. Sobreviveram **30**, distribuídas de forma que **nenhuma persona fique meio atendida** e que os **3 objetivos tenham funcionalidade correspondente**.

---

## As 30 Funcionalidades

Legenda: ⭐ = achado estruturante da sessão · 🇧🇷 = diferencial cultural (não modelado por Yelp/Google Maps/Foursquare)

### Bloco 0 — Fundação e guardrails (4)

Decisões de modelo de dados, não telas. Baratas de decidir agora, caras de corrigir depois.

| # | Funcionalidade | Personas | Por que entra |
|---|---|---|---|
| 01 | ⭐ Avaliação em 3 eixos — comida, ambiente, atendimento (nunca nota única) | Todas | É o dado primitivo do produto e atende sozinho a necessidade central da Paola |
| 02 | ⭐ Avaliação contextual — toda avaliação carrega horário e contexto de quando foi feita | Todas | Premissa de modelo; habilita "recentes vs. todas", timeline do local e avaliação de rota por horário sem retrabalho |
| 03 | Bloqueio de reavaliação antes do prazo mínimo | Sistema | Guardrail obrigatório da Fase 1 |
| 04 | Log de auditoria de avaliações, edições e exclusões | Sistema | Critério de aceite de Integridade — prioridade 7 da Fase 2 |

### Bloco 1 — Confiança · Objetivo 1 (4)

| # | Funcionalidade | Personas | Por que entra |
|---|---|---|---|
| 05 | Feed "Amigos foram aqui" — só locais onde ao menos 1 contato avaliou | Toni, Bianca | É a tese do produto virando tela |
| 06 | Card com fonte de confiança explícita (quem foi, com foto e nome) | Toni, Bianca | Sem isso o feed vira Google Maps; é a métrica do Objetivo 1 |
| 07 | Match de gosto — % de afinidade por sobreposição de avaliações | Toni, Bianca | Separa "rede de afinidade" de "lista de amigos" |
| 08 | Sugestão de "gêmeo de gosto" — alto match, ainda não é contato | Toni, Bianca | É o "diferentemente de" da Visão: descobrir gente nova com gosto parecido, não só conhecidos |

### Bloco 2 — Decisão rápida · Objetivo 2 (5)

| # | Funcionalidade | Personas | Por que entra |
|---|---|---|---|
| 09 | ⭐ Modo decisão — o app escolhe 1 lugar da lista por dia, hora, distância e companhia (máx. 2 toques) | Bianca | É literalmente a métrica do Objetivo 2 e do critério de Usabilidade |
| 10 | "Estou na rua agora" — raio de 300m, aberto agora, decide em 1 toque | Todas | Cobre o momento de uso mais frequente com esforço baixo |
| 11 | ⭐ "Quero ir" — salvar sem avaliar, fricção zero, privado por padrão | Bianca | Necessidade central da Bianca; esforço mínimo |
| 12 | Listas nomeadas ("Sábado com as meninas", "Quando meus pais vierem") | Bianca | Sem lista, o "Quero ir" é só uma pilha |
| 13 | ⭐ Copiar lista de quem você segue, com crédito à autora | Bianca | Converte consumo passivo em sinal de qualidade e em status para quem cura |

### Bloco 3 — Contribuição sem fricção (3)

| # | Funcionalidade | Personas | Por que entra |
|---|---|---|---|
| 14 | Avaliação mínima válida — só emoji ou só estrela, texto nunca obrigatório | Bianca | Sem ela o produto não coleta dado nenhum de 1 das 3 personas |
| 15 | ⭐ **Recorrência** — "vezes que voltou" como sinal de qualidade, acima da nota | Todas | Achado central da sessão: sinal mais honesto e mais difícil de manipular que a estrela, derivado de dado que já existe |
| 16 | ⭐ Modo silencioso — discrição no feed, identidade preservada no dado | Bianca | Respeita a Bianca sem violar o guardrail de não-anonimato da Fase 1 |

### Bloco 4 — Comida e corrida · necessidades do Toni (3)

| # | Funcionalidade | Personas | Por que entra |
|---|---|---|---|
| 17 | Perfil alimentar — tags fixadas que filtram o feed inteiro | Toni | Atende a metade "comida saudável/caseira" da necessidade dele |
| 18 | ⭐ Crowd-tagging — tags vêm de quem avaliou, nunca do dono | Toni, Paola | Alimenta o perfil alimentar e protege o guardrail contra manipulação do estabelecimento |
| 19 | Categoria "Lugares para atividade" + campos próprios de rota (iluminação, segurança, piso, sombra, bebedouro) | Toni | Atende a metade "lugares para correr"; sem ela o Toni fica meio servido |

### Bloco 5 — Ficha do local viva (2)

| # | Funcionalidade | Personas | Por que entra |
|---|---|---|---|
| 20 | "Está aberto agora?" confirmado por quem está lá, não pelo horário cadastrado | Todas | Resolve a falha mais comum dos concorrentes com custo baixo |
| 21 | 🇧🇷 Card compartilhável com deep link — funciona para quem não tem o app | Bianca | É como o produto se espalha no Brasil: pelo grupo do zap |

### Bloco 6 — Estabelecimento e modelo de negócio · Objetivo 3 (5)

| # | Funcionalidade | Personas | Por que entra |
|---|---|---|---|
| 22 | Perfil de dono separado do de consumidor, com verificação de titularidade | Paola | Pré-requisito de todo o lado Paola |
| 23 | ⭐ Painel com série temporal dos 3 eixos | Paola | É a necessidade da Paola, literal: "num lugar só" |
| 24 | Resposta do estabelecimento — rotulada, nunca conta como avaliação | Paola | É o canal legítimo de reputação dela; guardrail da Fase 1 preservado |
| 25 | Slot patrocinado separado e rotulado, fora do feed de amigos | Paola | É o modelo de receita descrito na Visão da Fase 1 |
| 26 | ⭐ Suspensão automática do Destaque se a nota cai abaixo do piso | Sistema | O freio que impede a monetização de corromper a avaliação — fecha o Objetivo 3 |

### Bloco 7 — Rituais brasileiros 🇧🇷 (4)

O fosso competitivo do produto: o que Yelp, Google Maps e Foursquare estruturalmente não modelam. São majoritariamente campos, não algoritmo — custo baixo, impacto de posicionamento alto.

| # | Funcionalidade | Personas | Por que entra |
|---|---|---|---|
| 27 | 🇧🇷 Faixa de preço reportada pelo usuário + estimativa de valor por pessoa (rachar a conta) | Bianca, Todas | Vem do usuário e não do dono, então é imune a cardápio desatualizado; e responde à pergunta que o grupo faz antes de sair |
| 28 | 🇧🇷 Campos "cobra couvert?" e "taxa incluída?", confirmados pela comunidade | Todas | Reclamação clássica brasileira que nenhum app importado modela |
| 29 | 🇧🇷 Tempo de fila ao vivo e faixa histórica por horário | Todas | Informação decisiva no Brasil e ausente nos concorrentes |
| 30 | 🇧🇷 Categorias de comida caseira — marmita, quentinha e self-service por quilo | Toni | Atende o Toni em cheio e é uma categoria que os apps importados simplesmente não têm |

---

## Cobertura do corte

| Dimensão | Cobertura |
|---|---|
| **Toni** | 05, 06, 07, 08, 17, 18, 19, 30 — as duas necessidades dele (comida saudável e correr) atendidas |
| **Paola** | 01, 22, 23, 24, 25, 26 — necessidade central atendida, com canal de reputação e receita |
| **Bianca** | 09, 11, 12, 13, 14, 16, 21, 27 — consome, organiza e decide sem precisar publicar |
| **Objetivo 1** | 05, 06, 07, 08, 15, 18 |
| **Objetivo 2** | 09, 10, 11, 12, 13, 14 |
| **Objetivo 3** | 04, 22, 23, 24, 25, 26 |

---

## Funcionalidades Rejeitadas (com motivo)

| Funcionalidade | Motivo da rejeição |
|---|---|
| Avaliação de mão dupla (o estabelecimento avalia o cliente) | Cria medo de avaliar e fere o "Não é" sério/profissional da Fase 1 |
| Pedido, reserva ou pagamento dentro do app | Guardrail explícito da Fase 1 — a transação acontece fora |
| Streak / gamificação de publicação obrigatória | Contradiz frontalmente a persona Bianca. Gamificação permitida apenas em **descoberta** e **curadoria** |
| Dono avaliando o próprio estabelecimento | Guardrail explícito da Fase 1 |
| Avaliação anônima | Guardrail explícito da Fase 1 |

---

## Achados Estruturantes

1. **Sinal ≠ publicação.** Duas das três personas não querem produzir conteúdo público. Salvar, copiar lista, voltar ao lugar e usar o modo decisão são contribuição legítima — o produto trata comportamento passivo como dado de qualidade (funcionalidades 11, 13, 14, 15, 16).
2. **Recorrência acima da nota.** Quantas vezes a pessoa voltou é um sinal mais honesto e mais difícil de manipular que a estrela, e é coletado sem pedir nada. Serve Integridade (prioridade 7) e Usabilidade (prioridade 6) simultaneamente.
3. **Avaliação Contextual é decisão de arquitetura, não funcionalidade.** Precisa ser definida antes do modelo de dados, não durante a implementação (funcionalidade 02).
4. **O caminho legítimo da Paola.** Ela não pode se auto-avaliar, então sua rota para reputação é **responder e corrigir** (24), e a monetização (25) ganha freio embutido na suspensão automática (26).
5. **O fosso é cultural.** O Bloco 7 é o que os concorrentes estruturalmente não modelam — e é onde o NaÁrea é defensável.
