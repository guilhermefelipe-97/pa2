---
title: 'Onda 5 — Titularidade, tags comunitárias e perfil alimentar'
type: 'feature'
created: '2026-10-30'
status: 'done'
baseline_commit: '582d3b7c3e630a6dcba42cab1cb7a8b7f589e5f6'
review_loop_iteration: 0
context:
  - '{project-root}/docs/lean-inception/visao-restricoes.md'
  - '{project-root}/docs/lean-inception/sequenciador-mvp.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** A onda 5 ainda não existe: Paola não tem identidade verificada de estabelecimento e Toni não pode fixar preferências apoiadas em tags comunitárias.

**Approach:** Entregar F22, F18 e F17 juntas, conforme pedido. As definições abaixo são propostas para aprovação, pois verificação e quórum estão abertos nos documentos.

## Boundaries & Constraints

**Always:**
- F22: pedido privado por usuário/local existente; área “Meus estabelecimentos” separada do perfil consumidor, acessível em “Você”. Pedido na ficha do local, persistindo antes locais apenas descobertos. Um titular por local; vários locais por titular.
- Cliente cria `users/{uid}/ownershipRequests/{placeId}` com `status: pending`, `createdAt` do servidor. Só solicitante lê; alterações de status somente administrativas. Sem documentos pessoais. Repetir pedido mostra o existente.
- `placeOwners/{placeId}` contém `uid`, `verifiedAt`; autenticados leem, cliente nunca escreve. Script Admin SDK aprova/rejeita pedidos e revoga titularidade; aprovação transacional impede substituir outro titular. Operador verifica titularidade fora do app e registra a decisão; execução real depende de credenciais e decisão humana.
- Titular verificado não cria avaliações, visitas nem relatos de aberto/preço no próprio negócio: bloquear nas Rules e explicar na UI. Outros locais continuam disponíveis. Conteúdo antigo é preservado; tags do titular atual são excluídas do quórum.
- F18: tags opcionais na avaliação: `caseiro`, `vegetariano`, `vegano`, `low-carb`, `integral`. Lista sem duplicatas; ausência significa vazia; mínimo de avaliação atual permanece. Não editar reviews nem escrever contadores pelo cliente.
- Tag confirmada = pelo menos 3 autores distintos, considerando apenas a avaliação mais recente de cada autor/local (empate por id), excluindo titular atual. Última avaliação sem tags retira o voto anterior. Confirmadas aparecem na ficha e nos cards, com contagem e origem comunitária.
- F17: preferências privadas em `users/{uid}/preferences/food`, mesmo vocabulário; todas as tags selecionadas devem estar confirmadas (AND). Sem seleção mantém feed atual. Filtrar todos os cards do feed de amigos, preservando fontes e ordenação; não adicionar recomendações de desconhecidos. Perto, Quero ir e decisão ficam fora do filtro nesta onda.
- Preferências persistem entre sessões; troca de conta limpa estado e descarta respostas antigas. Enquanto preferências/quórum falham, não mostrar cards incompatíveis: erro com tentar novamente. Vazio filtrado explica motivo e oferece editar/limpar filtro.

**Ask First:** Mudar quórum, vocabulário, alcance do filtro ou conceder titularidade real.

**Never:** Autoaprovação, upload de documentos, alegar segurança para alergias; painel F23, respostas F24 ou anúncios F25; alterar notas/auditoria existentes.

## I/O & Edge-Case Matrix

| Cenário | Entrada | Resultado | Falha |
|---|---|---|---|
| Titularidade | Pedido pendente | Sem poderes até aprovação administrativa | Sem autoaprovação |
| Integridade | Titular tenta contribuir no próprio local | Negado mesmo por chamada direta | Mensagem clara |
| Quórum | Mesmo autor avalia 3 vezes | Conta só uma vez | Tags inválidas negadas |
| Preferência | Vegano e integral | Apenas locais com ambas confirmadas | Sem dados não corresponde |
| Sessão | Conta muda durante leitura | Só dados da nova conta | Descartar resposta antiga |

</frozen-after-approval>

## Code Map

