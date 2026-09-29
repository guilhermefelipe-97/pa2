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

## 3. Seed dos locais (Natal/RN)

Os locais ficam em `../firebase/seed/places.json`. O cliente nunca escreve em
`places` (as Rules negam); só o seed, via Admin SDK.

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
