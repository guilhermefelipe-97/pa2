# NaÁrea

O NaÁrea é um aplicativo de descoberta social de lugares para comer e sair, com catálogo inicial em Natal (RN). Ele ajuda a escolher um restaurante, bar ou café a partir de experiências de pessoas que você segue e de informações da comunidade, como faixa de preço, funcionamento e fila.

## O que o app oferece

- **Descoberta de lugares** pelo feed de pessoas que você segue, pela busca ou pelo mapa de locais próximos.
- **Avaliações com contexto** que identificam quem visitou o local e separam as notas de comida, ambiente e atendimento. O app também indica quando duas pessoas têm gostos parecidos com base em avaliações de lugares em comum.
- **Quero ir** para salvar lugares, organizar listas e copiar seleções de outras pessoas com crédito à autoria. O **Decidir por mim** ajuda a escolher entre os lugares salvos.
- **Informações da comunidade** sobre faixa de preço, funcionamento, fila, couvert e taxa de serviço, além de categorias de comida caseira como marmita, quentinha e self-service por quilo.
- **Compartilhamento de lugares** por meio de cards com link para a ficha do estabelecimento.
- **Área do estabelecimento** para titulares verificados responderem publicamente às avaliações e acompanharem a evolução das notas por período.

O modelo de receita previsto é o **Destaque patrocinado**, um espaço identificado como publicidade e separado das recomendações de amigos. A exibição depende de critérios de qualidade, e o recurso permanece desativado em produção.

## Tecnologias e organização

O aplicativo usa **Flutter e Dart**, com arquitetura MVVM, **Firebase Authentication** para acesso por e-mail e senha e **Cloud Firestore** para armazenamento. O catálogo usa dados do OpenStreetMap.

| Pasta | Conteúdo |
| --- | --- |
| [app/](app/) | Aplicativo Flutter, testes e instruções de configuração |
| [firebase/](firebase/) | Regras de acesso, índices, catálogo inicial e testes do Firestore |
| [hosting/](hosting/) | Página web para os links de compartilhamento |
| [scripts/](scripts/) | Atalhos para desenvolvimento local no Windows |
| [docs/](docs/) | Documentação de produto e implementação |

## Executar localmente

Você vai precisar do Flutter com Dart 3.10.1 ou superior dentro da série 3.x. Para os emuladores do Firebase, use Node.js 20+, JDK 21+ e Firebase CLI. Gere a configuração local do aplicativo com o FlutterFire CLI seguindo o [guia de configuração](app/README.md#1-configurar-o-projeto-firebase). Para desenvolvimento local, use o projeto de demonstração dos emuladores nos comandos abaixo.

Em um terminal, a partir da raiz do repositório, inicie os emuladores:

```bash
firebase emulators:start --only "auth,firestore" --project demo-naarea
```

Em outro terminal, também a partir da raiz, execute o app:

```bash
cd app
flutter pub get
flutter run -d chrome --dart-define=USE_EMULATOR=true
```

Para preencher o catálogo de desenvolvimento, siga as [instruções de carga de dados no emulador](app/README.md#32-gravar-em-places-offline-a-partir-dos-arquivos).

## Verificações

Para analisar e testar o aplicativo, a partir da raiz:

```bash
cd app
flutter analyze
flutter test
```

Para testar as regras de acesso e os utilitários do Firebase, em outro terminal na raiz:

```bash
cd firebase
npm ci
npm run test:emulator
```

## Documentação do produto

- [Visão do NaÁrea](docs/lean-inception/visao-restricoes.md)
- [Sequenciador do MVP e das oito ondas](docs/lean-inception/sequenciador-mvp.md)
- [Onda 7 — painel temporal, compartilhamento e suspensão do Destaque](docs/onda-7.md)
- [Onda 8 — afinidade, comida caseira e informações de cobrança](docs/onda-8.md)
- [Créditos dos dados do OpenStreetMap](firebase/seed/CREDITOS.md)
