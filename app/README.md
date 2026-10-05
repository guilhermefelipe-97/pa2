# NaÁrea (app)

App Flutter do NaÁrea: avaliação em 3 eixos (comida, ambiente, atendimento) com
contexto e o feed "Amigos foram aqui". Arquitetura MVVM (`lib/ui` View +
ViewModel, `lib/domain` modelos, `lib/data` repositórios), `provider` +
`go_router`, backend Firebase no plano Spark (Auth e-mail/senha + Firestore).

A integridade dos dados é garantida pelas Security Rules em
`../firebase/firestore.rules`, testadas no Emulator.

## Pré-requisitos

- Flutter 3.38+ / Dart 3.10+
- Node 20+ (testes das Rules, seed e Firebase CLI)
- JDK 11 ou superior para os emuladores do Firebase. Se o `java` do PATH for
  mais antigo (ex.: 1.8), aponte `JAVA_HOME` para um JDK 11+ antes de rodar
  qualquer comando `firebase emulators:*`:

  ```bash
  # Git Bash (ajuste para o caminho do seu JDK)
  export JAVA_HOME="/c/Program Files/Java/jdk-24"
  export PATH="$JAVA_HOME/bin:$PATH"
  ```

- Firebase CLI: global (`npm i -g firebase-tools`) ou a versão local de
  `../firebase` (`cd ../firebase && npm install && npx firebase --version`).
- FlutterFire CLI: `dart pub global activate flutterfire_cli`.

## 1. Configurar o projeto Firebase

```bash
firebase login                       # ou: firebase login --reauth
firebase projects:create <id> --display-name "NaÁrea"
firebase firestore:databases:create "(default)" --location southamerica-east1 --project <id>

cd app
flutterfire configure --project=<id> --platforms=android,ios,web
cd ..
```

`flutterfire configure` substitui o placeholder `lib/firebase_options.dart`.
Enquanto ele não rodar, o app abre uma tela explicando o que falta.

Depois, na raiz do repositório:

1. Em `.firebaserc`, `default` continua `demo-naarea` (emulator, nunca toca
   produção) e o alias `prod` aponta para o projeto real (`naarea-natal`).
2. Publique Rules e índices:
   `firebase deploy --only firestore:rules,firestore:indexes --project prod`.
3. No console do Firebase, em Authentication > Sign-in method, habilite
   **E-mail/senha**.

## 2. Rodar o app

### Atalho no Windows (PowerShell)

Scripts em `../scripts/` que funcionam de qualquer pasta:

```powershell
# Terminal 1 — emuladores (deixe aberto)
powershell -ExecutionPolicy Bypass -File scripts\emuladores.ps1
# Terminal 2 — locais de Natal no emulador + app no Chrome
powershell -ExecutionPolicy Bypass -File scripts\seed-emulador.ps1
powershell -ExecutionPolicy Bypass -File scripts\app-emulador.ps1
```

> No PowerShell, `--only auth,firestore` sem aspas vira array e a CLI responde
> "No emulators to start". Use `--only "auth,firestore"` (os scripts já fazem isso).


Contra o projeto real:

```bash
flutter run -d chrome
```

Contra os emuladores locais (auth na 9099, firestore na 8080), em outro terminal
na raiz do repositório:

```bash
firebase emulators:start --only auth,firestore
```

e então:

```bash
flutter run -d chrome --dart-define=USE_EMULATOR=true
```

No emulador Android o app usa `10.0.2.2` automaticamente. Mesmo no modo
emulador é preciso ter `lib/firebase_options.dart` gerado.

## 3. Locais de Natal/RN: import do OpenStreetMap + seed

O catálogo de `places` tem duas fontes, ambas versionadas em `../firebase/seed/`:

- `places.json` — 20 locais **curados** (foto, categoria e bairro conferidos à mão);
- `osm-natal.json` — **snapshot do OpenStreetMap** (~600 locais de comer/beber
  de Natal com bairro, coordenadas, geohash, cozinha, endereço e horário bruto),
  gerado pelo import. Dados © OpenStreetMap contributors, licença ODbL
  (ver `../firebase/seed/CREDITOS.md`; o app mostra o crédito no seletor e no
  detalhe).

