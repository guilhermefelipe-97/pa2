---
title: 'Feed rico — foto do local, comentário opcional, cards e detalhe do local'
type: 'feature'
created: '2026-09-28'
status: 'done'
baseline_commit: '5532a16ab5a0564cd763cc819740e76d4e5b82a2'
review_loop_iteration: 0
context:
  - '{project-root}/docs/lean-inception/visao-restricoes.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-onda-1-fundacao-avaliacao-feed.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** O feed da Onda 1 funciona, mas é cru: card só de texto, sem foto, sem voz de quem foi e sem identidade visual — não transmite a "rede social moderna e divertida" da Visão.

**Approach:** Foto de capa por local (URL fixa no seed, plano Spark — sem Storage), comentário opcional do autor na avaliação (≤280, nunca obrigatório), cards redesenhados, tela de detalhe do local e identidade visual própria (tema, tipografia, ícone e nome do app).

## Boundaries & Constraints

**Always:** Comentário opcional — avaliar só com os 3 eixos continua válido. Comentário é do autor da avaliação, imutável como ela. Foto indisponível/sem URL nunca quebra o card: cai num fallback (gradiente + ícone da categoria). Integridade: Rules validam o comentário. MVVM e testes-primeiro como na Onda 1.

**Ask First:** Qualquer coisa que exija plano Blaze (Storage, Functions). Upload de foto por usuário. Comentários de terceiros em avaliações alheias.

**Never:** Comentário obrigatório; editar/excluir comentário; foto enviada pelo usuário; fotos sem licença de reuso; chaves/credenciais no repo.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Avaliar sem comentário | 3 eixos, campo vazio ou só espaços | review salva com `comment: null` | N/A |
| Avaliar com comentário | texto com espaços nas pontas | salvo aparado (trim) | N/A |
| Comentário longo | 281+ caracteres | campo limita em 280; Rules negam >280 via SDK | `permission-denied` → "Não foi possível salvar" |
| Forja | `comment` vazio `""`, número ou campo extra | escrita negada | Rules |
| Foto quebrada | `photoUrl` 404 ou ausente | card mostra fallback da categoria | sem erro visível |
| Card do feed | A e B avaliaram X, B com comentário | foto de X, bairro, "A e B foram aqui", média dos 3 eixos, comentário mais recente, "há 2 h" | N/A |
| Detalhe | toque no card | tela com foto grande e todas as avaliações dos amigos em X (eixos, comentário, companhia, período, tempo relativo) | abrir por URL sem dados → volta ao feed |

</frozen-after-approval>

## Code Map

Onda 1 já implementada (ver spec em `context`). Pontos de mudança:

- `app/lib/domain/models/place.dart` -- adicionar `photoUrl` (nullable); `app/lib/data/firebase/firestore_place_repository.dart` parse tolerante já existente
- `app/lib/domain/models/review.dart` + `app/lib/data/firebase/firestore_review_repository.dart:22` -- campo `comment` (nullable); payload passa de 9 para 10 chaves
- `firebase/firestore.rules:63` `reviewKeys()` e `validReview` -- incluir `comment`: `null` ou `string` com `1 <= size() <= 280`
- `app/lib/domain/feed.dart:5` `FeedItem` -- só tem `placeName`; o card precisa de `Place` (foto, bairro, categoria): `FeedViewModel` junta com `PlaceRepository` (≈20 locais, 1 leitura)
- `app/lib/ui/feed/feed_view.dart` (258 linhas) -- extrair card para `app/lib/ui/feed/widgets/`
- `app/lib/ui/review/review_view.dart` -- campo de comentário (`maxLength: 280`)
- `app/lib/routing/router.dart` -- rota `/local/:placeId` (extra = `FeedItem` + `Place`; sem extra → redirect ao feed, mesmo padrão da rota de avaliação)
- `app/android/app/src/main/AndroidManifest.xml:3` -- `android:label="naarea"` → `NaÁrea`
- `firebase/seed/places.json` -- `photoUrl` por local
- Python 3.13 + Pillow 11.3 disponíveis para gerar o PNG do ícone

## Tasks & Acceptance

