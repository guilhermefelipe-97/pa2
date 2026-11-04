# Filtros alimentares no feed

Pedido: mover as preferências alimentares para o canto superior direito do feed e melhorar a apresentação da seleção de tags.

- Ícone de ajustes no cabeçalho de Amigos; indicador com o número de tags aplicadas e chips abaixo do cabeçalho para reabrir a edição.
- Painel com Caseiro, Vegetariano, Vegano, Low-carb e Integral, ícones, descrições curtas, estado selecionado e ações Limpar/Cancelar/Aplicar filtros.
- Limpar altera o rascunho; Cancelar/Fechar preserva a preferência salva. Aplicar persiste na conta e atualiza o feed. Falhas mantêm o rascunho e exibem o erro junto aos botões.
- Preferência removida de Configurações. A rota anterior `/perfil-alimentar` permanece compatível e utiliza o mesmo painel redesenhado.
- Regras de negócio preservadas: tags confirmadas por três autores distintos, combinação AND e filtro apenas do feed de Amigos. Explicação disponível em Como funcionam as tags.
- Leitura e salvamento têm prazo de confirmação para liberar a interface quando a rede não responde. Identidade e respostas antigas continuam protegidas pelo controle de sessão.
- O feed mostra carregamento durante a troca de filtros, evitando exibir um falso resultado vazio enquanto a consulta ainda está em andamento.

Validação: testes da onda 5 e navegação, novos cenários de seleção/persistência/cancelamento, falha com nova tentativa, timeout e fonte 2x em 320dp. Análise sem ocorrências. Logs: `work/feed-filters-final-tests.log` (regressão) e `work/feed-filters-ready-tests.log` (quatro cenários finais revalidados), na pasta principal do workspace.

Prévias Flutter com dados de teste: `work/feed-preview/feed-filtros-painel-validacao.png` e `feed-tags-aplicadas-validacao.png`. Nenhuma alteração de Rules ou publicação em produção foi necessária nesta etapa.

## Validação e continuidade

A usuária aprovou a tela dos filtros e autorizou corrigir as duas pendências da onda 4: histórico completo dos candidatos no Decidir por mim e comprovação da cópia no contador. O painel aprovado foi preservado. A implementação e a conferência das correções estão registradas em `docs/design/onda4-correcao-historico-copias.md`.
