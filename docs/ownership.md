# Titularidade de estabelecimentos

O pedido privado nasce na ficha de um local existente e aparece em **Você → Meus estabelecimentos**. Um pedido pendente não concede poderes. O solicitante comum não altera status nem escreve `placeOwners`. A exceção é a administração autenticada descrita abaixo. Não solicitar nem enviar documentos pessoais pelo app.

Um operador humano deve verificar fora do app que a pessoa representa o estabelecimento (por exemplo, contato por canal público já conhecido e confirmação presencial). Registre no motivo apenas a conclusão e o método, sem documentos pessoais. A aprovação é uma decisão humana explícita, nunca automática.

Para descobrir pedidos no emulador, configure as variáveis abaixo, entre em `firebase/`, execute `node` e cole no REPL:

```javascript
const { firestoreFromEnv } = require('./seed/seed');
const { db } = firestoreFromEnv();
const pedidos = await db.collectionGroup('ownershipRequests').get();
for (const doc of pedidos.docs) {
  if (doc.data().status !== 'pending') continue;
  const uid = doc.ref.parent.parent.id;
  const placeId = doc.id;
  const local = await db.doc(`places/${placeId}`).get();
  console.log({ uid, placeId, local: local.data()?.name });
}
```

A consulta de manutenção acima percorre todos os pedidos pelo Admin SDK. No aplicativo, a fila administrativa usa collectionGroup com filtro status e ordenação por createdAt, com índice próprio e desempate pelo caminho do documento. `uid` e `placeId` da saída são os argumentos da CLI. No ambiente de emulação, crie contas e pedidos fictícios pelo app conectado ao emulador; não use dados reais.

O app não envia contato nem documentos com o pedido. Combine a verificação com a pessoa por um canal de suporte ou presencialmente, peça que ela informe o UID da conta solicitante e o estabelecimento, e confira ambos com a consulta administrativa. Confirme a identidade da conta pelo canal autenticado de atendimento; não aprove só porque alguém conhece um UID. Faça também a confirmação independente da representação por canal público do estabelecimento ou presencialmente. Guarde apenas método e conclusão no motivo. Se não houver canal suficiente para essa confirmação, mantenha pendente ou rejeite com motivo.

Com Node e dependências de `firebase/` instaladas, no PowerShell:

```powershell
$env:FIRESTORE_EMULATOR_HOST='127.0.0.1:8080'
$env:GCLOUD_PROJECT='demo-naarea'
node seed/manage-ownership.js approve UID PLACE_ID OPERADOR 'Verificado presencialmente'
node seed/manage-ownership.js reject UID PLACE_ID OPERADOR 'Representação não confirmada'
node seed/manage-ownership.js revoke UID PLACE_ID OPERADOR 'Representação encerrada'
```

Em produção, remova `FIRESTORE_EMULATOR_HOST`, defina o projeto correto em `GCLOUD_PROJECT` e `GOOGLE_APPLICATION_CREDENTIALS` apontando para uma service account fora do repositório. Confirme o ambiente e a decisão humana antes de executar. A implementação e seus testes não executam decisões em produção.

A transação impede substituir outro titular, inclusive em aprovações concorrentes. Um titular pode ter vários locais. Revogar exige o UID do titular atual; para transferir, revogue primeiro e aprove o pedido pendente da nova pessoa. Pedido já decidido permanece como histórico: repetir no app mostra o existente.

O pedido mantém a decisão original (`operator`, `reason`, `decidedAt` e `approval` ou `rejection`). Uma revogação registra `revocation` separadamente, preservando quem aprovou, quando e por qual motivo.

Titulares não podem criar avaliações, visitas nem relatos de aberto/preço do próprio local. Conteúdo anterior fica intacto; as tags do titular atual não contam no quórum. Revogação remove essa exclusão. Tags comunitárias não são certificações nutricionais nem garantia para alergias.

## Administração no aplicativo

A entrada **Você → Administração → Solicitações de titularidade** aparece somente quando o próprio documento `admins/{uid}` retorna do servidor com `enabled == true`. Regras impedem enumerar, criar ou alterar memberships pelo cliente. Revogação ou troca de conta limpa a fila, o detalhe e respostas em andamento. Rotas diretas sem membership mostram acesso negado.

A fila paginada informa solicitante, local e data. No detalhe, abra o perfil e a ficha; confirme a verificação externa antes de aprovar e informe um motivo de 1–500 caracteres, aparado, visível ao solicitante em **Meus estabelecimentos**. Não registre notas privadas nem documentos. Aprovar e reprovar exigem confirmação final. O administrador nunca decide seu próprio pedido.

A aprovação cria o titular e decide o pedido pendente em uma transação. As Rules exigem as duas escritas e recusam substituir qualquer titular existente, inclusive do mesmo UID. Reprovação altera somente o pedido. Decisões finais e createdAt são imutáveis pelo cliente. Os campos operator (UID autenticado), reason, decidedAt (servidor) e approval/rejection preservam o schema do script. Em conflito, recarregue o pedido; se uma resposta se perder, o repositório reconcilia com o servidor antes de liberar nova tentativa. Sem confirmação do servidor, a tela exige atualização.

Provisionamento é uma operação externa ao app: confirme a conta explicitamente indicada pelo usuário e obtenha seu UID pelo Firebase Authentication. Com Admin SDK autenticado em ambiente confiável, crie exclusivamente `admins/UID_CONFIRMADO` com `{enabled: true}`; para revogar, altere enabled para false. Não grave e-mail no código, não conceda acesso a contas adicionais sem autorização e nunca coloque credenciais administrativas no APK. O script acima continua disponível para manutenção, revogação e transferência fora desta tela.

A publicação exige deploy das Rules e do índice `ownershipRequests` collectionGroup (`status` ASC, `createdAt` ASC), aguardar índice pronto, e gerar/verificar APK 1.1.1 build 3 assinado. Provisionamento, deploy e APK são etapas operacionais posteriores à validação local; não testar decidindo pedidos reais.

A verificação de acesso diferencia carregamento, negativa e erro. Em erro, use **Revalidar acesso** para reiniciar a observação do papel; atualizar a fila não concede permissão. Falha na atualização do detalhe mantém a decisão bloqueada até uma leitura confiável. Se a decisão já terminou, mas o detalhe não pôde ser lido, a tela informa ambas as condições.

Pedidos indisponíveis aparecem identificados na fila sem ocultar os demais e não abrem ações de decisão. Titular existente bloqueia a aprovação, mantendo a reprovação disponível. A confirmação final identifica solicitante e local com nomes e identificadores. O histórico mostra o identificador do operador e a data da decisão; em revogações, **Meus estabelecimentos** distingue o motivo original da aprovação do motivo da revogação.