**Execution:**
- [x] `firebase/firestore.rules` + `firebase/tests/**` -- testes vermelhos de `comment` (null ok, 1–280 ok, "" / 281 / número negados; chaves exatas agora 10), depois Rules
- [x] `app/lib/domain/**` + testes -- `Place.photoUrl`, `Review.comment` (normalização: trim, vazio → null), função pura `relativeTime(DateTime, now)` ("agora", "há 5 min", "há 2 h", "ontem", "há 3 dias", data curta depois de 7 dias), média dos eixos por avaliação
- [x] `app/lib/data/**` + testes -- payload com 10 chaves; place com `photoUrl`
- [x] `app/lib/ui/**` + testes -- `FeedViewModel` expõe itens com `Place`; card novo (foto 16:9 com fallback, bairro/categoria, avatares com inicial, "A e B foram aqui", eixos 🍽️ ✨ 🤝, comentário mais recente, período + tempo relativo); `PlaceDetailView`; campo de comentário na avaliação; pull-to-refresh no feed
- [x] `app/lib/ui/core/theme.dart` -- identidade: paleta pôr-do-sol potiguar (coral/laranja + areia + azul-mar), `google_fonts` (títulos com personalidade, corpo legível), cards arredondados com sombra suave, modo claro
- [x] `firebase/seed/places.json` -- `photoUrl` de fotos com licença livre (Wikimedia Commons/Unsplash, preferir da própria cidade/bairro; verificar que a URL responde 200); registrar fonte/licença em `firebase/seed/CREDITOS.md`
- [x] `app/assets/icon/` + `flutter_launcher_icons` -- ícone gerado via script Pillow (`tools/gerar_icone.py`), nome `NaÁrea` no Android/iOS/Web

**Acceptance Criteria:**
- Given feed com avaliações de amigos, when abre o app, then cada card mostra foto (ou fallback), bairro, quem foi, eixos e tempo relativo.
- Given card no feed, when toca, then abre o detalhe do local com todas as avaliações dos amigos ali.
- Given tela de avaliação, when envia sem comentário, then salva normalmente; com comentário, ele aparece no card de quem segue.
- Given APK instalado, when olha a tela inicial do Android, then vê ícone e nome "NaÁrea".

## Design Notes

Comentário vive na própria review (não subcoleção): mantém a imutabilidade das Rules e a leitura do feed numa consulta só. Fotos por URL evitam Storage (Blaze). `Image.network` com `errorBuilder` + `loadingBuilder` basta; na web, Wikimedia serve CORS.

## Verification

**Commands:**
- `cd app && flutter analyze` -- expected: No issues found
- `cd app && flutter test` -- expected: todos passam
- `cd firebase && export JAVA_HOME="/c/Program Files/Java/jdk-24" PATH="$JAVA_HOME/bin:$PATH" && firebase emulators:exec --only firestore "npm test"` -- expected: todos passam
- `cd app && flutter build apk --release` -- expected: `build/app/outputs/flutter-apk/app-release.apk` gerado

## Suggested Review Order

**Integridade do comentário**

- Ponto de entrada: `comment` null ou 1–280, chaves exatas agora 10.
  [`firestore.rules:63`](../../firebase/firestore.rules#L63)

- Normalização (trim, vazio → null) e contagem igual à das Rules.
  [`review.dart:1`](../../app/lib/domain/models/review.dart#L1)

**Feed e detalhe**

- Card: foto, quem foi, eixos, citação com autor e tempo próprios.
  [`feed_card.dart:1`](../../app/lib/ui/feed/widgets/feed_card.dart#L1)

- Detalhe do local: médias, avaliações dos amigos e crédito da foto.
  [`place_detail_view.dart:1`](../../app/lib/ui/place/place_detail_view.dart#L1)

- Foto com fallback, cacheWidth, fade-in e rótulo honesto.
  [`place_photo.dart:1`](../../app/lib/ui/feed/widgets/place_photo.dart#L1)

- Tempo relativo por dia do calendário de Natal (UTC-3).
  [`relative_time.dart:1`](../../app/lib/domain/relative_time.dart#L1)

**Identidade visual**

- Paleta pôr-do-sol potiguar, Fredoka + Nunito, contraste AA.
  [`theme.dart:1`](../../app/lib/ui/core/theme.dart#L1)

- Ícone gerado por script Pillow.
  [`gerar_icone.py:1`](../../tools/gerar_icone.py#L1)

**Periféricos**

- Fotos Wikimedia com autor, licença e flag ilustrativa.
  [`CREDITOS.md:1`](../../firebase/seed/CREDITOS.md#L1)
