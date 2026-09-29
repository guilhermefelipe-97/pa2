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
