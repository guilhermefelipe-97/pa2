# Revisão das ondas implementadas — 01/11/2026

Revisão do checkout atual após as alterações de telas, perfil, titularidade, moderação, Quero ir e ícone. Comparação com o sequenciador do BMAD, especificações concluídas, integração dos repositórios em `app/lib/main.dart`, código e testes. As decisões posteriores da usuária sobre layout, nota geral calculada, edição do perfil e modais prevalecem sobre descrições históricas dos primeiros specs.

## Resultado automatizado

- Flutter: **1.179 testes aprovados**, nenhum com falha.
- **1 teste manual de mapa real ignorado**, por exigir ativação explícita de `LIVE_MAP_PREVIEW`. Os demais testes de mapa, marcadores, alternância Lista/Mapa e descoberta permanecem na suíte normal.
- Firebase: **348 testes aprovados** no emulador Firestore, sem alterações em dados de produção.
- Análise estática: **No issues found**.
- Logs desta revisão: `work/ondas-auditoria-flutter.log`, `work/ondas-auditoria-rules.log`, `work/ondas-auditoria-analysis.log`, na pasta principal do workspace.

Testes aprovados demonstram os cenários cobertos no código local. A publicação das Rules/índices recentes e a atualização do aplicativo instalado continuam sendo etapas distintas.

## Conferência por onda

| Onda | Escopo conferido | Resultado |
|---|---|---|
| 1 — F01, F02, F05, F11 | Login/cadastro, autoria autenticada, avaliação em três eixos, companhia/período, feed de pessoas seguidas, salvar/remover no Quero ir e desfazer | Testes aprovados. Os três eixos continuam separados no dado; a nota geral exibida é calculada. |
| 2 — F06, F12, F14, F10 | Fonte da avaliação e perfis, seguir/deixar de seguir, listas nomeadas e categorias com ícones, avaliação com pelo menos um eixo, descoberta por GPS e Lista/Mapa | Testes aprovados. Modal usa Título e Categoria sugerida, sem emojis visíveis. Mapa real com tiles externos ainda tem sua verificação manual separada. |
| 3 — F15, F20, F27, F03 | Voltei aqui/recorrência, relatos de funcionamento, faixas de preço, intervalo de 30 dias entre avaliações | Testes aprovados, inclusive travas nas Rules e recuperação de falhas de envio. Visitas mantêm intervalo de 12h e não comprovam presença por GPS; esse reforço consta no backlog. |
| 4 — F09, F13, F04 | Decidir por mim, copiar listas com crédito, visibilidade a seguidores, contagem de cópias e auditoria das contribuições | As duas limitações identificadas foram corrigidas localmente em 02/11/2026, conforme atualização abaixo. |
| 5 — F22, F18, F17 | Solicitação de titularidade, aprovação/reprovação com verificação externa, bloqueios do titular no próprio local, tags comunitárias e perfil alimentar | Testes aprovados. Preferências continuam privadas; as tags exigem três autores distintos, considerando o último voto de cada pessoa e excluindo o titular atual. Seleções múltiplas exigem todas as tags confirmadas. |
| 6 — F24, F29, F16, F25 | Resposta única do titular, fila atual e histórica, modo silencioso e estrutura do Destaque | Testes aprovados. Respostas, fila e modo silencioso estão implementados; Destaque permanece intencionalmente desativado em produção. |

## Ajustes de tela preservados

- Perfil com capa, foto, @, bio, bairro/cidade e Instagram opcional; edição em Configurações ou no próprio perfil.
- Modal de senha com reautenticação, confirmação, mostrar/ocultar, bloqueio de envio duplicado e descarte após troca de conta.
- Galeria de fotos do estabelecimento, fila estimada, ações Avaliar/Quero ir e amigos agrupados por avatar.
- Meus estabelecimentos com Responder/Editar e seta de acompanhamento; moderação com Pendentes/Decididas.
- Quero ir compacto, contador pequeno e cinza, Nova lista preenchido, ícones nas categorias e perfil apenas na barra inferior nessa tela.
- Novo ícone gerado para Android, iOS e web. Não há anúncios reais nem avaliações fictícias incluídos no aplicativo.

## Limitações identificadas na revisão de 01/11 — histórico

### 1. Decidir por mim usa uma janela limitada de avaliações

`app/lib/ui/decision/decision_view_model.dart` usa `fetchReviewsByAuthors` e filtra os candidatos após a leitura. O repositório usa limite padrão de 100 avaliações por lote de autores. Com pessoas muito ativas, avaliações antigas sobre um local salvo podem ficar fora da comparação. O fluxo de decisão funciona; a cobertura de todo o histórico ainda não está implementada.

Este ponto já consta em `_bmad-output/implementation-artifacts/deferred-work.md`. A correção exige consulta específica para os candidatos ou paginação do histórico usado pelo ranking.

### 2. Contador de cópias não comprova a criação da cópia no servidor

As Rules de `users/{uid}/lists/{listId}/copies/{copierUid}` exigem que o usuário siga a autora e que a lista esteja visível, limitando a uma entrada por pessoa. Porém, não exigem um documento de lista copiada correspondente. Um cliente modificado consegue registrar essa entrada sem realizar a cópia. O app normal copia e credita corretamente; o contador não deve ser tratado como métrica antifraude.

