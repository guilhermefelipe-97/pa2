---
title: 'F12 — Listas nomeadas dentro do "Quero ir"'
type: 'feature'
created: '2026-10-05'
status: 'done'
baseline_commit: '474a3d445985e6b139d35e0cc1a0786bfcfe8d70'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-f11-quero-ir.md'
  - '{project-root}/docs/lean-inception/jornada-bianca.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Passo 4 da jornada da Bianca ("Isso é 'Sábado com as meninas'"): sem organização, o "Quero ir" vira uma pilha e ela abandona.

**Approach:** Listas privadas com nome e emoji opcional (`users/{uid}/lists/{listId}`, membros num array `placeIds`). Na aba "Quero ir", chips no topo filtram por lista ("Todos" = salvos). Adicionar a uma lista é feito por um bottom sheet com as listas marcáveis e "Nova lista", aberto pelo "Adicionar a lista" da SnackBar de salvar e pelo menu de cada card salvo. Lista é subconjunto do "Quero ir": adicionar a uma lista salva o local; remover do "Quero ir" o tira de todas as listas.

## Boundaries & Constraints

**Always:** Privado (só o dono lê/escreve). Nome aparado, 1–40 caracteres, único por usuário sem diferenciar caixa/acento (validado no app). Emoji opcional de um conjunto fixo de 12. No máximo 30 listas e 200 locais por lista (Rules garantem os tamanhos). `createdAt` imutável; `updatedAt == request.time` em toda escrita. Remover do "Quero ir" + tirar das listas acontece num único batch. Otimista com reversão, como o F11. Excluir lista pede confirmação e não remove os locais do "Quero ir".

**Ask First:** Listas públicas ou compartilhadas; ordenar locais dentro da lista manualmente.

**Never:** Copiar lista de outra pessoa (F13); notas por local; listas colaborativas.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Criar lista | "  Sábado com as meninas " + 🎉 | lista criada aparada, aparece como chip e já marcada no sheet | vazio/41+ → botão desabilitado com contador |
| Nome repetido | "sabado com as meninas" já existe | bloqueado: "Você já tem uma lista com esse nome" | N/A |
| Adicionar | sheet: marca 2 listas em local não salvo | local salvo + nas 2 listas | falha → reverte e "Não foi possível salvar" |
| Desmarcar | desmarca lista no sheet | sai só daquela lista, continua no "Quero ir" | idem |
| Remover do Quero ir | local em 2 listas | some de tudo num batch; SnackBar "Removido de Quero ir e de 2 listas" + Desfazer restaura tudo | idem |
| Filtrar | chip "Sábado…" | só os locais da lista, mais recente primeiro; vazio → "Nada nesta lista ainda" | N/A |
| Renomear/excluir | menu do chip ativo | renomeia com as mesmas validações; excluir confirma e volta para "Todos" | idem |
| Limites | 31ª lista ou 201º local | "Nova lista" desabilitado com aviso / marcar desabilitado | Rules negam via SDK |
| Forja via SDK | outro uid, chave extra, nome 0/41, `createdAt` alterado, `placeIds` não-lista | negado | Rules |

</frozen-after-approval>

## Code Map

- `firebase/firestore.rules:46-57` -- padrão de `saved/{placeId}` (F11) a seguir em `lists/{listId}` (create/update/delete do dono, `hasOnly(['name','emoji','placeIds','createdAt','updatedAt'])`)
- `app/lib/data/repositories/saved_repository.dart` + `firestore_saved_repository.dart` -- estilo; criar `ListsRepository` + implementação Firestore (listar, criar, renomear, excluir, setMembership com `arrayUnion/arrayRemove`, batch "remover de tudo")
- `app/lib/ui/saved/saved_places_store.dart` -- fonte única dos salvos (otimista, serializa por id, Desfazer restaura `savedAt`); estender ou compor com um `ListsStore` para manter salvos e listas coerentes
- `app/lib/ui/core/save_button.dart` -- SnackBar de salvar ganha ação "Adicionar a lista"
- `app/lib/ui/saved/saved_view.dart` + `saved_view_model.dart` -- aba; adicionar chips, filtro e menu do card
- `app/lib/main.dart` -- providers
- `app/test/support/{fakes,app_harness}.dart` -- fakes e harness de widget

