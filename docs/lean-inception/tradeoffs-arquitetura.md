# NaÁrea — Requisitos Não-Funcionais e Trade-offs

> Fase 2 (Semanas 4–6) — Lean Inception + BMAD. Elicitado com a Analista Mary a partir da priorização informal do time (notas de 7 a 1, sendo 7 a mais importante).

## Conclusão

A ordem de prioridade abaixo estabelece a regra de trade-off do projeto: **quando duas qualidades entrarem em conflito numa decisão de arquitetura, a que estiver mais alta nesta lista vence.** Ex.: um cache que acelera o feed (Performance, 5) mas arrisca servir dado desatualizado ou inconsistente (Integridade, 7) deve ser rejeitado ou redesenhado — Integridade vence por estar mais alta na tabela.

## Prioridade dos Requisitos Não-Funcionais

| Prioridade | Requisito | Definição |
|---|---|---|
| 7 (mais alta) | **Integridade** | Os dados permanecem corretos, consistentes e não são alterados indevidamente. |
| 6 | **Usabilidade** | O quanto o sistema é fácil e agradável de utilizar. |
| 5 | **Performance** | Capacidade do sistema de executar operações de forma eficiente: tempo de resposta, latência, throughput, uso de CPU/memória/IO. |
| 4 | **Escalabilidade** | Capacidade de continuar atendendo ao aumento de demanda (distinto de performance: performance é *quão bem* o sistema executa; escalabilidade é *até onde* ele aguenta crescer). |
| 3 | **Rastreabilidade** | Capacidade de acompanhar e relacionar elementos ao longo do ciclo de desenvolvimento. |
| 2 | **Segurança** | Proteção de dados pessoais e do sistema contra acesso, uso ou alteração indevidos. |
| 1 (mais baixa) | **Flexibilidade** | Capacidade do sistema de se adaptar a mudanças. |

## Justificativa da Priorização

- **Integridade no topo** porque toda a proposta de valor do NaÁrea (ver `visao-restricoes.md`) depende de avaliação real e confiável — dado corrompido ou duplicado quebra a confiança que é a essência do produto.
- **Usabilidade em 2º** porque a identidade do produto é "rede social moderna e divertida"; fricção de uso contradiz a proposta.
- **Performance e Escalabilidade nas posições intermediárias** são relevantes (feed por localização em tempo real) mas calibradas para a realidade de um MVP acadêmico de um semestre, não para escala de produção.
- **Rastreabilidade em 3º** serve tanto ao processo (ciclo BMAD entre as fases) quanto, potencialmente, à auditoria de ações do usuário — **ainda a esclarecer**, ver Pendências.
- **Segurança em 2º lugar, deliberadamente abaixo de Performance, Escalabilidade e Rastreabilidade — decisão intencional confirmada pelo time.** Não é descuido: para o escopo do MVP acadêmico, prioriza-se robustez funcional sobre hardening de segurança. Isso não isenta o produto de requisitos mínimos de segurança (dado que trata localização e identidade real), apenas não os trata como o critério decisório dominante.
- **Flexibilidade em último** porque o MVP não precisa se manter adaptável por anos — é um projeto de um semestre.

## Critérios de Aceite por Requisito

- **Integridade — resolvido.** Todo dado sensível (avaliações, edições, exclusões) gera **log de auditoria** com autor, timestamp e ação. Cobre "alteração indevida": qualquer edição fora das regras já definidas no `visao-restricoes.md` (dono avaliando o próprio negócio, reavaliação antes do prazo, avaliação sem localização) deve ficar rastreada e bloqueável.
- **Usabilidade — resolvido.** Qualitativo: interface bonita, intuitiva, agradável de usar (alinhado ao É "moderna e divertida"). Quantitativo: completar uma avaliação em até 3–4 toques e menos de 30s; achar um lugar recomendado em até 2 toques a partir da abertura do app.
- **Performance — resolvido.** Feed e telas carregam em até 2–3s em conexão 4G comum.
- **Escalabilidade — resolvido.** Meta realista para um MVP acadêmico, não escala de produção: suportar dezenas a poucas centenas de usuários simultâneos sem degradação perceptível — suficiente para demo e avaliação da disciplina.
- **Rastreabilidade — resolvido.** Cobre as duas dimensões: rastreabilidade de **dado do usuário** (quem avaliou o quê, quando — via o log de auditoria da Integridade) e rastreabilidade de **processo** (decisões e requisitos acompanháveis entre as fases do BMAD, via os docs de `docs/lean-inception/` e os memlogs).
- **Segurança — resolvido.** "Básico" definido como: autenticação de usuário (senha com hash, nunca em texto puro), tráfego sempre em HTTPS, controle de acesso (usuário só edita/exclui o próprio conteúdo), e proteção de dados pessoais compatível com a LGPD (dado que o produto trata localização e identidade real vinculada às avaliações) — piso mínimo aceitável mesmo com Segurança em prioridade 2.
