---
title: 'Onda 1 — Fundação do app, avaliação em 3 eixos com contexto e feed "Amigos foram aqui"'
type: 'feature'
created: '2026-09-28'
status: 'done'
baseline_commit: 'c52f81cc224d1eed3e2a4a60db86b66e91c5f060'
review_loop_iteration: 0
context:
  - '{project-root}/docs/lean-inception/visao-restricoes.md'
  - '{project-root}/docs/lean-inception/tradeoffs-arquitetura.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** O NaÁrea não tem código. A Onda 1 do sequenciador exige as duas decisões mais caras de corrigir depois — o modelo de avaliação (F01 3 eixos + F02 contexto) e o grafo social que alimenta o feed "Amigos foram aqui" (F05).

**Approach:** App Flutter em `app/` (pacote `naarea`), MVVM do guia oficial (`ui/` View+ViewModel `ChangeNotifier`, `domain/` modelos, `data/` repositórios+services), `provider` + `go_router`. Backend Firebase no plano Spark: Auth e-mail/senha, Firestore, integridade garantida por Security Rules testadas no Emulator. Locais de Natal/RN via seed. F11 ficou para spec próprio (`deferred-work.md`).

## Boundaries & Constraints

**Always:** Toda avaliação tem autor autenticado com nome (nunca anônima). Os 3 eixos (comida, ambiente, atendimento) são inteiros 1–5, todos obrigatórios. `createdAt` é timestamp do servidor. Período do dia é derivado de `createdAt` em UTC-3 (America/Fortaleza), nunca gravado pelo cliente. Integridade vence performance (`tradeoffs-arquitetura.md`). ViewModels testados com fakes escritos à mão.

**Ask First:** Qualquer serviço que exija plano Blaze/cartão (Cloud Functions, Places API). Mudar o schema do Firestore além do descrito. Adicionar pacote de estado além de `provider`.

**Never:** Nota única agregada; avaliação sem login; editar/excluir avaliação (fica para F03/F04); cliente escrevendo em `places`; F11, listas, match de gosto; texto de review; segredos/chaves de service account no git.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Avaliar | logado, 3 eixos 1–5, companhia opcional | doc em `reviews` com `authorId`=uid, `authorName`=nome do perfil, `createdAt`=servidor | N/A |
| Eixo faltando | 2 de 3 eixos preenchidos | botão Enviar desabilitado | ViewModel não chama repositório |
| Forja via SDK | `authorId` de outro uid, nota 0/6, `createdAt` do cliente, campo extra | escrita negada | Rules `permission-denied`; UI mostra "Não foi possível salvar" |
| Feed vazio | não segue ninguém | estado vazio com CTA "Encontrar pessoas" | N/A |
| Feed | segue A e B, ambos avaliaram o local X | 1 card de X com "A e B foram aqui", ordenado pela avaliação mais recente | erro de rede → mensagem + "Tentar de novo" |
| Seguir mais de 30 | `following` > 30 uids | consulta em lotes de 30 (limite do `whereIn`) e merge | N/A |
| Cadastro | nome vazio ou só espaços | cadastro bloqueado | mensagem de validação |

</frozen-after-approval>

## Code Map

Repositório greenfield: nenhum código Flutter/Firebase existe. Toolchain local: Flutter 3.38.3 / Dart 3.10.1, Firebase CLI 14.26.0, JDK 24 em `C:/Program Files/Java/jdk-24` (o `java` do PATH é 1.8 — o Emulator exige `JAVA_HOME` apontando para o JDK 24). `flutterfire` CLI não instalada.

