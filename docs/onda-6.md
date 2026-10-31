# Onda 6 — respostas, modo silencioso, fila e Destaque

Versão: **1.2.0+4**. Inclui a administração de titularidade. O Patrocinado permanece desligado em produção até F23/F26.

## Fluxos para teste

1. Em Você → Meus estabelecimentos, abrir **Avaliações e respostas** de um local cujo titular foi aprovado pela administração. A lista tem todas as avaliações do local, inclusive pessoas não seguidas, em páginas de 20. Responder com texto aparado entre 1 e 1000 unidades UTF-16. A resposta exibe titular e horário, não muda os três eixos e não pode ser editada/excluída. Repetir com titular falso/revogado, texto vazio/grande, duplicidade e auditoria ausente: as Rules negam. Após revogação, a resposta original continua identificada.
2. Em Você → **Modo silencioso**, salvar o padrão. Em Avaliar/Voltei aqui, ajustar a escolha desta contribuição; o ícone de informação explica o alcance. Dados/nome/notas/tags/preço/foto continuam disponíveis na ficha, perfil e agregações. Somente Amigos exclui a atividade inteira: nenhum card, ordem, foto, comentário, fonte ou recorrência deriva dela. Histórico não muda quando o padrão é alterado. Verificar uma atividade legada sem `silent` e uma pública anterior a mais de 100 silenciosas recentes; a pública continua no feed. Perto e decisão mantêm seus dados completos.
3. Na ficha, **Fila** aceita espera inteira de 0 a 180 minutos. GPS negado, indisponível ou distância maior que 150 m explicam o impedimento e liberam a interface para nova tentativa. Coordenadas não são transmitidas. O titular não contribui. Após enviar, tentar novamente dentro de 30 minutos: bloqueado. Ao vivo usa últimos 60 minutos, último relato por pessoa, mediana, número de pessoas e idade; o sinal expira automaticamente. Histórico usa últimos 28 dias, mesmo dia semanal e faixa de duas horas em UTC−3, último relato por pessoa e mínimo três pessoas; exibe faixa típica P25–P75 sem inventar previsão. A leitura percorre toda a janela em páginas de 100 e não altera ranking.
4. Trocar de conta com leitura/envio pendente nos fluxos novos: nada da sessão anterior deve aparecer na nova. Simular rede sem resposta e ACK perdido; a interface deve recuperar, reler o servidor antes de repetir e não criar contribuição duplicada.

## Destaque somente no emulador

Executar o app com `USE_EMULATOR=true`. Usar exclusivamente o Admin SDK conectado ao emulador para preparar:

- `placeOwners/{placeId}` com titular aprovado e local existente, pelo fluxo administrativo;
- `config/features`: `{sponsorshipEnabled: true, sponsoredSlotIds: ['teste']}`;
- `sponsoredSlots/teste`: `{placeId: 'id-do-local', startsAt: Timestamp, endsAt: Timestamp}`, com início passado e fim futuro.

Em Você → **Patrocinado**, o componente é rotulado e separado do feed Amigos. O cliente lê o catálogo confiável de IDs e faz `get` individual: as Rules verificam flag, vigência, schema e titularidade para cada slot. Slots sem titular, futuros ou vencidos são negados e não renderizam; a tela atualiza e remove os expirados. Flag ausente/false nega inclusive leitura direta pelo SDK. Cliente não grava slots nem configuração. A implementação de produção retorna vazio mesmo se a flag existir. Não há pagamentos ou ativação comercial. F23/F26 e nova autorização humana são dependências para anúncios reais.

## Verificação automatizada

Em `app`: `flutter analyze` e `flutter test`. Em `firebase`: JDK21 no PATH e `npm run test:emulator`. Os testes novos cobrem cálculos, paginação pública/legada, janela inteira de fila, atomicidade, cooldown, ACK perdido, respostas, preferência privada, envio/renderização/expiração e isolamento de sessão. A suíte administrativa existente permanece obrigatória. Logs desta execução ficam em `work/wave6-*.log`, fora do repositório.


Resultado final: análise estática sem ocorrências; 1.116 casos Flutter verdes (1.105 na execução completa e 11 no arquivo de telas corrigido); 333 testes Firebase verdes no emulador. As três revisões independentes foram concluídas e os ajustes aplicados. Regras publicadas em naarea-natal, com todos os 10 índices READY. Nenhum pedido real foi aprovado ou reprovado durante os testes. O Patrocinado permanece desligado.