Este ponto também consta no backlog. Vincular o registro à cópia exige uma mudança coordenada no formato e nas Rules; não foi feita uma alteração silenciosa desse contrato durante esta revisão.

### 3. Patrocinado não está comercialmente ativo

`FirestoreSponsorshipRepository.current` retorna vazio fora do emulador, independentemente de configuração remota. A ativação continua condicionada às entregas F23/F26 e à decisão da usuária. Ondas 7 e 8 não foram classificadas como implementadas nesta auditoria.

## Atualização de 02/11/2026 — correções aprovadas

As duas pendências da onda 4 descritas acima foram corrigidas, com autorização da usuária: consulta paginada do histórico dos candidatos no Decidir por mim e contador vinculado à lista efetivamente salva. Os relatos anteriores descrevem o estado encontrado em 01/11, não o código atual. O painel dos filtros no feed também foi aprovado e preservado.

Validação atual: 82 testes específicos aprovados, 352 testes Firebase aprovados e análise estática sem ocorrências. A suíte completa aprovou 1.188 testes e ignorou o único teste manual de mapa, mas encontrou um teste antigo procurando “Salvar preferências”. Esse teste foi atualizado para “Aplicar filtros”, preservando a verificação de saída durante salvamento com fonte ampliada; os 15 testes do grupo de filtros/regressão passaram na nova execução. Nenhuma falha conhecida ficou pendente. A suíte inteira não foi repetida após esse ajuste exclusivo de teste.

Logs no diretório `work` do workspace: `wave4-targeted.log`, `wave4-rules.log`, `wave4-full-flutter.log`, `wave4-filters-regression.log` e `wave4-final-analysis.log`.

Detalhes e publicação: `docs/design/onda4-correcao-historico-copias.md`. Migração dos recibos antigos é simulada por padrão e só acrescenta provas encontradas, preservando datas e créditos. Nada foi publicado nem migrado em produção nesta revisão.

## Funcionalidades ainda não implementadas

Segundo `docs/lean-inception/sequenciador-mvp.md`:

| Onda | Falta implementar |
|---|---|
| 7 | F23 painel do titular com evolução das avaliações ao longo do tempo; F21 card compartilhável com link que abre o conteúdo; F26 suspensão automática do Destaque. |
| 8 | F07 afinidade de gosto entre pessoas, versão binária; F30 categorias de comida caseira; F28 informações de couvert e taxa de serviço/10%. |

O painel atual de Meus estabelecimentos não equivale ao F23 temporal. Compartilhar/copiar um link atual não equivale ao F21 com card e deep link completo. A tag Caseiro não equivale às categorias do F30. Patrocinado permanece desligado em produção enquanto faltarem F23/F26 e decisão de ativação.

Além das ondas, permanecem reforços no backlog: prova de presença e limite global de visitas, opções de desfazer/exclusão, tratamento de trava após remoção de avaliação, correção posterior de preço e escala do provedor de busca. F08 (gêmeo de gosto), F19 (locais de atividade) e N31 (anotações privadas no painel) estão fora do sequenciador atual. Lista completa em `_bmad-output/implementation-artifacts/deferred-work.md`.

## Antes da entrega para instalação

1. Publicar as Rules e os índices recentes necessários à edição do perfil/Instagram, galeria, apresentação do titular, agregações de notas e histórico de moderação.
2. Conferir e migrar os recibos antigos de cópias com prova, preservando os demais; gerar o novo APK após encerrar a validação das telas. O código continua com versão `1.4.0+7`; a revisão não gerou outro instalador.
3. Conferir em aparelho real GPS, fotos/permissões, mapa com conexão e e-mail de confirmação da troca de endereço. Esses serviços externos não foram testados com contas reais nesta revisão.

## Modal Nova lista

Prévia real do Flutter em `work/feed-preview/nova-lista-modal-validacao.png`, com dados de teste: Título, contador de 40 caracteres, categoria opcional por ícone e botões Cancelar/Criar lista. Nome vazio, nome repetido e comprimento inválido impedem a criação. A escolha da categoria é preservada nas listas e nas cópias existentes.

## Publicação e APK — 02/11/2026

Versão atualizada para 1.5.0+8. Rules e índices publicados com sucesso no projeto naarea-natal. Todos os 14 índices compostos confirmados READY. Os três recibos antigos foram conferidos contra listas realmente copiadas e migrados em transações, acrescentando somente copiedListId; datas e listas preservadas, com releitura após cada gravação. Não restou recibo legado nesta conferência.

APK release de produção gerado em `outputs/NaArea-1.5.0.apk`, no workspace. Assinatura válida e idêntica à versão 1.4.0, pacote br.naarea.naarea, versão 1.5.0 (8), Android mínimo 24, ARM32/ARM64/x86_64. A assinatura atual é de desenvolvimento, como nas versões de teste anteriores; não é uma publicação na Play Store. Patrocinados continuam desligados. Conferência de GPS, fotos, mapa e e-mail em aparelho real permanece necessária.

Logs em work: release-1.5.0-build.log, release-1.5.0-deploy.log, release-1.5.0-indexes-ready.log, release-1.5.0-signature.log, release-1.5.0-package.log, release-1.5.0-copy-plan.log e release-1.5.0-copy-migration.log. As seções anteriores registram a situação antes desta publicação.