- `app/lib/domain/models/` -- `Place`, `Review`, `Scores`, `Companion` (sozinho|casal|amigos|familia|trabalho), `DayPeriod` + `DayPeriod.fromTimestamp` (manhã 5–11, almoço 11–14, tarde 14–18, noite 18–24, madrugada 0–5, UTC-3)
- `app/lib/domain/feed.dart` -- função pura `groupReviewsIntoFeed(reviews) -> List<FeedItem>`
- `app/lib/data/` -- `AuthRepository`, `UserRepository` (perfil, busca por prefixo de `displayNameLower`, seguir/deixar de seguir), `PlaceRepository`, `ReviewRepository` (criar, feed por `authorId whereIn` em lotes)
- `app/lib/ui/{auth,feed,people,review}/` -- View + ViewModel por tela
- `firebase/firestore.rules`, `firebase/firestore.indexes.json` -- integridade e índice `reviews(authorId ASC, createdAt DESC)`
- `firebase/tests/` -- testes das Rules (`@firebase/rules-unit-testing`, mocha)
- `firebase/seed/` -- script Node `firebase-admin` com ~20 locais reais de Natal/RN

## Tasks & Acceptance

**Execution:**
- [x] `app/` -- `flutter create --org br.naarea --project-name naarea --platforms android,ios,web`; deps `provider`, `go_router`, `firebase_core`, `firebase_auth`, `cloud_firestore` -- fundação
- [x] `app/lib/domain/**` + `app/test/domain/**` -- modelos, `DayPeriod.fromTimestamp`, `groupReviewsIntoFeed`; testes primeiro (fronteiras de período, agrupamento e ordenação) -- regras puras
- [x] `firebase/firestore.rules` + `firebase/tests/**` -- Rules primeiro como testes vermelhos: `users/{uid}` só o dono escreve, `displayName` não vazio; `users/{uid}/following/{t}` só o dono; `places` leitura autenticada, escrita negada; `reviews` create validando autor, nome = perfil, `hasOnly` de chaves, eixos int 1–5, `createdAt == request.time`, `companion` na lista ou null; update/delete negados -- guardrails da Fase 1
- [x] `app/lib/data/**` -- repositórios abstratos + implementação Firestore -- a UI nunca toca Firebase diretamente
- [x] `app/lib/ui/**` + `app/test/ui/**` -- ViewModels (Auth, Feed, People, PlacePicker, Review) testados com repositórios fake; Views com `ListenableBuilder`; rotas `go_router` com redirect por estado de auth -- MVVM
- [x] `firebase/seed/**` -- seed de `places` (Natal/RN) contra emulator e produção (service account via variável de ambiente, arquivo no `.gitignore`) -- dados reais
- [x] `firebase.json`, `.firebaserc`, `.gitignore` -- emulators (auth, firestore), paths de rules/indexes -- configuração
- [x] Projeto Firebase -- após `firebase login` do usuário: `projects:create`, Firestore em `southamerica-east1`, `flutterfire configure`, deploy de rules/indexes; habilitar provedor e-mail/senha (console, se a CLI não permitir) -- backend real (projeto `naarea-natal` criado, Firestore, flutterfire e deploy feitos; provedor e-mail/senha pendente no console pelo usuário)

**Acceptance Criteria:**
- Given usuário novo, when se cadastra com nome, e-mail e senha, then cai no feed e o doc `users/{uid}` existe com `displayName`.
- Given usuário logado na tela Pessoas, when busca "bia" e toca Seguir, then as avaliações de Bianca passam a aparecer no feed.
- Given usuário logado, when escolhe um local, dá 1–5 nos 3 eixos e envia, then a avaliação aparece no feed de quem o segue com nome do autor, os 3 eixos e o período do dia.
- Given app fechado com sessão ativa, when reabre, then vai direto ao feed.

## Design Notes

Feed = `reviews where authorId in [lote≤30] orderBy createdAt desc limit 100`, lotes em paralelo, merge e depois `groupReviewsIntoFeed`. `authorName`/`placeName` desnormalizados na review evitam N leituras por card; a Rule garante `authorName == get(users/$(uid)).data.displayName` no momento da escrita. Período não é gravado: derivado do `createdAt`, não pode divergir.

## Verification

