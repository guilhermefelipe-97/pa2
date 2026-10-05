---
title: 'G1 — Foto do local enviada por quem avaliou'
type: 'feature'
created: '2026-10-05'
status: 'done'
baseline_commit: '95eeefb80ed49abb8943c371a502a54954733e56'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-feed-rico-fotos-comentario-visual.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-g0-catalogo-osm.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** O catálogo OSM não tem fotos e não há API de fotos sem cartão. Cards sem foto real enfraquecem a confiança e o apelo visual.

**Approach:** Ao avaliar, a pessoa pode anexar 1 foto (câmera ou galeria), opcional. O app reduz para no máximo 1080 px no lado maior e recodifica em JPEG até ≤ 150 KB (o que também remove EXIF/GPS), e grava os bytes em `reviewPhotos/{reviewId}` no mesmo batch da avaliação (sem Storage, plano Spark). Feed e detalhe mostram a foto mais recente dos amigos naquele local com crédito "Foto de Ana"; sem foto de amigo, cai na foto do catálogo e depois no fallback de categoria.

## Boundaries & Constraints

**Always:** Foto opcional — avaliar sem foto continua idêntico. Sempre recodificar no cliente (nunca subir o arquivo original). Foto imutável e ligada à avaliação: Rules exigem que a review do mesmo id seja criada no mesmo batch pelo mesmo autor, com `hasPhoto: true`. Bytes ≤ 150.000. Leitura só autenticada. Foto carregada sob demanda (só quando o card/tile aparece) com cache em memória; nunca bloqueia o feed. Crédito com o nome do autor sempre visível sobre a foto. Acessível: rótulo "Foto de <nome> em <local>".

**Ask First:** Mais de 1 foto por avaliação; foto sem avaliação; denunciar/moderar fotos.

**Never:** Firebase Storage/Blaze; serviço externo de imagens; vídeo; filtros/edição.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Anexar | foto 4000×3000, 5 MB, com GPS no EXIF | prévia na tela de avaliação; enviada ≤1080 px, ≤150 KB, sem EXIF | compressão falha → "Não foi possível usar essa foto" e segue sem foto |
| Trocar/remover | toque na prévia | opções "Trocar foto" / "Remover foto" | N/A |
| Enviar com foto | 3 eixos + foto | batch: review com `hasPhoto: true` + `reviewPhotos/{id}` | falha → nada gravado, "Não foi possível salvar" |
| Sem foto | 3 eixos | review com `hasPhoto: false`, sem doc de foto | N/A |
| Forja via SDK | foto sem review no batch, review de outro autor, `hasPhoto: true` sem foto, >150.000 bytes, não-bytes, update/delete | negado | Rules |
| Card | amigos A (com foto, há 1 h) e B (sem foto) em X | foto de A com "Foto de A" | foto falha ao carregar → foto do catálogo/fallback, sem erro visível |
| Detalhe | 3 avaliações com foto | faixa horizontal de fotos; toque abre em tela cheia com crédito e tempo relativo | idem |
| Review antiga | sem chave `hasPhoto` | tratada como sem foto | N/A |
| Cancelar seleção | fecha câmera/galeria | nada muda | permissão negada → mensagem explicando como liberar |

</frozen-after-approval>

## Code Map

- `firebase/firestore.rules` `reviewKeys()`/`validReview`/`match /reviews` -- schema exato de 10 chaves; passa a 11 com `hasPhoto` (bool); se `true`, `existsAfter(reviewPhotos/$(reviewId))`
- `firebase/tests/firestore.rules.test.js` -- suíte de Rules
- `app/lib/domain/models/review.dart` -- `Review`/`NewReview`; adicionar `hasPhoto` (leitura tolerante: ausente = false)
- `app/lib/data/repositories/review_repository.dart:7` + `firestore_review_repository.dart` -- `createReview(NewReview, {Uint8List? photo})` vira batch com id gerado no cliente; novo `ReviewPhotoRepository.getPhoto(reviewId)` com cache/dedupe em voo
- `app/lib/ui/review/review_view_model.dart:93` + `review_view.dart` -- estado da foto (prévia, comprimindo, erro), seletor câmera/galeria
- `app/lib/ui/feed/widgets/place_photo.dart:11` -- hoje só `place.photoUrl` + fallback; passa a aceitar foto de amigo (bytes) com crédito
- `app/lib/domain/feed.dart` -- `FeedItem` escolhe a review mais recente com `hasPhoto`
- `app/lib/ui/place/place_detail_view.dart` -- faixa de fotos + visualizador em tela cheia
- Pacotes: `image_picker` (câmera/galeria, web incluso) e `image` (decodificar/redimensionar/JPEG, em `compute`)

