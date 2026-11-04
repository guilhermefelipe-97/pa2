# Referência Stitch — revisão integral do export

Fonte: stitch_app_de_avalia_es_profissional.zip, reaberto em 01/11/2026.
Conteúdo conferido: 13 code.html e 14 screen.png (13 telas e o ícone).
Os HTMLs foram lidos como dados; scripts do export não foram executados.

## Fonte visual

O ZIP contém diferenças entre HTML e PNG. Em Perto, o HTML inclui “Destaque da semana”, “Patrocinado”, “Lugares por perto” e “Por distância”, como a última imagem fornecida pelo usuário; o PNG tem uma composição anterior. Seguir o HTML e a última referência do usuário nesses pontos. Os contornos azuis em partes do PNG de Configurações não constam do tema do HTML.

Tokens conferidos: fundo #FFF8F5; texto #1F1B17; texto secundário #4D4540; principal #000000; cobre #904D00; superfícies #FCF2EB / #F6ECE6; cartões brancos. Fontes Epilogue e Plus Jakarta Sans. Raios lg=8px, xl=12px, full=9999px; moderação também usa 2xl=16px. Usar o raio indicado em cada componente, sem impor um raio genérico a todas as telas.

## Inventário completo

| Export | Composição revisada | Correspondência Flutter / trabalho visual |
| --- | --- | --- |
| amigos_feed_na_rea | Cabeçalho com localização, filtros, autoria, capa, local/nota, ações e fim da lista | feed/feed_view.dart e feed/widgets/feed_card.dart; alterações do usuário têm prioridade |
| perto_descoberta_na_rea | Busca + Lista/Mapa na mesma faixa, filtros, patrocinado, lista por distância, ampliar raio | nearby/nearby_view.dart, nearby_map.dart e sponsored/sponsored_view.dart; em correção visual |
| quero_ir_listas_salvos | Total salvo, nova lista, chips de listas, cartões com miniatura, informações e ação | saved/saved_view.dart; reprodução detalhada ainda precisa de validação |
| pessoas_rede_conex_es | Descobrir Pessoas, busca, filtros de rede, sugestões, cartões e seguir | people/people_view.dart; reprodução detalhada ainda precisa de validação |
| perfil_do_usu_rio_na_rea | Capa, avatar sobreposto, identidade, bio, contadores, abas, experiências, resposta do titular, visitas e listas | profile/profile_view.dart; reprodução detalhada ainda precisa de validação |
| configura_es_na_rea | Conta/segurança, privacidade, notificações, preferências, ajuda e sobre | settings/settings_view.dart; reunir os fluxos reais e validar ausência de funções ainda não disponíveis |
| avaliar_um_local_na_rea | Local selecionado, três eixos opcionais, comentário, fotos, companhia, tags, silencioso e publicar | review/review_view.dart; preservar validações e salvamento reais |
| ficha_do_estabelecimento_na_rea | Capa, identidade/endereço, abertura/fila, ações, amigos, avaliações com fotos/resposta e informações | place/place_detail_view.dart; preservar avaliações, titular e fila |
| meus_estabelecimentos_na_rea | Pendências, locais vinculados, status e responder/reivindicar | owner/owner_view.dart e owner_reviews_view.dart; dados e autorizações reais |
| modera_o_de_titularidade_na_rea | Pendentes/decididas, solicitante, comprovação, aprovar/recusar e histórico | admin/admin_ownership_view.dart; preservar acesso de administrador e auditoria |
| estado_carregamento_skeleton | Cabeçalho, aviso de carregamento, busca/chips e cartões skeleton | Estado transversal; os spinners atuais ainda não reproduzem toda a composição |
| estado_offline_sem_conex_o | Modo offline, ícone, texto, salvos, tentar novamente e acessar Quero ir | Estado transversal; exibir disponibilidade offline somente quando os dados estiverem realmente acessíveis |
| estado_vazio_sem_resultados | Consulta, ilustração, título/texto, sugestões, limpar filtros e ver mapa | Estado transversal; sugestões e contagens precisam de dados reais |
| app_icon_for_mobile_app_named_na_rea_displaying_an_ultra_clean_high_contrast | Bússola verde escura, ponteiro cobre/creme | Asset de ícone; não define sozinho a paleta das telas |

