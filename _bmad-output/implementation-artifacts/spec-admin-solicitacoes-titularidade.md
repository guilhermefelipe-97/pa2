---
title: 'Administração — Aprovar e reprovar solicitações de titularidade'
type: 'feature'
created: '2026-10-30'
status: 'done'
baseline_commit: '99a9d86d8c8d7a034a43bdae664eb2a86e98d0f8'
review_loop_iteration: 0
context:
  - '{project-root}/docs/ownership.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** A solicitação existe no APK, mas sua análise exige comandos administrativos.
**Approach:** Entregar Você → Administração → Solicitações de titularidade, com fila paginada de pendentes, detalhe, aprovação e reprovação.

## Boundaries & Constraints

**Always:**
- Só administradores veem a entrada e acessam rotas/dados; credenciais administrativas nunca entram no APK. `admins/{uid}` é provisionado fora do cliente, somente para a conta indicada pelo usuário no chat. Nenhum e-mail fica fixado no código.
- Membership usa `enabled == true`; próprio usuário lê seu documento, ninguém enumera ou escreve pelo app. Revogação/troca de conta limpam tela e respostas atrasadas.
- Fila mostra solicitante, local e data; detalhe abre os perfis/ficha. Aprovar exige confirmação da verificação externa e motivo; reprovar exige motivo. Confirmação final, envio único e estados de vazio/erro/retry.
- Decisão somente de pedido existente pendente; administrador não decide o próprio pedido. Motivo aparado de 1–500 caracteres, visível ao solicitante, sem notas privadas. Operador é UID autenticado e data é do servidor.
- Preservar schema do script: `operator`, `reason`, `decidedAt` e mapa `approval`/`rejection` iguais ao trio. `createdAt` imutável. Decisões finais não são editáveis pelo cliente.
- Aprovação cria `placeOwners/{placeId}` e decide pedido na mesma transação. Rules exigem ambas as escritas, verificam autor/tempo/local e negam substituir qualquer titular existente. Rejeição só decide pedido. Concorrência recarrega e explica conflito; confirmação perdida é reconciliada antes de repetir.
- Regras autorizam exclusivamente o cliente administrador; solicitante comum continua sem alterar status/titular. Ele vê status e motivo em Meus estabelecimentos.

**Ask First:** Conceder acesso a outra conta ou decidir pedidos reais.
**Never:** Revogação/transferência nesta tela, autoaprovação, coleta de documentos, service account no aplicativo, pagamento/Functions como dependência.

## I/O & Edge-Case Matrix

| Cenário | Estado | Resultado | Falha |
|---|---|---|---|
| Acesso | Conta comum/rota direta | Sem fila ou decisão | Acesso negado |
| Aprovar | Pendente e local sem titular | Pedido e titular juntos | Forjas negadas |
| Reprovar | Motivo preenchido | Só pedido decidido | Motivo obrigatório |
| Concorrência | Duas decisões/titular existente | Uma decisão válida | Recarregar conflito |
| Sessão | Conta/papel muda durante leitura | Limpar dados | Descartar resposta antiga |

</frozen-after-approval>

## Code Map

- `firebase/firestore.rules:27,52` — bloqueios atuais de titular/pedido; acrescentar autorização bilateral e leitura administrativa collectionGroup.
- `firebase/seed/manage-ownership.js:5` — schema e transação existentes; preservar compatibilidade.
- `app/lib/ui/profile/profile_view.dart:96`, `routing/router.dart:94`, `main.dart:115` — entrada, rotas e providers.
- `app/lib/data/repositories/owner_repository.dart`, `ui/owner/owner_view.dart` — acompanhamento do solicitante; motivo opcional compatível.

## Tasks & Acceptance

**Execution:**
- [x] `firebase/firestore.rules`, `firestore.indexes.json`, `tests/firestore.rules.test.js` — autorização, schemas, acoplamento, concorrência; índice collectionGroup status/data.
- [x] `app/lib/data/repositories/admin_*`, `data/firebase/firestore_admin_*`, `domain/models/admin_ownership_request.dart` — acesso observado e fila/decisão transacional, com revalidação do servidor.
- [x] `app/lib/ui/admin/`, `routing/routes.dart`, `routing/router.dart`, `main.dart`, `ui/profile/profile_view.dart` — MVVM, telas protegidas e isolamento de sessão.
- [x] `app/lib/data/repositories/owner_repository.dart`, `data/firebase/firestore_owner_repository.dart`, `ui/owner/owner_view.dart` — exibir motivo ao solicitante.
- [x] `app/test/`, `firebase/tests/` — matriz, menu/rotas, fluxo completo, dupla submissão, perda de resposta/permissão e regressões existentes.
- [x] `docs/ownership.md` — documentar exceção administrativa do cliente e provisionamento seguro; operações de entrega seguem após revisão.