## Tasks & Acceptance

**Execution:**
- [x] `firebase/tests/**` + `firebase/firestore.rules` -- testes vermelhos de `lists` (dono CRUD; terceiro nega; chaves exatas; nome string 1–40 aparado; emoji null ou string ≤ 8; `placeIds` lista ≤ 200; `createdAt` imutável; `updatedAt == request.time`), depois Rules
- [x] `app/lib/domain/models/place_list.dart` + testes -- modelo, normalização/validação de nome, conjunto de emojis
- [x] `app/lib/data/**` + testes -- `ListsRepository` e implementação; batch de remoção total
- [x] `app/lib/ui/lists/**` + testes -- `ListsStore`, bottom sheet "Adicionar a lista" (checkbox por lista, "Nova lista" inline com emoji), diálogo de renomear, confirmação de excluir
- [x] `app/lib/ui/saved/**`, `app/lib/ui/core/save_button.dart` + testes -- chips com contagem, filtro, menu do card ("Adicionar a lista", "Remover do Quero ir"), SnackBar com "Adicionar a lista"

**Acceptance Criteria:**
- Given Bianca salvou um local no feed, when toca "Adicionar a lista" na SnackBar e cria "Sábado com as meninas", then o chip aparece na aba e filtrar por ele mostra o local.
- Given app reaberto, when vai à aba, then as listas e seus locais continuam lá.

## Verification

**Commands:**
- `cd app && flutter analyze` -- expected: No issues found
- `cd app && flutter test` -- expected: todos passam
- `cd firebase && export JAVA_HOME="/c/Program Files/Java/jdk-24" PATH="$JAVA_HOME/bin:$PATH" && firebase emulators:exec --only firestore "npm test"` -- expected: todos passam

## Spec Change Log

- Revisão 1 (patches, sem loopback): a invariante "lista ⊂ Quero ir" passou a ser garantida também por reconciliação no `ListsStore` (membros não salvos saem com `arrayRemove`), além do batch. Evita membros-fantasma por corridas, listas apagadas em outro aparelho e remoções offline. KEEP: otimismo com reversão, fila por lista, batch único na remoção.

## Suggested Review Order

**Integridade**

- Ponto de entrada: listas privadas, chaves exatas, emoji do conjunto fixo, ≤200 locais.
  [`firestore.rules:63`](../../firebase/firestore.rules#L63)

**Coerência listas ↔ Quero ir**

- Reconciliação: membro não salvo e sem escrita pendente sai da lista.
  [`lists_store.dart:279`](../../app/lib/ui/lists/lists_store.dart#L279)

- Remover do Quero ir: batch único; fallback e retry sem listas ausentes.
  [`lists_store.dart:586`](../../app/lib/ui/lists/lists_store.dart#L586)

- Marcação otimista em fila por lista; desfaz salvamento que ela causou.
  [`lists_store.dart:406`](../../app/lib/ui/lists/lists_store.dart#L406)

- Batch: apaga o salvo e faz `arrayRemove` nas listas.
  [`firestore_lists_repository.dart:112`](../../app/lib/data/firebase/firestore_lists_repository.dart#L112)

**UI**

- Sheet "Adicionar a lista" com criação inline.
  [`add_to_list_sheet.dart:25`](../../app/lib/ui/lists/add_to_list_sheet.dart#L25)

- Chips com contagem visível, banner de erro das listas.
  [`saved_view.dart:66`](../../app/lib/ui/saved/saved_view.dart#L66)

**Periféricos**

- Nome único sem caixa/acento e com espaços colapsados.
  [`place_list.dart:60`](../../app/lib/domain/models/place_list.dart#L60)