**Commands:**
- `cd app && flutter analyze` -- expected: No issues found
- `cd app && flutter test` -- expected: todos passam
- `cd firebase && export JAVA_HOME="/c/Program Files/Java/jdk-24" PATH="$JAVA_HOME/bin:$PATH" && firebase emulators:exec --only firestore "npm test"` -- expected: todos os testes de Rules passam

**Manual checks (if no CLI):**
- `flutter run -d chrome` com dois usuários: B segue A, A avalia, B vê o card.

## Suggested Review Order

**Integridade (guardrails da Fase 1)**

- Ponto de entrada: a Rule que impede avaliação anônima, forjada ou fora de 1–5.
  [`firestore.rules:68`](../../firebase/firestore.rules#L68)

- Avaliações imutáveis nesta onda; edição/exclusão ficam para F03/F04.
  [`firestore.rules:85`](../../firebase/firestore.rules#L85)

- Nome do perfil congelado: `authorName` desnormalizado nunca fica desatualizado.
  [`firestore.rules:31`](../../firebase/firestore.rules#L31)

- Seguir exige alvo existente; grafo social do F05.
  [`firestore.rules:36`](../../firebase/firestore.rules#L36)

**Modelo de avaliação (F01 + F02)**

- Período derivado do `createdAt` em UTC-3, nunca gravado pelo cliente.
  [`day_period.dart:20`](../../app/lib/domain/models/day_period.dart#L20)

- Payload exato de 9 chaves casando com o `hasOnly` das Rules.
  [`firestore_review_repository.dart:22`](../../app/lib/data/firebase/firestore_review_repository.dart#L22)

- Envio só com os 3 eixos preenchidos.
  [`review_view_model.dart:45`](../../app/lib/ui/review/review_view_model.dart#L45)

**Feed "Amigos foram aqui" (F05)**

- Agrupamento puro por local, "A e B foram aqui", ordenado pela mais recente.
  [`feed.dart:41`](../../app/lib/domain/feed.dart#L41)

- `whereIn` em lotes de 30 com corte consistente entre lotes.
  [`firestore_review_repository.dart:39`](../../app/lib/data/firebase/firestore_review_repository.dart#L39)

- Recarga pedida durante carga é enfileirada, não descartada.
  [`feed_view_model.dart:44`](../../app/lib/ui/feed/feed_view_model.dart#L44)

- Busca por prefixo com limite superior explícito `\uf8ff`.
  [`firestore_user_repository.dart:34`](../../app/lib/data/firebase/firestore_user_repository.dart#L34)

- Estado de seguir: init com retry, merge de corrida e reconciliação.
  [`people_view_model.dart:115`](../../app/lib/ui/people/people_view_model.dart#L115)

**Autenticação e navegação**

- Cadastro só publica sessão após o perfil existir; rollback sem órfãos.
  [`firebase_auth_repository.dart:51`](../../app/lib/data/firebase/firebase_auth_repository.dart#L51)

- Login recupera perfil ausente ou recusa a sessão.
  [`firebase_auth_repository.dart:101`](../../app/lib/data/firebase/firebase_auth_repository.dart#L101)

- Redirect por estado de auth; rota de avaliação sem `Place` volta ao seletor.
  [`router.dart:22`](../../app/lib/routing/router.dart#L22)

- Inicialização com emulator opcional e tela de erro de setup.
  [`main.dart:27`](../../app/lib/main.dart#L27)

**Periféricos**

- Índice composto exigido pela consulta do feed em produção.
  [`firestore.indexes.json:4`](../../firebase/firestore.indexes.json#L4)

- Suíte de Rules (39 testes) contra o emulator.
  [`firestore.rules.test.js:1`](../../firebase/tests/firestore.rules.test.js#L1)

- Seed de 20 locais de Natal/RN — nomes precisam de conferência humana.
  [`places.json:1`](../../firebase/seed/places.json#L1)

- Setup completo: login, flutterfire, deploy com alias `prod`, emuladores, seed.
  [`README.md:29`](../../app/README.md#L29)
