# Moderação de titularidade

Referência: `modera_o_de_titularidade_na_rea` do ZIP Stitch. Entrada em Configurações → Administração → Solicitações de titularidade, apenas para administrador autorizado.

- Cards arredondados com local, foto do cadastro quando disponível, solicitante, data e status real. Sem imagem, usa ícone; sem avatar, inicial do nome.
- Pendentes e Decididas carregam dados reais, com paginação de 20 registros. O contador descreve os resultados carregados e indica `+` se há mais páginas.
- Decididas inclui aprovações, reprovações e revogações, com motivo e acesso ao detalhe. Novo índice `ownershipRequests(status, decidedAt DESC)` preparado no arquivo de índices para a entrega final.
- Aprovar e Recusar abrem a revisão da solicitação. O detalhe mantém motivo obrigatório, verificação externa antes da aprovação e confirmação final. Mantidos os bloqueios de autoaprovação, titular existente, conflito e perda de acesso.
- Por escolha da usuária, mantém verificação externa. Não exibe anexos ou documentos fictícios do protótipo.
- O acesso alterado limpa tanto a fila quanto o histórico. Consultas antigas são descartadas.

Verificações: testes anteriores de moderação, histórico com mais de 20 registros e ordenação, troca de abas, perda de acesso e fonte ampliada em 320dp. Prévias usam dados de teste.
