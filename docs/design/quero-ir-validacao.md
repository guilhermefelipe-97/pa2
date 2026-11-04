# Quero ir e Nova lista

Referência: `codex-clipboard-e28108e8-4d9a-4f13-ad7d-6930f09b2a41.png`.

- Título separado do contador de salvos, que usa fonte 12, peso normal e cinza.
- Nova lista é botão preenchido permanente, com texto em uma linha e largura limitada para telas pequenas.
- Cabeçalho reutiliza o GPS real do feed e mantém Decidir por mim pelo ícone de dado. A pedido da usuária, o acesso ao perfil fica na barra inferior, sem ícone duplicado no topo.
- Cards compactos com foto/fallback, local, bairro/categoria, nota disponível, marcador e menu. Data do salvamento disponível na dica do card. Removidos os painéis adicionais de coleção/organização para seguir a referência.
- Estrelas usam as notas reais da comunidade; indisponibilidade ou ausência de avaliações não vira nota fictícia. Puxar para atualizar também renova as notas.
- Todos os salvos e listas usam ícones Material. Título e Categoria sugerida são os campos do modal; categorias com ícone também aparecem ao renomear, adicionar locais e abrir listas pelo perfil.
- Os identificadores antigos das categorias são preservados no armazenamento. Listas antigas e cópias continuam válidas, sem migração destrutiva nem alterações nas Rules.
- Mantidos renomear, excluir, adicionar/remover, desfazer, visibilidade a seguidores, copiar lista, crédito da origem e contador de cópias. A lista selecionada é trazida à área visível dos chips.

Verificação: 109 testes aprovados, incluindo fluxos de cópia/compartilhamento, criação com categoria, fonte 2x em 320dp e prévias com fontes e fotos de teste. Nenhum dado fictício foi salvo em produção. Arquivos de prévia: `work/feed-preview/quero-ir-listas-validacao.png` e `nova-lista-modal-validacao.png`.
