# Titularidade de estabelecimentos

O pedido privado nasce na ficha de um local existente e aparece em **Você → Meus estabelecimentos**. Um pedido pendente não concede poderes. O cliente não altera status nem escreve `placeOwners`. Não solicitar nem enviar documentos pessoais pelo app.

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

A leitura administrativa percorre os pedidos e filtra pendentes sem depender de índice de collection group; não a exponha no cliente. `uid` e `placeId` da saída são os argumentos da CLI. No ambiente de emulação, crie contas e pedidos fictícios pelo app conectado ao emulador; não use dados reais.

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
