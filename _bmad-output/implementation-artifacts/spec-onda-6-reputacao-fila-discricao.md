---
title: 'Onda 6 — Respostas, fila, modo silencioso e Destaque'
type: 'feature'
created: '2026-10-30'
status: 'done'
baseline_commit: '759f8417d7b4461069c146d67f5d8abaa17da028'
review_loop_iteration: 0
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

Entregar F24/F25/F29/F16 após a administração, preservando funcionalidades e dados existentes.

## Boundaries & Constraints

**Always:**
- **F24:** Meus estabelecimentos → Avaliações e respostas lista avaliações globais paginadas do próprio local. Titular atual responde uma vez, texto aparado de 1–1000 caracteres, identidade e hora do servidor. Resposta imutável, rotulada, auditada no mesmo batch; nunca compõe notas. Preservar autoria após revogação.
- **F16:** Você → Modo silencioso salva preferência privada para futuras avaliações/visitas, ajustável no formulário. silent ausente=false; histórico imutável. Atividade silenciosa não cria/ordena card nem revela fonte, foto, comentário ou selo no feed Amigos. Dados completos continuam identificados na ficha/perfil e nas agregações, Perto e decisão. Explicar esse alcance.
- **F29:** relato identificado de espera inteira 0–180min; proximidade150m no cliente, posição não enviada; titular não relata próprio local. Trava30min e auditoria atômicas. Ao vivo: últimos60min, último relato/pessoa, mediana/amostra/idade e expiração automática. Histórico:28dias, mesmo dia semanal/faixa2h em UTC−3, último relato/pessoa, mínimo3 pessoas, percentis25–75. Ler janela inteira paginada; pouca amostra é insuficiência, sem previsão inventada. Não alterar ranking.
- **F25:** página/componente Patrocinado separados dos amigos. Só slot vigente de local com titular. Testável em emulador, desligado em produção até F23/F26. Rules negam slots sem config/features.sponsorshipEnabled == true; flag/slots só graváveis fora do cliente. Sem pagamentos/ativação comercial.
- Autorização nas Rules; schemas exatos; horários do servidor; cooldown/retry idempotente; timeout recuperável e isolamento de sessão. Preservar administração.

**Ask First:** Ativar anúncios reais ou mudar parâmetros/privacidade.
**Never:** Anonimato, autoavaliação, misturar anúncio ao feed; implementar F23/F26.

## I/O & Edge-Case Matrix

| Caso | Resultado exigido |
|---|---|
| Titular falso/revogado/duplicidade | Resposta negada |
| Atividade silenciosa/legada | Sem vazamento no feed; legado público preservado |
| Relato vencido/pouca amostra | Sem sinal recente/previsão histórica |
| Flag ausente/false | Anúncios negados inclusive via SDK |
| Conta muda/ack perdido | Descartar estado antigo/reconciliar antes de repetir |

</frozen-after-approval>

## Code Map

- app/lib/domain/feed.dart, ui/core/load_visits.dart: apresentação e agregação hoje compartilham atividades; não filtrar dados globalmente.
- data/firebase/firestore_*repository.dart, domain/models/place_activity*.dart: parse, batches, cópias e defaults.
- domain/open_status.dart, ui/open/: padrão de relato/proximidade/trava.
- firebase/firestore.rules, firestore.indexes.json: estender auditoria e índices sem quebrar pares atuais.

## Tasks & Acceptance

- [x] app/lib/domain/, data/repositories/, data/firebase/: contratos/modelos de respostas, fila, privacidade e slots; cálculos puros com clock; persistência autorizada, paginação e retry.
- [x] app/lib/ui/owner/, ui/place/, ui/feed/, ui/privacy/, ui/queue/, ui/sponsored/, ui/review/, ui/visit/: entradas, formulários, rótulos e estados; atualizar main.dart, routing/ e perfil.
- [x] firebase/firestore.rules, firestore.indexes.json, firebase/tests/, app/test/: cobrir matriz, envios, renderização, batches máximos e regressões administrativas.
- [x] docs/: roteiro de teste e dependências de Destaque.
- [x] Principal: publicar após revisão e gerar APK assinado combinado1.2.0/build4.

**Acceptance:**
- Given titular atual, when responde a cliente não seguido, then resposta aparece identificada sem alterar eixos.
- Given contribuição silenciosa, when grava nota/tag/preço, then dados persistem sem expor atividade no feed.
- Given amostra suficiente, when ficha abre, then fila usa pessoas distintas e recorte aprovado.

## Spec Change Log

## Verification

app: flutter analyze; flutter test. firebase: npm run test:emulator. Todos verdes; APK assinado. Baseline capturado após commit administrativo; implementação sequencial. Deploy/build pelo principal, sem decisões reais em testes.

