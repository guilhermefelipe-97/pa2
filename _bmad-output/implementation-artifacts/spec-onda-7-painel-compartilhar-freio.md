---
title: 'Onda 7 — Painel temporal, card compartilhável e freio do Destaque'
type: 'feature'
created: '2026-11-04'
status: 'review'
baseline_commit: 'eba5d0e'
review_loop_iteration: 0
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

Entregar F26, F21 e F23 (onda 7 do sequenciador) a partir do branch `feat/admin-onda-6`, preservando as ondas 1–6.
Decisões da usuária em 04/11/2026: piso de 3,5 em 90 dias com mínimo de 5 avaliações; card em imagem + link web;
funil do Destaque (impressões → visitas → salvamentos) fica fora desta onda.

## Boundaries & Constraints

**Always:**
- **F26 — Suspensão automática do Destaque:** um slot só aparece se o local tiver, nas avaliações dos últimos 90 dias,
  pelo menos 5 avaliações e média de todas as notas de eixo (comida, ambiente, atendimento; eixo vazio não conta)
  ≥ 3,5. Abaixo do piso ou com amostra insuficiente, o slot fica suspenso sem ação humana e volta sozinho quando a
  regra passar. A checagem é um cálculo puro com relógio injetado; a leitura das avaliações é paginada e tem cache curto
  para não ler a cada atualização da seção Perto. O titular vê em Meus estabelecimentos → Divulgação a regra, a média
  dos 90 dias, a amostra e se o Destaque estaria ativo ou suspenso. Atividade silenciosa (F16) conta, como nas demais
  agregações.
- **F21 — Card compartilhável com deep link:** na ficha do local, botão Compartilhar gera uma imagem do card (nome,
  categoria/bairro, médias dos eixos das avaliações exibidas quando houver, quantas pessoas seguidas avaliaram, quem
  está compartilhando) e abre a folha de compartilhamento do sistema com texto + link
  `https://naarea-natal.web.app/l/<placeId>`. O link leva só o id do local, nenhum dado pessoal. A página estática do
  Firebase Hosting abre o app (`naarea://app/l/<placeId>`) quando instalado e, sem o app, explica o que é o NaÁrea.
  O app trata `/l/<placeId>` abrindo a ficha; sem sessão, passa pelo login e volta para a ficha.
- **F23 — Painel com série temporal:** em Meus estabelecimentos, o titular atual abre Painel do local: médias mensais
  dos 3 eixos nos últimos 12 meses (UTC−3), separadas, nunca uma nota única; quantidade de avaliações e de "Voltei
  aqui" por mês; recorte por período do dia (F02). Mês sem nota no eixo não vira zero. Mês com menos de 3 avaliações
  é marcado como amostra pequena. Leitura paginada da janela inteira, cálculo puro testável. Só o titular atual vê.
- Sem mudança nas Rules. Índice novo de `visits (placeId, createdAt)` se necessário. Português do Brasil.

**Ask First:** Deploy de Hosting, índices ou Rules; ativar anúncios; mudar piso/janela/amostra; publicar APK.

**Never:** Funil/impressões do Destaque nesta onda; anúncios no feed Amigos; dados pessoais no link; nota única agregada
no painel; Cloud Functions.

## I/O & Edge-Case Matrix

| Caso | Resultado exigido |
|---|---|
| Média 90d ≥ 3,5 e ≥ 5 avaliações | Slot exibido |
| Média 90d < 3,5 | Slot suspenso; titular vê "Suspenso" com média e piso |
| Menos de 5 avaliações em 90d | Slot suspenso por amostra insuficiente |
| Falha ao ler avaliações | Slot não exibido (falha fecha), descoberta segue utilizável |
| Link aberto sem sessão | Login e depois a ficha do local |
| Link com id inválido | Ficha mostra "Local não encontrado" |
| Mês sem avaliações / eixo sem nota | Ponto ausente, nunca zero |
| Recorte "Noite" | Só avaliações feitas 18h–24h (UTC−3) |
| Usuário que não é titular | Sem acesso ao painel |

</frozen-after-approval>

## Code Map

- `app/lib/domain/sponsorship_floor.dart` (novo): regra pura do piso.
- `app/lib/domain/owner_timeline.dart` (novo): série mensal por eixo, recorte por período.
- `app/lib/data/repositories/place_history_repository.dart` + `data/firebase/firestore_place_history_repository.dart` (novos): avaliações/visitas de um local desde uma data, paginadas.
- `app/lib/data/firebase/firestore_sponsorship_repository.dart`: aplicar o piso antes de devolver o slot.
- `app/lib/ui/owner/owner_view.dart`: Divulgação com status do piso; entrada Painel.
- `app/lib/ui/owner/owner_timeline_view.dart` (novo): gráfico + tabela.
- `app/lib/ui/share/` (novo): card e compartilhamento; `ui/place/place_detail_view.dart`: botão.
- `app/lib/routing/`: `/l/:placeId`, painel e retorno após login.
- `app/android/app/src/main/AndroidManifest.xml`: esquema `naarea` e host https.
- `hosting/` + `firebase.json`: página estática do link.

## Spec Change Log

## Verification

app: `flutter analyze`; `flutter test`. Rules inalteradas (testes de emulador não precisam rodar de novo). Deploy de Hosting e índice só com autorização.

## Resultado da implementação local — 04/11/2026

- `flutter analyze --no-pub`: 6 avisos `empty_catches`, todos em código anterior a esta onda (nenhum erro).
- `flutter test --no-pub`: **1.217 testes passaram**, 1 ignorado (mapa real manual). Linha de base antes da onda: 1.189.
- Novos testes: `test/domain/sponsorship_floor_test.dart`, `test/domain/owner_timeline_test.dart`,
  `test/data/wave7_repositories_test.dart`, `test/ui/wave7_widgets_test.dart` (28 casos).
- Rules inalteradas; testes de emulador Firebase não rodados (Java 8 neste PC).
- Novo pacote: `share_plus`. Índice novo: `visits (placeId, createdAt)`. Página `hosting/public/`.
- Nenhum commit, deploy, APK ou ativação comercial nesta etapa. Roteiro: `docs/onda-7.md`.