- `firebase/firestore.rules:17` — perfil público com chaves exatas; não colocar preferências ou poderes nele. `:403`, `:458`, `:501` — validar review/visit/report; preservar limites do batch com foto/auditoria.
- `app/lib/domain/models/place_activity_review.dart:4` — Review/NewReview; `data/firebase/firestore_review_repository.dart:146`, `:267` — batch e parse.
- `app/lib/ui/review/review_view_model.dart:109`, `:308` — bloqueio e envio; `review_view.dart` — formulário.
- `app/lib/ui/feed/feed_view_model.dart:128` — carga de amigos tem limite, inadequada para quórum global; `domain/feed.dart:210` preserva agrupamento.
- `app/lib/ui/saved/saved_places_store.dart` — padrão de assinatura da autenticação e descarte de respostas antigas.
- `app/lib/main.dart:99`, `routing/router.dart:189`, `ui/profile/profile_view.dart:86`, `ui/place/place_detail_view.dart:285` — providers, rotas e entradas.
- `firebase/seed/seed.js:48` — configuração Admin SDK, emulador e credenciais externas; não alterar seed de locais.

## Tasks & Acceptance

**Execution:**
- [x] `firebase/firestore.rules`, `firebase/tests/firestore.rules.test.js` — proteger titularidade, preferências, tags e contribuições; testar forjas e batch máximo.
- [x] `firebase/seed/manage-ownership.js`, `firebase/tests/ownership.test.js`, `docs/ownership.md` — decisões administrativas testáveis e procedimento de verificação/revogação.
- [x] `app/lib/domain/food_tags.dart`, `domain/models/place_activity_review.dart`, `data/firebase/firestore_review_repository.dart` — tags e quórum puro; leitura global por locais candidatos em lotes de 30, sem corte silencioso; excluir titular atual.
- [x] `app/lib/data/repositories/owner_repository.dart`, `data/firebase/firestore_owner_repository.dart`, `ui/owner/` — pedidos, área separada e estados pendente/aprovado/rejeitado.
- [x] `app/lib/ui/review/`, `ui/visit/`, `ui/open/` — checar titularidade, comunicar bloqueio e manter servidor autoritativo.
- [x] `app/lib/data/repositories/dietary_repository.dart`, `data/firebase/firestore_dietary_repository.dart`, `ui/dietary/` — persistência privada, store por sessão e editor de preferências.
- [x] `app/lib/ui/feed/`, `ui/place/`, `ui/profile/`, `routing/`, `main.dart` — integrar tags, filtros e entradas; atualizar fakes/harness e testes de regressão.

**Acceptance Criteria:**
- Given pedido pendente, when operador aprova após verificação externa, then área mostra titularidade e Rules impedem contribuição no próprio local.
- Given três consumidores confirmaram uma tag, when Toni fixa essa preferência e reinicia sessão, then feed continua filtrado sem perder identidade das fontes.
- Given dados anteriores à onda, when app carrega sem preferências, then avaliações e feed existentes continuam válidos.

## Spec Change Log

## Design Notes

Calcular quórum a partir das reviews globais apenas dos locais candidatos; nunca inferir confirmação usando só amigos ou uma página truncada. Aceitável para escala acadêmica; agregação administrativa futura exige nova decisão. Tags não são certificações nutricionais.

## Verification

- `cd app; flutter analyze` — sem problemas.
- `cd app; flutter test` — testes novos e regressões passam.
- `cd firebase; npm run test:emulator` — Rules, administração e integridade passam, incluindo batch máximo.
- Conferir pedido, aprovação em emulador, bloqueio do titular, editor, persistência e vazio filtrado. Sem deploy nem alteração de titularidade em produção.

## Execution record — 2026-10-30

- Implementadas F22, F18 e F17; escopo congelado preservado.
- Análise Flutter: `analyze --no-pub` sem problemas (9,5 s).
- Suíte Flutter completa: 1048 testes passaram (1 min 24 s).
- `npm run test:emulator` com JDK 21: 315 testes passaram (52 s), incluindo Rules, batch máximo e decisões administrativas concorrentes.
- Widget tests cobrem pedido repetido, entrada separada em Você, bloqueio do titular, editor, preferências persistidas e vazio filtrado. Testes de repositório/store cobrem leitura global com 31 candidatos, mais de 100 avaliações e descarte por sessão.
- Sem deploy, concessão de titularidade ou alteração de dados em produção. Verificação em dispositivo físico não executada.

## Revisão BMAD step04 — patches locais

As três revisões foram tratadas sequencialmente, sem renegociar intenção ou alterar o bloco congelado:

