# Perfil público aprovado; edição em validação visual

Referências: codex-clipboard-100a8a99-a30c-4b32-afd3-1c2b50f65d52.png (identidade) e codex-clipboard-ff76762c-86c9-4cd4-8d7d-c834419abad6.png (avaliações).

O perfil público e o formato das avaliações foram aprovados pela usuária. A próxima validação apresenta Editar perfil, acessível pelo botão do próprio perfil ou Configurações → perfil. Título e botões de foto/capa reduzem o texto quando necessário para manter uma linha em telas pequenas.

Revisão da edição com a referência `codex-clipboard-d38e8ad2-aae2-43e4-9629-dd856e300964.png`: cabeçalho Cancelar/Salvar, capa com avatar sobreposto e câmera, Informações básicas, Presença e links e Acesso e segurança. Privacidade foi expressamente dispensada pela usuária; o modo silencioso existente continua em Configurações. Instagram é opcional, tem até 30 caracteres e é persistido/validado no perfil público. Não se inventam selos de curador ou de e-mail verificado.

Alterar senha abre modal com senha atual, nova senha e confirmação, visibilidade individual e bloqueio de envio duplicado. A alteração usa Firebase Auth com reautenticação; senhas não são salvas no perfil público. Falha permite corrigir/tentar novamente, mudança de conta oculta os campos e descarta a resposta anterior. A troca de senha mantém o rascunho de edição do perfil.

Captura adicional: `work/feed-preview/alterar-senha-modal-validacao.png`. Rules e índices novos permanecem locais até a etapa de entrega final.

- Perfil público apresenta foto, capa dentro do card de identificação, nome, @usuário, bio e cidade opcional. O próprio perfil tem Editar perfil e engrenagem. Outros perfis mantêm Seguir/Seguindo.
- Configurações → perfil abre Editar perfil. O formulário permite nome, @, bio, cidade, foto e capa; Conta e segurança abre o gerenciamento de e-mail/senha. Dados ficam em seções públicas e privadas distintas.
- @ tem 3–24 caracteres (letras minúsculas, números, ponto e sublinhado). Reserva em `usernames/{handle}` e perfil são gravados em transação; colisão não altera parcialmente o perfil. A troca libera o @ anterior no mesmo lote. Contas antigas sem @ escolhem o identificador na edição; nenhum identificador fictício é exibido.
- Bio até 240 caracteres; cidade opcional até 80; nome até 60. Foto e capa são JPEG recodificados, até 1080 px/150000 bytes, sem EXIF, em `users/{uid}/media/{avatar|cover}`. A capa deixa de ser derivada da última avaliação.
- Imagens de perfil alimentam o componente de avatar compartilhado, inclusive nas outras telas. Há cache limitado, descarte de respostas antigas e invalidação ao editar ou trocar a sessão.
- As avaliações seguem a hierarquia da referência: local e nota geral, contexto e preço informado, notas por eixo em faixa, comentário, imagem disponível e resposta do titular. Não se inventam selos de visita verificada, plano Gold, contagem de utilidade nem fotos adicionais de uma avaliação.
- A ordenação Mais recentes/Mais antigas funciona nos registros carregados. As atividades mantêm os limites existentes de 50 avaliações e 50 visitas; totais usam consultas de contagem separadas. Se as contagens estiverem indisponíveis, os valores carregados são identificados como recentes. Seguidores não recebe número fictício; Seguindo aparece quando a contagem real está disponível.
- Retornar à aba Perfil ou ao perfil após outra tela recarrega os dados. Puxar para atualizar também recarrega atividades, identidade e imagens.
- Mudar o nome não reescreve avaliações, respostas ou créditos antigos: seus nomes registrados permanecem ligados ao mesmo uid. Copiar uma nova lista consulta o nome atual antes de gravar o crédito, mantendo cópias anteriores válidas.
- E-mail/senha usam Firebase Auth com reautenticação pela senha atual. Novo e-mail exige confirmação do link; a interface não afirma que ele já foi trocado. Senhas não são persistidas no Firestore. O endereço exibido é recarregado ao retornar ao app.
- Regras restringem edição ao dono, reserva de @ à mesma conta e tamanho/formato dos campos. E-mail, senha e permissões administrativas são rejeitados no documento público.

Verificação: 1160 testes Flutter aprovados; 343 testes das regras no emulador aprovados. Os testes cobrem edição, colisão de @, gravação atômica, retorno das avaliações, confirmação de e-mail, reautenticação, listas e regressões das ondas anteriores. Logs: `app/profile-full-regression.log`, `profile-rules-tests.log` e `app/profile-final-analyze.log`.

Capturas em `work/feed-preview/perfil-novo-validacao.png`, `editar-perfil-validacao.png` e `conta-seguranca-validacao.png` (pasta principal do workspace). Usam dados de teste e imagens do export, sem gravar conteúdo fictício em produção. O fluxo continua validando uma tela por vez. Não foi gerado novo APK nem publicada nova regra nesta etapa.