O cliente nunca escreve em `places` (as Rules negam); só o seed, via Admin SDK.

### 3.1 Atualizar o snapshot (opcional, precisa de internet)

```bash
cd ../firebase
npm install
npm run import:osm
```

O script consulta a Overpass API (sem chave nem cartão; `OVERPASS_URL` aceita
outros endpoints separados por vírgula), calcula o bairro de cada local pelos
polígonos dos 38 bairros oficiais (`admin_level=10`), junta o mesmo local
mapeado como ponto e como prédio (fica o prédio) e grava `seed/osm-natal.json`
ordenado por id — rodar duas vezes com o mesmo dado do OSM gera o mesmo
arquivo. O snapshot existente **não** é tocado se o Overpass falhar, se vierem
menos de 34 bairros ou menos de 80% dos locais do snapshot anterior. Revise o
diff e faça commit do arquivo.

Por padrão o `import:osm` não toca no Firestore. Para gravar em `places` logo
em seguida, passe o flag explícito `--seed` (com as variáveis do seed abaixo):

```bash
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 GCLOUD_PROJECT=demo-naarea npm run import:osm -- --seed
```

### 3.2 Gravar em `places` (offline, a partir dos arquivos)

Emulador (com `firebase emulators:start` rodando):

```bash
cd ../firebase
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 GCLOUD_PROJECT=demo-naarea npm run seed
```

Produção: gere uma chave de service account no console (Configurações do
projeto > Contas de serviço), **salve fora do repositório** e aponte a variável
de ambiente para ela:

```bash
cd ../firebase
GOOGLE_APPLICATION_CREDENTIALS=/caminho/fora/do/repo/sa.json GCLOUD_PROJECT=<id> npm run seed
```

**Ordem de deploy em produção** (a busca do app depende do índice e dos campos
novos do seed):

1. Índices: `firebase deploy --only firestore:indexes --project prod`.
2. Aguardar o build do índice `places (searchTokens, nameLower)` ficar
   **Ativado** no console (Firestore > Índices). Antes disso a busca falha.
3. Seed (comando acima), que grava `searchTokens`, `nameLower` e `source`.
4. Publicar o app.

O seed é idempotente: monta os documentos de forma determinística, grava só os
que mudaram (`updatedAt` só muda quando o conteúdo muda) e nunca apaga
documentos (os que saíram da fonte são listados no log). Os curados mantêm o
id (avaliações apontam para eles): quando o nome normalizado casa com **um
único** local do OSM de bairro compatível (igual, ou ausente em um dos lados),
o curado recebe coordenadas, `osmId`, cozinha, endereço e horário, e o
duplicado do OSM não é criado; casamento ambíguo (2+) mantém os dois e aparece
no log. Um `osmId` (ex.: `"way/483561432"`) no curado em `places.json` força o
casamento com aquele local.

A busca do app usa `searchTokens` (prefixos ≥ 2 de cada palavra do nome, sem
acento/caixa) com `array-contains` + `orderBy nameLower`, o que exige o índice
composto de `../firebase/firestore.indexes.json` em produção. As regras de
normalização são as mesmas no script (`seed/osm/tokens.js`) e no app
(`lib/domain/search_tokens.dart`), testadas contra a mesma fixture.

O `.gitignore` bloqueia os nomes usuais de chave, mas não conte com isso: a
chave não deve ficar dentro do repositório.

## 4. Testes

App (ViewModels com fakes escritos à mão; repositórios Firestore com
`fake_cloud_firestore` e `firebase_auth_mocks`):

```bash
flutter analyze
flutter test
```

### Testes das Rules

Rodam no Emulator do Firestore (`@firebase/rules-unit-testing` + mocha). Exigem
`JAVA_HOME` com JDK 11+ (ver Pré-requisitos):

```bash
cd ../firebase
npm install
npx firebase emulators:exec --only firestore "npm test"
# ou: npm run test:emulator
```

As funções puras do import do OSM (tokens, categoria, bairro por polígono,
geohash, casamento com os curados) não precisam do emulador:

```bash
cd ../firebase
npx mocha tests/osm.test.js   # ou: npm run test:osm
```
