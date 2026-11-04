# Onda 4 — histórico e comprovação de cópias — 02/11/2026

Correções autorizadas pela usuária em “Corrigir as duas agora”. Nenhuma alteração nos layouts aprovados.

## Decidir por mim

O ranking consulta somente os locais candidatos e os autores seguidos, incluindo o histórico antigo. Páginas de 100 documentos com desempate por ID evitam perda quando há datas iguais. Os grupos respeitam o produto máximo de 30 alternativas de consulta, com até quatro leituras concorrentes. A consulta usa o índice existente `placeId ASC, authorId ASC, createdAt DESC` (ID descendente implícito).

O conjunto completo de avaliações só é publicado após a consulta terminar. Em falha ou após 15 segundos, o ranking mantém o comportamento anterior de ignorar esse sinal; não usa páginas parciais como se fossem o histórico completo. Encerrar a tela, trocar de conta ou atingir o prazo cancela as próximas páginas. Não altera critérios do ranking, preferência por companhia, relatos de fechado ou permissão de localização.

## Contador de cópias

O app primeiro confirma a criação da lista com seu crédito e depois registra `copies/{copierUid}` com `createdAt` e `copiedListId`. As Rules exigem uma lista existente do próprio copiador com `copiedFromUid` e `copiedFromListId` correspondentes à origem, além de seguir a autora e a origem estar visível. Uma entrada por pessoa, prova imutável, repetição idempotente. Uma falha somente no contador preserva a lista realmente copiada.

Recibos antigos sem `copiedListId` não entram na nova contagem até receberem uma prova. Uma atualização legada apenas acrescenta a prova e preserva a data. A cópia original, seus locais e créditos não são alterados.

## Publicação pendente

1. Publicar as Rules coordenadas com o app novo e os índices recentes das demais telas. Clientes antigos ainda podem salvar uma lista, mas não criam recibos no formato novo.
2. Conferir os recibos antigos com `node firebase/seed/backfill-copy-receipts.js --dry-run` no ambiente correto. O padrão já é simulação. Com `--apply`, acrescenta somente provas verificadas em transação; sem lista correspondente, mantém o recibo intacto e fora da contagem. Não exclui dados. Clientes antigos não devem continuar ativos durante a migração final.
3. Gerar o APK após a validação das telas. Nenhuma migração nem publicação de Rules em produção foi executada nesta correção.

## Teste rápido

- Copiar uma lista visível de alguém seguido: ela aparece no Quero ir com crédito e a autora vê uma cópia.
- Copiar novamente: pode criar outra lista, mas a contagem continua uma pessoa.
- Falhar apenas o contador não desfaz a lista salva.
- Decidir por mim deve considerar avaliações antigas de um salvo mesmo após mais de 100 avaliações recentes em outros locais.

Os cenários de fraude, legado, simulação da migração, idempotência, paginação com datas iguais e troca de conta têm testes automatizados.

## Resultado da validação

82 testes específicos aprovados; 352 testes Firebase no emulador aprovados; análise estática sem ocorrências. Na suíte completa, 1.188 passaram e um teste antigo de preferências falhou por procurar o nome anterior do botão. Após atualizar apenas esse teste, os 15 cenários de filtros/regressão passaram, inclusive texto ampliado e saída durante salvamento. Um teste manual de mapa foi ignorado conforme configuração. Ver relatório geral para os logs.

## Publicação concluída — 02/11/2026

Regras e índices publicados em naarea-natal; todos os índices READY. Conferência em produção encontrou três recibos legados, todos com cópias reais correspondentes. Migração acrescentou somente copiedListId nos três recibos em transações com validação de origem e controle de concorrência. Datas originais preservadas e listas intactas, confirmadas por releitura. APK 1.5.0+8 gerado com assinatura idêntica à versão anterior. Patrocinados seguem desligados.
