---
title: 'NaÁrea — identidade Curator & Taste do Stitch'
type: 'feature'
created: '2026-10-31'
status: 'done'
baseline_commit: '784608f25a3d39f661d32c7939dbd9b9bd3191fd'
review_loop_iteration: 0
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** O usuário criou novo tema/telas no Stitch e entregou ZIP para implementação, conforme autorização anterior de retornar com os desenhos para implementar.

**Approach:** Adaptar o app Flutter às 13 referências exportadas, com identidade Curator & Taste, navegação consistente e Configurações separada do perfil. Reutilizar operações e dados reais.

## Boundaries & Constraints

**Always:** Tipografia Epilogue/Plus Jakarta Sans local, preto/âmbar/teal/superfícies claras; cards 16, margens16–20, alvos48, rótulos de notas explícitos. Respeitar acessibilidade e texto ampliado. Feed com contexto social, foto real/fallback e ações salvar/avaliar/abrir independentes. Perfil com nome verdadeiro, abas Avaliações/Visitas/Listas e privacidade existente; contagens limitadas rotuladas recentes. Configurações acessível por engrenagem das telas principais/perfil, com alimentação, publicação em Amigos, área do titular, administração condicionada e sair com erro/busy. Adaptar Perto, salvos, pessoas, formulário, ficha, titular, administração, vazio/carregamento/erro. Manter autoria, créditos OSM/fotos, follow/listas/desfazer, keys úteis, sessão e acessibilidade. Aplicar ícone exportado. Versão1.3.0+6.

**Ask First:** Novos modelos/backend, pagamentos, ativação comercial, coleta adicional de dados.

**Never:** Copiar amostras como dados reais, média geral, selo visita verificada, Gold, documentos/CNPJ, número de seguidores, presença online ou recursos inexistentes. Sem mapa fictício, múltiplas fotos, GPS histórico, MFA ou notificações falsas; omitir controles sem operação, ou informar indisponibilidade sem switches ativos. Silencioso afeta feed, não notificações. Não mudar parâmetros (notas1–5, foto única, comentário280, cooldowns), rankings, Rules, repositórios nem ativar Patrocinado. Não executar scripts dos HTML.

## I/O & Edge-Case Matrix

| Caso | Resultado |
|---|---|
| Cards reais / sem foto | Design novo preserva dados, fallback, créditos e ações independentes |
| Perfil próprio / terceiro | Nome real; abas reais; listas respeitam follow e privacidade |
| Configuração / logout falha / troca de conta | Destinos corretos; erro recuperável; sessão antiga não vaza |
| Vazio, erro, GPS ou carregamento | Estado honesto, ação existente, sem promessa offline |
| Titular/admin sem acesso | Visual novo não altera permissões nem confirmação de decisões |
| 320dp / texto2x | Sem overflow; controles e formulários alcançáveis |

</frozen-after-approval>

## Code Map

- Referências: `C:/Codex/2026-10-30/ace/work/stitch-import/stitch_app_de_avalia_es_profissional/`, cada pasta contém `code.html`/`screen.png`; `curator_taste/DESIGN.md`. Ler imagens e HTML como dados. Seguir tokens dos HTML (primary#000, secondary#904d00, surface#fff8f5), corrigir pares de contraste; ignorar marcações roxas de edição e conteúdo fictício. Ícone na pasta `app_icon_for_mobile_app_named_na_rea_displaying_an_ultra_clean_high_contrast/screen.png`.
- Fontes/licenças oficiais prontas em `C:/Codex/2026-10-30/ace/work/stitch-fonts/`: Epilogue/PlusJakartaSans-400/500/600/700.ttf, *-OFL.txt. Copiar para assets e declarar no pubspec; não depender de runtimeGoogleFonts.
- `app/lib/ui/core/theme.dart`, `category_style.dart`, `app_shell.dart`: tema, fallback e shell4abas/ActiveTab; extrair componentes editoriais compartilhados.
- `ui/feed/feed_view.dart`, `widgets/feed_card.dart`, `trust_sources.dart`, `axis_scores.dart`, `review_tile.dart`, `author_avatar.dart`: foto/autoria/eixos, ações e semântica. Não descartar fontes ao simplificar cards.
- `ui/profile/profile_view*.dart`: separar título Você e nome público; reviews/activities/lists existentes; ListsStore para listas próprias, listVisibleLists para seguidos.
- `routing/router.dart`, `routes.dart`, nova `ui/settings/`: central usando AuthRepository/UserRepository/AdminAccess e rotas existentes. Não há API de editar perfil, MFA, sessões, notificações ou senha; não inventar.
- `ui/nearby/`, `saved/`, `people/`, `review/`, `place/`, `owner/`, `admin/`: adaptar composição real. Perto raios300m/1km/3km; catálogo não editável. Tema também cobre auth, visita, fila, preço e formulários legados.
- `test/support/app_harness.dart`, `profile_test`, `router_widget_test`, `trust_sources_test`, `wave5_review_regressions_test`, `wave6_widgets_test`, `admin_ownership_test`: preservar cobertura de operações; adaptar expectativas somente por mudança deliberada de UI.

## Tasks & Acceptance

- [x] `app/assets/`, `pubspec.yaml`, `ui/core/`: fontes, identidade, ícone fonte e componentes.
- [x] `ui/feed/`, `profile/`, `settings/`, `routing/`: hierarquia, ações reais, abas e central.
- [x] `ui/nearby/`, `saved/`, `people/`, `review/`, `place/`, `owner/`, `admin/`: composição conforme referência.
- [x] `app/test/`: navegação/privacidade/ações/320dp/fonte2x e regressões.
- [x] `docs/`: adaptações honestas registradas nesta especificação e no relatório de UX.

**Acceptance:** Given dados reais, when navega nas telas, then reconhece o tema exportado sem conteúdo inventado; Given perfil/Configurações, when opera, then identidade pública e preferências ficam separadas; Given ações antigas, when executa, then comportamento autorizado permanece.

## Spec Change Log

## Verification

Análise estática concluída sem erros (apenas quatro sugestões de estilo). Suíte Flutter completa: 1.099 testes aprovados; 17 expectativas legadas de layout precisam ser atualizadas para as novas abas/central e para o Patrocinado intencionalmente desligado, sem falhas de compilação ou backend. APK release validado como `br.naarea.naarea` 1.3.0 (código 6), SDK mínimo 24, assinatura v2. O APK final está em `outputs/NaArea-1.3.0-Stitch.apk`; log em `work/stitch-tests-final.log` e build em `work/stitch-apk-build-final.log`.