## Alterações explícitas do usuário que prevalecem sobre o export

- Cinco abas: Amigos, Perto, Quero ir, Pessoas e Perfil.
- Configurações acessível pelo perfil, no canto superior direito.
- Titularidade e Administração dentro de Configurações.
- Remover “Círculo gastronômico”.
- Incluir no feed uma avaliação escrita real com autoria, quando houver.
- Manter os cards de estabelecimento arredondados e o botão flutuante Avaliar.
- Rodapé somente em Configurações: NaÁrea na primeira linha; © 2026. Todos os direitos reservados. abaixo.
- Dados vêm de ações e registros reais; exemplos do export servem apenas para testes visuais.
- A validação por tela foi substituída pela autorização posterior para concluir todas as telas e entregar o APK final, perguntando somente em caso de dúvida de localização no fluxo.

## Pontos que não podem ser confundidos com implementação concluída

O ZIP é uma especificação visual e apresenta capacidades que precisam de suporte próprio: 2FA, dispositivos conectados, controles de notificações, histórico automático, contatos, métricas de utilidade/contagens, preços, selos de verificação e horários comerciais. Não apresentar controles decorativos, números inventados nem promessas de dados offline. A política anterior mantém patrocinados desligados em produção até F23/F26; campanhas de demonstração ficam no teste visual.

A revisão de todas as fontes está concluída. O inventário acima registra a situação inicial da auditoria; a atualização abaixo registra a entrega integrada.

## Atualização — avaliação

Lista e Mapa de Perto aprovados pelo usuário. Avaliação redesenhada com local selecionado, três eixos opcionais, comentário, foto, companhia, tags alimentares reais, faixa de gasto, silencioso explicado e botão fixo com média calculada. Permanecem uma foto e 280 unidades UTF-16 por avaliação, conforme contrato atual; o export visual propõe várias fotos e 600 caracteres.

## Entrega integrada — 1.4.0+7

Revisão posterior (01/11/2026): a declaração de fidelidade abaixo foi ampla demais. A entrega é parcial: ficha, perfil, Meus estabelecimentos e moderação divergem da composição Stitch, falta atualização do perfil após novas avaliações e não há edição de perfil/conta. Titularidade não possui o acompanhamento detalhado da referência e moderação não tem lista de decididas. Consultar outputs/Analise-NaArea-1.4.0.md na pasta principal do workspace para evidências e correções necessárias. Os testes funcionais aprovados não demonstram completude visual ou existência das funções de edição.

Quero ir, Pessoas, Perfil, Configurações, ficha do local, titularidade e moderação receberam a composição, tipografia, superfícies e componentes do export, respeitando as alterações autorizadas e as capacidades reais. Estados de carregamento, sem resultados e falha de conexão usam ações reais de recuperação. Não são exibidos números, campanhas, biografias ou controles de segurança fictícios.

As cinco abas permanecem. Perfil contém a engrenagem; Configurações reúne preferências alimentares, modo silencioso, permissões do aparelho, titularidade e administração autorizada. O rodapé institucional aparece somente nessa tela. Perfis abertos por outros fluxos têm ação de voltar; listas públicas mantêm suas regras de compartilhamento; fotos dentro das avaliações preservam sua autoria.

Perto inclui mapa geográfico com marcadores nas coordenadas reais, atribuição OpenStreetMap e alternância Lista/Mapa. O provedor de tiles é configurável por MAP_TILE_URL. A integração de publicidade permanece desligada em produção até F23/F26, conforme autorização anterior.

Verificações incluem capturas Flutter com fontes locais, telas estreitas com fonte ampliada, criação de listas, navegação entre perfis e regressões das ondas anteriores. Os registros finais da execução e do build ficam em app/stitch-release-*.log.
