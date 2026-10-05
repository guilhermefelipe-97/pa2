# Deferred Work

- source_spec: none
  summary: F11 "Quero ir" — salvar local em 1 toque, sem avaliar, privado por padrão (Onda 1 do sequenciador).
  evidence: Dividido da Onda 1 por escopo (decisão [S] em 2026-09-28); entregável independente que depende apenas de Place e do feed já prontos no spec da fundação (F01+F02+F05).

- source_spec: `_bmad-output/implementation-artifacts/spec-onda-1-fundacao-avaliacao-feed.md`
  summary: Verificar o índice composto reviews(authorId ASC, createdAt DESC) contra um projeto Firebase real (smoke test pós-deploy).
  evidence: O Firestore Emulator não exige índices compostos; o teste de Rules passa com ou sem o índice.

- source_spec: `_bmad-output/implementation-artifacts/spec-onda-1-fundacao-avaliacao-feed.md`
  summary: CI (GitHub Actions) rodando flutter analyze, flutter test e a suíte de Rules no emulator.
  evidence: Sem CI, os guardrails de integridade só são verificados quando alguém roda o emulator manualmente.

- source_spec: `_bmad-output/implementation-artifacts/spec-onda-1-fundacao-avaliacao-feed.md`
  summary: Paginação / "carregar mais" no feed além das 100 avaliações mais recentes por lote.
  evidence: fetchReviewsByAuthors limita cada lote a 100 docs; avaliações antigas de amigos ativos somem sem indicação.

- source_spec: `_bmad-output/implementation-artifacts/spec-onda-1-fundacao-avaliacao-feed.md`
  summary: Busca de pessoas por qualquer parte do nome e sem acento (campo de busca normalizado/tokenizado).
  evidence: Hoje só casa prefixo do nome completo e sem folding de acento — "Silva" não acha "Bianca Silva".

- source_spec: `_bmad-output/implementation-artifacts/spec-onda-1-fundacao-avaliacao-feed.md`
  summary: Tela "Minhas avaliações" para o usuário conferir o que publicou.
  evidence: O feed exclui o próprio uid por desenho (F05), então o autor não vê a avaliação que acabou de enviar.

- source_spec: `_bmad-output/implementation-artifacts/spec-feed-rico-fotos-comentario-visual.md`
  summary: Empacotar as fontes Fredoka/Nunito como assets (sem download em runtime) e registrar as licenças OFL.
  evidence: google_fonts baixa as fontes do Google no primeiro uso — sem internet cai na fonte do sistema e há requisição a terceiro (LGPD).

- source_spec: `_bmad-output/implementation-artifacts/spec-feed-rico-fotos-comentario-visual.md`
  summary: Atualizar periodicamente o tempo relativo ("agora", "há 5 min") e ao voltar o app para primeiro plano.
  evidence: `now` é capturado por build; o texto congela até outro rebuild.

- source_spec: none
  summary: F12 Listas nomeadas — organizar locais salvos em listas privadas (Onda 2).
  evidence: Dividido em 2026-10-05 (decisão [S]); sequência acordada G0 → F11 → F12 → F06 → F14 → F10, um spec por cartão.

- source_spec: none
  summary: F06 Card com fonte de confiança — reforçar quem foi (nome, "você segue", eixos por pessoa, visitas), sem foto de perfil por upload (Onda 2).
  evidence: Dividido em 2026-10-05 (decisão [S]); entregável independente sobre o feed existente.

- source_spec: none
  summary: F14 Avaliação mínima válida — eixos opcionais com mínimo de 1 eixo preenchido (Onda 2).
  evidence: Dividido em 2026-10-05 (decisão [S]); relaxa regra da Onda 1 (3 eixos obrigatórios) nas Rules e na UI.

- source_spec: none
  summary: F10 "Estou na rua agora" — locais num raio de 300m usando lat/lng/geohash do catálogo OSM (G0), com opção de ampliar; "aberto agora" fica para F20 (Onda 2).
  evidence: Dividido em 2026-10-05 (decisão [S]); depende do G0 (catálogo OSM com coordenadas).

- source_spec: `_bmad-output/implementation-artifacts/spec-g0-catalogo-osm.md`
  summary: Busca de locais por bairro no seletor (chip ou filtro de bairro), perdida ao trocar o filtro local pela busca por tokens do nome.
  evidence: O seletor antigo filtrava por nome ou bairro ("ponta negra"); a busca por `searchTokens` só indexa o nome.

- source_spec: `_bmad-output/implementation-artifacts/spec-g0-catalogo-osm.md`
  summary: Smoke test pós-deploy do índice places(searchTokens CONTAINS, nameLower ASC) em produção.
  evidence: Nem o emulator nem o FakeFirebaseFirestore exigem índice composto; a falta só aparece no projeto real.

- source_spec: `_bmad-output/implementation-artifacts/spec-g0-catalogo-osm.md`
  summary: Marcar como inativos (e manter buscáveis) os docs `osm-*` que saírem do OSM no futuro, em vez de só listá-los no log.
  evidence: O seed nunca apaga nem reescreve docs fora da fonte; eles podem ter avaliações e ficariam sem tokens atualizados.

- source_spec: none
  summary: G1 Foto do local enviada por quem avaliou — opcional, comprimida no app (~80 KB) e gravada no Firestore (sem Storage/Blaze), exibida no card e no detalhe com crédito "foto de <nome>".
  evidence: Decidido em 2026-10-05: sem cartão não há API de fotos de locais; OSM não tem fotos. Sequência: G0 → F11 → F12 → G1 → F06 → F14 → F10.

- source_spec: `_bmad-output/implementation-artifacts/spec-g1-foto-de-quem-avaliou.md`
  summary: Excluir/denunciar foto de avaliação (autor apaga a própria foto; denúncia por terceiros) e fluxo de pedido de exclusão (LGPD).
  evidence: `reviewPhotos` é imutável (update/delete negados) e legível por qualquer usuário logado; foto errada ou com rosto de terceiros não tem saída. Ficou como Ask First no G1.

- source_spec: `_bmad-output/implementation-artifacts/spec-g1-foto-de-quem-avaliou.md`
  summary: Documentar capacidade das fotos no Firestore (Spark: 1 GiB, 50 mil leituras/dia) com alerta de cota e plano de migração para Storage quando houver Blaze.
  evidence: Cada foto ~≤150 KB e 1 leitura por sessão por usuário; algumas milhares de fotos esgotam o armazenamento gratuito.
