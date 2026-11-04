---
title: 'Patrocinado na descoberta e divulgação na área do titular'
type: 'refactor'
created: '2026-10-31'
status: 'done'
baseline_commit: '6297ca997a649d3c256af2ae566fda313c594002'
review_loop_iteration: 0
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** O acesso a Patrocinado no perfil parece uma configuração pessoal.

**Approach:** Conforme a proposta aprovada pelo usuário com “então faça assim”, mostrar os destaques na descoberta Perto, identificados como Patrocinado. Reservar divulgação comercial à área do titular.

## Boundaries & Constraints

**Always:** Retirar o atalho do perfil; colocar seção reutilizável na descoberta sem interferir no ranking orgânico nem no feed Amigos. Seção vazia, indisponível ou carregando não ocupa espaço nem bloqueia descoberta. Preservar navegação à ficha, expiração, cargas serializadas, timeout e isolamento de sessão. Titular aprovado encontra em Meus estabelecimentos uma entrada Divulgação que informa claramente indisponibilidade atual, sem botões de compra ou promessa de contratação. Preservar listagem de avaliações e permissões. Produção continua desligada, sem mudanças nas Rules, flag, slots ou backend.

**Ask First:** Ativar anúncios, pagamentos ou contratação.

**Never:** Criar campanha fictícia, misturar anúncios a Amigos, mudar escopo F23/F26 ou ranking.

## I/O & Edge-Case Matrix

| Estado | Comportamento |
|---|---|
| Slot válido no emulador | Perto mostra seção Patrocinado e ficha abre pelo card |
| Vazio, erro, lento ou expirado | Descoberta permanece utilizável; seção sem cards fica oculta |
| Perfil próprio | Atalho Patrocinado ausente |
| Titular atual / pedido pendente | Divulgação disponível só para titular atual; informa indisponibilidade comercial |

</frozen-after-approval>

## Code Map

- `app/lib/ui/profile/profile_view.dart`: actions do perfil próprio contêm TextButton Patrocinado; remover somente esse atalho.
- `app/lib/ui/nearby/nearby_view.dart`: aba Perto, `_results` tem cabeçalhos e lista orgânica; integrar componente destacado sem ranquear anúncios. Estados vazios/erro/GPS preservados.
- `app/lib/ui/sponsored/sponsored_view.dart`: reaproveitar `_Slots` com modo compacto/embutido e exportar seção. Manter SponsoredView para rota/compatibilidade. Repositório opcional em harnesses antigos.
- `app/lib/data/firebase/firestore_sponsorship_repository.dart`: produção retorna []; somente leitura como contexto, não mudar.
- `app/lib/ui/owner/owner_view.dart`: `row.owned` controla ações por local. Divulgação informa indisponibilidade, sem nova API comercial.
- `app/test/ui/wave6_widgets_test.dart`, testes nearby/profile/owner: reutilizar fakes/harness. `docs/onda-6.md` atualizar localização do consumidor.

## Tasks & Acceptance

- [x] `app/lib/ui/profile/`, `nearby/`, `sponsored/`: mover apresentação e preservar estados existentes.
- [x] `app/lib/ui/owner/owner_view.dart`: divulgação exclusiva do titular atual.
- [x] `app/test/ui/`: verificar matriz e regressões relevantes.
- [x] `docs/onda-6.md`, `app/pubspec.yaml`: documentar Perto e versão 1.2.1+5.

**Acceptance Criteria:**
- Given usuário na descoberta, when há destaque vigente, then vê Patrocinado separado da lista orgânica.
- Given perfil próprio ou feed Amigos, when navega, then não encontra o antigo atalho nem anúncios no feed.
- Given titular atual, when abre Divulgação, then entende que a contratação está indisponível.

## Spec Change Log

- 2026-10-31: revisão aplicada sem mudanças no bloco frozen. Seção compacta limitada a três cards com acesso ao catálogo completo; explicação de raio/filtro e suspensão das atualizações periódicas enquanto a aba está inativa. Ampliada a cobertura da matriz e das regressões.

## Verification