## Tasks & Acceptance

**Execution:**
- [x] `firebase/tests/**` + `firebase/firestore.rules` -- testes vermelhos (matriz "Forja"; review sem `hasPhoto` agora negada; batch válido aceito), depois Rules
- [x] `app/lib/domain/**` + testes -- `hasPhoto`; `compressPhoto(bytes) -> Uint8List` pura (redimensiona ≤1080, baixa qualidade 85→40 até ≤150.000; erro se não couber) testada com imagem sintética grande e com EXIF
- [x] `app/lib/data/**` + testes -- batch review+foto; `ReviewPhotoRepository` (cache, dedupe)
- [x] `app/lib/ui/review/**` + testes -- anexar/trocar/remover, prévia, estados
- [x] `app/lib/ui/feed/**`, `app/lib/ui/place/**` + testes -- foto do amigo no card com crédito, faixa e tela cheia no detalhe
- [x] Android/iOS -- permissões de câmera/galeria (`AndroidManifest.xml`, `Info.plist` com textos em pt-BR)

**Acceptance Criteria:**
- Given Ana avalia o Mangai com foto, when Bianca (que segue Ana) abre o feed, then o card do Mangai mostra a foto com "Foto de Ana".
- Given a mesma avaliação, when inspeciono `reviewPhotos/{id}`, then os bytes têm ≤150.000 e o JPEG não tem EXIF.

## Verification

**Commands:**
- `cd app && flutter analyze` -- expected: No issues found
- `cd app && flutter test` -- expected: todos passam
- `cd firebase && export JAVA_HOME="/c/Program Files/Java/jdk-24" PATH="$JAVA_HOME/bin:$PATH" && firebase emulators:exec --only firestore "npm test"` -- expected: todos passam

## Spec Change Log

- Revisão 1 (patches, sem loopback): Rules aceitam review sem `hasPhoto` (janela de transição para builds antigos, tratada como `false`); `reviewPhotos.jpeg` exige marcador JPEG (`ffd8ff`); permissão `CAMERA` removida do Android (captura por intent). KEEP: batch review+foto com id do cliente, recodificação obrigatória no cliente.

## Suggested Review Order

**Integridade**

- Ponto de entrada: foto só junto da review, mesmo autor, ≤150.000 bytes, JPEG.
  [`firestore.rules:182`](../../firebase/firestore.rules#L182)

- `hasPhoto` opcional (transição) e `true` exige a foto no mesmo batch.
  [`firestore.rules:141`](../../firebase/firestore.rules#L141)

**Privacidade e tamanho**

- Recodifica: orientação EXIF aplicada, ≤1080 px, sem EXIF, qualidade 85→40.
  [`photo_compression.dart:39`](../../app/lib/domain/photo_compression.dart#L39)

- Batch review + foto com id gerado no cliente.
  [`firestore_review_repository.dart:32`](../../app/lib/data/firebase/firestore_review_repository.dart#L32)

**Leitura e exibição**

- Cache LRU, dedupe, backoff e `peek` síncrono; limpa ao trocar de usuário.
  [`review_photo_repository.dart:36`](../../app/lib/data/repositories/review_photo_repository.dart#L36)

- Foto do amigo com crédito; "Sua foto" por `isOwn`.
  [`review_photo.dart:33`](../../app/lib/ui/feed/widgets/review_photo.dart#L33)

- Faixa e tela cheia com zoom e swipe coordenados.
  [`review_photo_strip.dart:11`](../../app/lib/ui/place/review_photo_strip.dart#L11)

**Captura**

- Anexar/trocar com guarda de duplo toque; troca falha mantém a anterior.
  [`review_view_model.dart:144`](../../app/lib/ui/review/review_view_model.dart#L144)

- Mapeamento de erros de plataforma (permissão, sem câmera).
  [`photo_picker.dart:38`](../../app/lib/data/services/photo_picker.dart#L38)
