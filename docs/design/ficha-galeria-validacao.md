# Ficha do local — galeria e validação visual

Solicitação: galeria de capa com várias fotos; fila estimada visível; Avaliar e Quero ir lado a lado, sem quebra de linha; amigos em grupo de avatares; preservar as ondas anteriores e Copiar lista. A referência mais recente é codex-clipboard-f80765fa-2022-453e-a39f-0d0d32cdb013.png.

## Implementação

- Galeria paginada na capa: fotos enviadas para o estabelecimento, fotos das avaliações e imagem do catálogo quando disponível. Navegação por gesto/setas, contador e crédito.
- Adicionar fotos: seletor múltiplo, até seis por envio, prévia e remoção antes do envio; compressão JPEG existente de até 1080 px/150000 bytes, sem metadados EXIF. Falha mantém a seleção; troca de conta esconde a seleção e bloqueia o envio.
- Fotos da capa são documentos próprios em `places/{placeId}/photos/{id}`, com `authorId`, `authorName`, `createdAt` e `jpeg`. As avaliações e a coleção `reviewPhotos` permanecem compatíveis com os clientes anteriores.
- Leitura de até 20 imagens por página, com cursor. Cada envio usa batch; não grava parcialmente um lote inválido.
- Regras: leitura autenticada; criação com usuário/nome reais, timestamp do servidor e limite de tamanho; atualização negada; remoção somente pela autoria. A interface permite remover imagens da seleção antes de enviar; não oferece ainda exclusão de imagens já publicadas.
- A fila mostra a faixa interquartil dos relatos recentes e horário da atualização. Sem sinal recente, usa o histórico apenas quando há amostra suficiente. Sem dados, informa a ausência da estimativa. O cartão abre os detalhes e o formulário existentes.
- Avaliar e Quero ir dividem a largura disponível, com rótulos de uma linha. O bloqueio de reavaliação continua: botão desabilitado e explicação da liberação. Voltei aqui permanece como ação secundária ao fim das experiências, inclusive em locais sem avaliações.
- Amigos: avatares agrupados, sem nomes visíveis repetidos, com tooltip/rótulo acessível e acesso ao perfil. Enquanto não houver foto de perfil cadastrada, o avatar existente mostra a inicial; não são usadas fotos de pessoas fictícias em produção.
- Médias por eixo continuam disponíveis em Informações úteis. Notas, visitas, preços, tags, fila e respostas do titular continuam com suas regras próprias.
- Copiar lista: perfil de outra pessoa → Listas → lista compartilhada → Copiar lista. Mantidos os requisitos de seguir a pessoa e de ela ter compartilhado a lista. O cartão agora indica Abrir para copiar lista.

## Validação e entrega

As capturas usam dados de teste e imagens públicas referenciadas pelo próprio HTML Stitch, sem gravar conteúdo fictício no Firebase de produção. O estado visual continua aguardando aprovação do usuário, tela por tela. Não foi gerado novo APK nesta etapa.

As novas regras foram verificadas no emulador junto com as regras anteriores (338 testes aprovados). A publicação dessas regras deve acompanhar a liberação da galeria após a validação; as regras não foram publicadas nesta etapa.

Logs do app em `app/gallery-final-regression.log` e `app/gallery-analyze-clean.log`; regras em `gallery-rules-tests2.log`. Captura para revisão em `work/feed-preview/detalhes-local-completo.png`, na pasta principal do workspace.

Resultado final desta etapa: 1151 testes do app aprovados (um teste manual de mapa não executado nesta bateria), 338 testes das regras aprovados, análise estática sem problemas. A captura da ficha foi inspecionada novamente, com foto de referência, fila 15–20 minutos calculada de relatos de teste, botões Avaliar/Quero ir na mesma linha e grupo de avatares sem nomes visíveis.
