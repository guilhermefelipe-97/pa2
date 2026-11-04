# Meus estabelecimentos — validação por tela

Referência: `meus_estabelecimentos_na_rea` do ZIP Stitch. Acesso: Perfil → Configurações → Meus estabelecimentos.

- Cards com capa da galeria, status real, média das notas disponíveis e ações Responder / Editar na mesma linha.
- Contagem de avaliações sem resposta usa agregações de todas as avaliações, descontando respostas inclusive de titulares anteriores. Falha na consulta não vira zero.
- Pedidos pendentes, rejeitados e revogados ficam em Acompanhar. O selo Ativo também abre o acompanhamento com o motivo da decisão. Não há etapas fictícias.
- Editar permite apresentação (1.000 caracteres), horários públicos (500) e galeria de fotos. Os textos são exibidos na ficha; não alteram nome, endereço, coordenadas ou índices do catálogo. Horários são informativos; não substituem os relatos comunitários de funcionamento.
- Fotos usam a galeria existente: até seis por envio, compressão e confirmação. Remover foto publicada exige confirmação e só está disponível para o próprio autor.
- Salvamento revalida o titular no cliente e nas Rules. Revogação impede novos salvamentos. Falha mantém os textos digitados.
- Divulgação continua indisponível para contratação em produção.

Testes: edição e leitura na ficha, falha e recuperação, revogação, fotos próprias, telas de 320dp com fonte ampliada, regras de segurança e agregações com 27 avaliações/eixos parciais.

As imagens de prévia usam dados de teste. As novas Rules e os três índices de agregação permanecem locais para a entrega final; nenhum APK novo foi gerado nesta validação.