Análise estática e testes de interface relevantes. SDK: C:/Users/Jeane/flutter/flutter/bin/cache/dart-sdk/bin/dart.exe seguido de C:/Users/Jeane/flutter/flutter/bin/cache/flutter_tools.snapshot. Git no PATH: C:/Users/Jeane/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/git/cmd. Logs em C:/Codex/2026-10-30/ace/work, fora do repositório. SDK/caches podem exigir require_escalated. Não executar commit, remotos ou build APK no implementador; principal revisa e gera APK ao final. Nenhum deploy necessário, pois backend permanece igual. Português do Brasil nas mensagens e documentação.

### Execução após revisão — 2026-10-31

Executados sequencialmente em `app`, com acesso aos caches do SDK:

```powershell
& 'C:/Users/Jeane/flutter/flutter/bin/cache/dart-sdk/bin/dart.exe' 'C:/Users/Jeane/flutter/flutter/bin/cache/flutter_tools.snapshot' test --no-pub test/ui/wave6_widgets_test.dart test/ui/nearby_view_test.dart test/ui/profile_test.dart test/ui/admin_ownership_test.dart *> 'C:/Codex/2026-10-30/ace/work/patrocinado-tests-review.log'
& 'C:/Users/Jeane/flutter/flutter/bin/cache/dart-sdk/bin/dart.exe' 'C:/Users/Jeane/flutter/flutter/bin/cache/flutter_tools.snapshot' analyze --no-pub *> 'C:/Codex/2026-10-30/ace/work/patrocinado-analyze-review.log'
```

Resultado: **79 testes passaram**; análise estática **sem ocorrências**, concluída em 22,7 segundos. A primeira rodada pós-revisão passou 78 testes e falhou apenas na asserção do cabeçalho após ele sair da área construída da lista; a asserção foi movida para antes da rolagem, e a rodada final acima passou integralmente.

Cobertura adicionada: slot com descoberta orgânica preservando sugestão e ordem/quantidade de tiles; troca de conta com resposta antiga anterior ao timeout e nova leitura pendente; erro real com seção sem espaço e recuperação serializada; falha de consulta do titular; três cards de um catálogo com 12 IDs distintos, navegação ao catálogo e retorno em tela pequena; pausa das atualizações da seção com `ActiveTab` inativo e releitura ao voltar. Continuam cobertos expiração, timeout incluindo consulta dos nomes, ausência em Amigos/perfil e estados existentes de GPS/erro/vazio.

Em `work/pa2`, `& 'C:/Users/Jeane/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/git/cmd/git.exe' diff --check` concluiu com código 0. Nenhum build, deploy ou commit foi executado pelo implementador. Limitação aceita na revisão: a reconstrução do loader quando o formato dos resultados muda permanece; a arquitetura de leitura não foi redesenhada.

## Entrega

- Três revisões concluídas; ajustes de catálogo compacto, filtros, polling e verificações aplicados.
- 79 testes relevantes passaram; análise estática limpa. APK 1.2.1+5 gerado e assinatura v2 compatível com a versão anterior.
- Backend e anúncios de produção permanecem inalterados. Remontagem do loader entre estados orgânicos é limitação tolerada de leitura, sem gravação.

## Suggested Review Order

- Descoberta apresenta destaques separados e preserva estados vazios.
  [nearby_view.dart:260](../../app/lib/ui/nearby/nearby_view.dart#L260)

- Seção compacta reaproveita catálogo, expiração e isolamento de sessão.
  [sponsored_view.dart:25](../../app/lib/ui/sponsored/sponsored_view.dart#L25)

- Perfil deixa de oferecer acesso ao catálogo comercial.
  [profile_view.dart:96](../../app/lib/ui/profile/profile_view.dart#L96)

- Titular atual acessa divulgação com indisponibilidade explícita.
  [owner_view.dart:130](../../app/lib/ui/owner/owner_view.dart#L130)

- Testes cobrem descoberta, catálogo, erro, sessão e permissões.
  [wave6_widgets_test.dart:164](../../app/test/ui/wave6_widgets_test.dart#L164)
