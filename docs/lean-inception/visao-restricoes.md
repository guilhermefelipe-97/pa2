# NaÁrea — Visão do Produto e Restrições

> Fase 1 (Semanas 1–3) — Lean Inception + BMAD. Fonte: sessão de brainstorming em `_bmad-output/brainstorming/brainstorm-naarea-2026-08-24/.memlog.md`.

## Visão do Produto

**Para**: pessoas que desejam encontrar restaurantes, bares, pontos turísticos, serviços e experiências de forma rápida e confiável, especialmente quando estão em cidades novas ou não conhecem bem a região.

**Cujo problema é**: a dificuldade de encontrar locais de qualidade, obter avaliações realmente confiáveis e descobrir recomendações alinhadas aos seus gostos e interesses.

**O NaÁrea** é um aplicativo mobile de recomendações e interação social.

**Que**: facilita a descoberta de locais, produtos e serviços por meio de filtros inteligentes, avaliações de usuários reais, localização, preferências pessoais e recomendações personalizadas.

**Diferentemente de**: plataformas como Google Maps, Instagram e outros aplicativos de busca, que focam principalmente em localização ou conteúdo genérico.

**O nosso produto**: combina busca, avaliações, fotos, vídeos e localização com recursos de rede social, permitindo que os usuários sigam pessoas com gostos semelhantes, descubram recomendações de amigos e recebam sugestões personalizadas. Assim, ao visitar uma nova cidade ou procurar algo diferente, o usuário pode confiar nas experiências de pessoas que compartilham interesses parecidos, tornando a escolha mais fácil, segura e relevante.

## Produto É – Não é – Faz – Não faz

### É

- Rede social de gosto compartilhado — segue amigos conhecidos, mas também descobre gente nova com gosto parecido.
- Rede social moderna e divertida.
- Momentos de uso: chegar em cidade nova sem conhecer nada, decidir onde sair no sábado com a galera, ou vontade geral de conhecer locais novos.

### Não é

- Um diretório neutro tipo Google Maps, onde todo lugar recebe o mesmo tratamento.
- Um aplicativo de anúncio — anúncio é apenas uma parte, não a essência.
- Um check-in raso tipo Foursquare/Swarm — tem interação, avaliações, informações e geolocalização juntos, não só marcar presença.
- Sério/profissional tipo LinkedIn, nem chato/reclamão tipo Nextdoor — o tom é descontraído e divertido.
- Um app de reserva/pedido/transação tipo OpenTable ou iFood — só indica o local, a transação acontece fora do app.

### Faz

- Monetiza via anúncio de estabelecimento patrocinado (Destaque).
- Usuário tem perfil salvo com locais visitados, comentários, fotos e filtros.
- Chat entre usuários (comentários, não só nota).
- Permite compartilhar localização.
- Permite postagem de fotos e vídeos.
- Habilita níveis para consumidores que avaliam.
- Coloca os estabelecimentos mais bem avaliados em destaque.
- Busca em outros bairros e cidades, não só onde o usuário está.
- Modo viagem: GPS detecta cidade nova e troca o feed para moradores locais / amigos que já visitaram.
- Mostra no feed do usuário estabelecimentos conforme as preferências.

### Não faz

- Não permite que o dono do estabelecimento avalie o próprio negócio.
- Feed não permite conteúdo aleatório.
- Não permite que um mesmo usuário reavalie o mesmo estabelecimento antes de um período mínimo de tempo (ex: 1 mês desde a última avaliação).
- Não permite avaliação anônima — nome/foto sempre atrelado, pra manter confiança.

## Esclarecendo o Objetivo

O NaÁrea existe para resolver a falta de confiança e relevância na descoberta de lugares: diferente de diretórios neutros (Google Maps), curadoria genérica (Instagram) ou check-in raso (Foursquare/Swarm), ele usa a rede de afinidade e conhecidos do usuário como filtro de qualidade. As restrições acima (Não É / Não Faz) existem para proteger esse princípio central — autenticidade da avaliação acima de monetização ou engajamento vazio — e servem como guardrails para a IA na geração de requisitos e arquitetura nas próximas fases: nenhuma funcionalidade proposta deve permitir avaliação duplicada em curto prazo, avaliação do próprio dono, ou identidade anônima.
