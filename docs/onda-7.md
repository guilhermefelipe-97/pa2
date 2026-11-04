# Onda 7 — Painel temporal, card compartilhável e freio do Destaque

Spec: `_bmad-output/implementation-artifacts/spec-onda-7-painel-compartilhar-freio.md`.

## O que entrou

| Cartão | Onde está no app | Regra |
|---|---|---|
| **F26** Suspensão automática do Destaque | Perto (seção Patrocinado) e Meus estabelecimentos → Divulgação | Slot só aparece com ≥ 5 avaliações nos últimos 90 dias e média de todas as notas de eixo ≥ 3,5. Abaixo disso, suspenso; volta sozinho. Falha de leitura esconde o slot. Cache de 10 min por local. |
| **F21** Card compartilhável com deep link | Ficha do local → ícone Compartilhar | Imagem do card (nome, categoria/bairro, médias dos eixos da rede, quem enviou) + texto com `https://naarea-natal.web.app/l/<id>`. O link leva só o id do local. |
| **F23** Painel com série temporal | Meus estabelecimentos → ícone Painel do local | 12 meses (UTC−3), médias separadas de comida/ambiente/atendimento, avaliações e "Voltei aqui" por mês, recorte por período do dia, aviso de amostra pequena (< 3). Só o titular atual. |

## Roteiro de teste manual (emulador)

1. **F26**: com `config/features.sponsorshipEnabled = true` e um slot vigente de local com titular, cadastrar 5 avaliações recentes com média ≥ 3,5 → Perto mostra o Destaque. Adicionar avaliações baixas até a média ficar < 3,5 e esperar 10 min (ou reabrir o app) → o Destaque some. Em Divulgação o titular lê "Destaque suspenso: média … abaixo do piso de 3,5".
2. **F21**: abrir uma ficha → Compartilhar → conferir a prévia → Enviar → escolher o WhatsApp. No Android, `adb shell am start -a android.intent.action.VIEW -d "naarea://app/l/<id>"` abre a ficha; deslogado, passa pelo login e volta para a ficha.
3. **F23**: como titular, Meus estabelecimentos → Painel do local → trocar Todos/Noite e conferir a lista mês a mês.

## Pendente antes de ir ao ar (precisa de autorização)

- `firebase deploy --only hosting`: publica a página `hosting/public/l/index.html`. Sem isso o link do card dá 404.
- `firebase deploy --only firestore:indexes`: índice novo `visits (placeId ASC, createdAt DESC)` usado pelo painel. Rules não mudaram.
- App Links verificados (abrir o app direto pelo link https) exigem `/.well-known/assetlinks.json` com o SHA-256 do certificado de assinatura. Sem isso, o link abre a página e o botão "Abrir no app" usa `naarea://`.
- Destaque continua desligado em produção (`FirestoreSponsorshipRepository` só lê slots no emulador). Ligar é decisão da usuária.

## Fora desta onda

Funil do Destaque no painel (impressões → visitas → salvamentos), decidido em 04/11/2026 para quando o Destaque for ativado.