## Ambiente de execução

Flutter disponível via C:/Users/Jeane/flutter/flutter/bin/cache/dart-sdk/bin/dart.exe seguido de C:/Users/Jeane/flutter/flutter/bin/cache/flutter_tools.snapshot; flutter.bat pode aguardar lock. JDK21 em C:/Users/Jeane/.jdks/ms-21.0.11. Python em C:/Codex/2026-10-30/ace/work/uv-python/cpython-3.12.16-windows-x86_64-none/python.exe. Dependências instaladas; acesso ao SDK/caches fora da pasta pode exigir require_escalated. Logs/scripts temporários em C:/Codex/2026-10-30/ace/work, fora do repositório. Atualizar app/pubspec.yaml para1.2.0+4. Não delegar implementação em paralelo, não executar operações de produção e não gerar APK intermediário: principal faz deploy/build depois da revisão.


## Resultado da implementação local

- `flutter analyze --no-pub`: sem ocorrências (log `work/wave6-analyze-final.log`).
- Conjunto dirigido: 190 testes verdes (`work/wave6-directed-final.log`).
- `flutter test --no-pub`: 1104 testes verdes, 2m02 (`work/wave6-flutter-final.log`).
- `npm run test:emulator`: 332 testes verdes, script exit0 (`work/wave6-firebase-final.log`).
- Roteiro e fixture de emulador: `docs/onda-6.md`. Versão: `1.2.0+4`.
- Nenhum commit, deploy, operação remota, ativação comercial ou APK intermediário nesta etapa. Revisões, publicação e APK assinado ficam pendentes com o principal.

## Revisão final e entrega

- Três revisões independentes concluídas; achados tratados sem mudar o escopo aprovado.
- Fila: reconciliação antes da trava, valores recuperados reais, proteção contra operação tardia, novo relato após 30 minutos, atualização explícita, persistência do local descoberto e rejeição de coordenadas inválidas.
- Respostas: lista com carregamento sob demanda, revalidação do titular, limite de texto, atualização explícita e proteção contra leituras antigas.
- Privacidade: confirmação neutra, padrão silencioso aplicado automaticamente, paginação com empates e feed real com mais de 100 contribuições silenciosas.
- Destaque: cargas serializadas, prazo total e isolamento de documentos inválidos; produção permanece desligada.
- Histórico: testes distinguem os recortes UTC e UTC−3, inclusive virada de dia.
- Aplicativo: 1.105 testes passaram na execução completa, e o arquivo de telas corrigido passou em execução separada com 11 testes (total de 1.116 casos). Análise estática final sem ocorrências.
- Firebase: 333 testes passaram no emulador após os ajustes da revisão.
- APK combinado 1.2.0+4 verificado com aapt e apksigner. Regras e índices publicados no projeto naarea-natal; índices conferidos READY. Nenhum pedido real foi decidido durante os testes.

## Suggested Review Order

- Integração dos fluxos e repositórios aprovados.
  [main.dart:113](../../app/lib/main.dart#L113)

- Regras impõem identidade, atomicidade, imutabilidade e bloqueio comercial.
  [firestore.rules:685](../../firebase/firestore.rules#L685)

- Reconciliação preserva a identidade de envios tardios e permite novos relatos legítimos.
  [firestore_queue_repository.dart:59](../../app/lib/data/firebase/firestore_queue_repository.dart#L59)

- Fila oferece recuperação explícita e atualiza o local persistido.
  [queue_section.dart:74](../../app/lib/ui/queue/queue_section.dart#L74)

- Feed público pagina atividades silenciosas sem perder contribuições anteriores ou empates.
  [activity_queries.dart:9](../../app/lib/data/firebase/activity_queries.dart#L9)

- Respostas históricas preservam autoria, validação e atualização sem sobrescrita por leitura antiga.
  [reply_line.dart:8](../../app/lib/ui/owner/reply_line.dart#L8)

- Patrocinado limita a duração total das cargas e impede sobreposição.
  [sponsored_view.dart:54](../../app/lib/ui/sponsored/sponsored_view.dart#L54)

- Cálculos de fila respeitam janela, pessoas distintas e horário local.
  [queue_status.dart:62](../../app/lib/domain/queue_status.dart#L62)

- Testes exercitam persistência, recuperação e paginação.
  [wave6_repositories_test.dart:18](../../app/test/data/wave6_repositories_test.dart#L18)

- Telas verificam privacidade, respostas, recuperação e troca de sessão.
  [wave6_widgets_test.dart:134](../../app/test/ui/wave6_widgets_test.dart#L134)

- Roteiro documenta os fluxos de validação e os limites comerciais aprovados.
  [onda-6.md:1](../../docs/onda-6.md#L1)