**Acceptance Criteria:**
- Given administrador autorizado, when verifica e aprova pedido de outra pessoa, then titularidade é criada e solicitante vê resultado/motivo.
- Given usuário comum ou administrador revogado, when acessa rota ou SDK diretamente, then fila e decisões ficam bloqueadas.

## Spec Change Log

## Design Notes

CollectionGroup deriva UID/local do caminho, sem migração. Admin não se concede poderes; leitura de papel não usa cache como prova. Dados históricos e script existentes permanecem válidos. A nova autorização substitui a proibição geral documentada de alterações administrativas pelo cliente.

Implementação local nesta etapa; o agente principal executará o provisionamento da conta indicada no chat, deploy e build depois da revisão. Nenhuma operação de produção deve ser executada pelo implementador.

## Verification

- `cd app; flutter analyze; flutter test` — análise limpa e regressões passam.
- `cd firebase; npm run test:emulator` — Rules/administrativo passam.
- Conferir índice pronto e APK 1.1.1, build 3, com assinatura válida. Não decidir pedidos reais para testar.


## Validação local

- Flutter: 1072 testes passaram; análise sem problemas.
- Firebase emulador: 323 testes passaram, incluindo SDK cliente e concorrência.
- 11 testes administrativos reexecutados após último ajuste visual.

## Entrega operacional após revisão

- [x] Habilitar apenas a conta indicada pelo usuário (confirmado no servidor).
- [x] Publicar Rules/índice e confirmar índice pronto (READY no servidor).
APK final combinado com a onda 6 aprovada será entregue após a próxima implementação.


## Revisão independente e validação final

- Três revisões concluídas; 12 grupos de patches e lacunas tratados.
- Flutter completo: 1084 testes passaram; Firebase: 324 passaram; dirigidos finais: 25 passaram.
- Análise final: sem problemas (21,9s). Diff sem erros.
- Produção: conta indicada habilitada, Rules publicadas e índice confirmado READY.


## Suggested Review Order

**Permissões e integridade**

- Papel administrativo externo controla leitura da fila e decisões atômicas.
  [firestore.rules:16](../../firebase/firestore.rules#L16)

- Aprovação exige pedido e titularidade juntos; decisões finais são imutáveis.
  [firestore.rules:30](../../firebase/firestore.rules#L30)

- Transação revalida servidor e reconcilia resposta perdida antes de repetir.
  [firestore_admin_ownership_repository.dart:104](../../app/lib/data/firebase/firestore_admin_ownership_repository.dart#L104)

**Sessão e recuperação**

- Papel confirmado pelo servidor, revogação e retry isolados por conta.
  [admin_access.dart:8](../../app/lib/ui/admin/admin_access.dart#L8)

- Leitura confiável precede decisões; falhas não reabilitam pedidos antigos.
  [admin_ownership_view_model.dart:40](../../app/lib/ui/admin/admin_ownership_view_model.dart#L40)

**Interface**

- Confirmação identifica o alvo e mostra o motivo público antes de gravar.
  [admin_ownership_view.dart:24](../../app/lib/ui/admin/admin_ownership_view.dart#L24)

- Solicitante acompanha resultado e motivo, distinguindo revogação de aprovação anterior.
  [owner_view.dart:1](../../app/lib/ui/owner/owner_view.dart#L1)

**Verificação e operação**

- Repositório cobre paginação, metadados, timeout e resposta perdida.
  [admin_ownership_repository_test.dart:1](../../app/test/data/admin_ownership_repository_test.dart#L1)

- Telas e regras cobrem confirmações, acesso negado, concorrência e histórico.
  [admin_ownership_test.dart:1](../../app/test/ui/admin_ownership_test.dart#L1)

- Procedimento explica concessão externa do papel e verificação da titularidade.
  [ownership.md:1](../../docs/ownership.md#L1)