1. Preferências têm sequência por operação; saves invalidam loads anteriores e loads não concorrem com save em andamento. Regressões usam Completers e respostas invertidas.
2. Editor usa scroll, suporta viewport baixo/texto ampliado e só fecha a rota se ainda estiver montado após salvar. Teste cobre saída durante save.
3. Detalhe descarta sucessos e falhas de tags superados por uma leitura posterior.
4. Lookups de titularidade têm timeout de 5 segundos nos checks e submits de avaliação, visita e aberto; testes verificam liberação de estado após leitura pendente.
5. Revogação registra decisão separada e preserva aprovação, operador, motivo e data originais; teste administrativo verifica o histórico.
6. Titular conhecido vê restrição antes do convite de localização, inclusive sem permissão concedida.
7. Meus estabelecimentos mantém uma carga por conta/refresh, consulta nomes em lote e usa lista lazy; rebuild não repete consultas e troca de conta descarta dados.
8. Tags malformadas viram lista vazia sem descartar a review válida, impedindo ressuscitar voto anterior; testes incluem tipos inválidos, duplicatas e vocabulário estranho.
9. Procedimento documenta descoberta de pedidos/UID/local via Admin SDK no emulador e combinação da verificação externa com solicitante.
10. Regressões de local descoberto verificam ordem persistência/pedido, falha de persistência e troca de conta durante persistência.
11. Testes de formulário e repositório verificam seleção/desseleção e persistência de NewReview.tags não vazia.
12. Widget test verifica tag confirmada por três autores com contagem e origem comunitária no card e na ficha.

Status mantido em in-review para encerramento do step05. Sem deploy ou alteração de titularidade/dados em produção.

### Verificação após patches da revisão

- Flutter `analyze --no-pub`: sem problemas (13,0 s).
- Flutter `test --no-pub --reporter expanded`, suíte completa: **1061 testes passaram** (2 min 33 s).
- Firebase `npm run test:emulator` com JDK 21, suíte completa: **315 testes passaram** (2 min).
- `git diff --check` e `node --check firebase/seed/manage-ownership.js`: passaram.
- Logs de validação ficam em work/ fora do repositório; nenhum script temporário foi adicionado.


## Suggested Review Order

**Integridade e titularidade**

- Servidor impede contribuições do titular no próprio local.
  [firestore.rules:22](../../firebase/firestore.rules#L22)

- Aprovação administrativa transacional preserva decisões e impede substituição acidental.
  [manage-ownership.js:5](../../firebase/seed/manage-ownership.js#L5)

- Pedidos privados são separados das concessões administrativas.
  [firestore.rules:52](../../firebase/firestore.rules#L52)

**Tags da comunidade**

- Última avaliação por pessoa define o voto; titular atual é excluído.
  [food_tags.dart:1](../../app/lib/domain/food_tags.dart#L1)

- Consulta global por candidatos evita confirmar tags com amostra truncada.
  [firestore_review_repository.dart:240](../../app/lib/data/firebase/firestore_review_repository.dart#L240)

**Preferências e sessão**

- Operações antigas são descartadas; preferências permanecem privadas por conta.
  [dietary_store.dart:34](../../app/lib/ui/dietary/dietary_store.dart#L34)

- Filtro AND preserva fontes e ordenação do feed de amigos.
  [feed_view_model.dart:55](../../app/lib/ui/feed/feed_view_model.dart#L55)

**Interface**

- Área do titular usa nomes, consultas reutilizadas e lista sob demanda.
  [owner_view.dart:28](../../app/lib/ui/owner/owner_view.dart#L28)

- Editor permite rolagem e protege navegação após salvamento demorado.
  [dietary_view.dart:6](../../app/lib/ui/dietary/dietary_view.dart#L6)

- Ficha descarta respostas de tags superadas por consultas mais recentes.
  [place_detail_view_model.dart:69](../../app/lib/ui/place/place_detail_view_model.dart#L69)

**Verificação e operação**

- Cenários assíncronos reproduzem respostas invertidas e tempo limite.
  [wave5_review_regressions_test.dart:1](../../app/test/ui/wave5_review_regressions_test.dart#L1)

- Fluxos completos verificam tags, preferências e titularidade nas telas.
  [wave5_widgets_test.dart:1](../../app/test/ui/wave5_widgets_test.dart#L1)

- Transações administrativas são exercitadas exclusivamente no emulador.
  [ownership.test.js:1](../../firebase/tests/ownership.test.js#L1)

- Procedimento explica descoberta de pedidos e verificação humana fora do aplicativo.
  [ownership.md:1](../../docs/ownership.md#L1)
