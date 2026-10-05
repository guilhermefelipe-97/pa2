import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/models/place_list.dart';
import 'package:naarea/ui/lists/lists_store.dart';
import 'package:naarea/ui/saved/saved_places_store.dart';

import '../support/fakes.dart';

class _Setup {
  _Setup(this.auth, this.savedRepo, this.listsRepo, this.saved, this.lists);
  final FakeAuthRepository auth;
  final FakeSavedRepository savedRepo;
  final FakeListsRepository listsRepo;
  final SavedPlacesStore saved;
  final ListsStore lists;

  void dispose() {
    lists.dispose();
    saved.dispose();
  }
}

Future<_Setup> _make({
  void Function(FakeSavedRepository s, FakeListsRepository l)? seed,
  Duration waitTimeout = const Duration(seconds: 10),
}) async {
  final auth = FakeAuthRepository(uid: 'me');
  final savedRepo = FakeSavedRepository();
  final listsRepo = FakeListsRepository(saved: savedRepo);
  seed?.call(savedRepo, listsRepo);
  final saved = SavedPlacesStore(
    authRepository: auth,
    savedRepository: savedRepo,
    waitTimeout: waitTimeout,
  );
  final lists = ListsStore(
    authRepository: auth,
    listsRepository: listsRepo,
    savedStore: saved,
    waitTimeout: waitTimeout,
  );
  await pumpEventQueue();
  return _Setup(auth, savedRepo, listsRepo, saved, lists);
}

final _t = DateTime.utc(2026, 9, 20);

void main() {
  test('carrega as listas do usuário na ordem de criação', () async {
    final s = await _make(
      seed: (_, l) => l
        ..seed('me', 'b', 'B', createdAt: DateTime.utc(2026, 9, 2))
        ..seed('me', 'a', 'A', createdAt: DateTime.utc(2026, 9, 1))
        ..seed('outra', 'x', 'X'),
    );
    addTearDown(s.dispose);
    expect(s.lists.isReady, isTrue);
    expect(s.lists.lists.map((l) => l.id), ['a', 'b']);
  });

  test(
    'criar com local não salvo: nome aparado, local salvo e na lista',
    () async {
      final s = await _make();
      addTearDown(s.dispose);

      final created = s.lists.create(
        '  Sábado com as meninas ',
        emoji: '🎉',
        withPlace: 'mangai',
      )!;
      // Otimista: já aparece, já marcada, e o local já está salvo.
      final shown = s.lists.listById(created.id)!;
      expect(shown.name, 'Sábado com as meninas');
      expect(shown.emoji, '🎉');
      expect(shown.contains('mangai'), isTrue);
      expect(s.saved.isSaved('mangai'), isTrue);

      expect(await created.done, isTrue);
      final stored = s.listsRepo.get('me', created.id)!;
      expect(stored.name, 'Sábado com as meninas');
      expect(stored.placeIds, ['mangai']);
      expect(s.savedRepo.byUser['me']!.containsKey('mangai'), isTrue);
      // O salvo sai antes da lista.
      expect(s.savedRepo.writes, ['save:mangai']);
      expect(s.listsRepo.writes, ['create:${created.id}']);
    },
  );

  test('nome repetido (caixa/acento) e inválido são bloqueados', () async {
    final s = await _make(
      seed: (_, l) => l.seed('me', 'a', 'Sábado com as meninas'),
    );
    addTearDown(s.dispose);
    expect(s.lists.isNameTaken('sabado com as MENINAS'), isTrue);
    expect(
      s.lists.isNameTaken('sabado com as meninas', exceptId: 'a'),
      isFalse,
    );
    expect(s.lists.create('sabado com as meninas'), isNull);
    expect(s.lists.create('   '), isNull);
    expect(s.lists.create('a' * 41), isNull);
    expect(s.lists.create('Ok', emoji: 'x'), isNull);
    expect(s.listsRepo.writes, isEmpty);
  });

  test('limite de 30 listas', () async {
    final s = await _make(
      seed: (_, l) {
        for (var i = 0; i < PlaceList.maxLists; i++) {
          l.seed('me', 'l$i', 'Lista $i');
        }
      },
    );
    addTearDown(s.dispose);
    expect(s.lists.canCreate, isFalse);
    expect(s.lists.create('Mais uma'), isNull);
  });

  test('marcar 2 listas num local não salvo: salvo + nas 2', () async {
    final s = await _make(
      seed: (_, l) => l
        ..seed('me', 'a', 'A')
        ..seed('me', 'b', 'B'),
    );
    addTearDown(s.dispose);

    final r1 = s.lists.setMembership('a', 'mangai', true);
    final r2 = s.lists.setMembership('b', 'mangai', true);
    expect(s.saved.isSaved('mangai'), isTrue);
    expect(s.lists.listsContaining('mangai').map((l) => l.id), ['a', 'b']);
    expect(await r1, isTrue);
    expect(await r2, isTrue);
    expect(s.listsRepo.get('me', 'a')!.placeIds, ['mangai']);
    expect(s.listsRepo.get('me', 'b')!.placeIds, ['mangai']);
    expect(s.savedRepo.writes, ['save:mangai']);
  });

  test('falha ao marcar: reverte, e desfaz o salvamento que causou', () async {
    final s = await _make(seed: (_, l) => l.seed('me', 'a', 'A'));
    addTearDown(s.dispose);
    s.listsRepo.failWhen = (op) => op.startsWith('add:');

    final done = s.lists.setMembership('a', 'mangai', true);
    expect(s.lists.listById('a')!.contains('mangai'), isTrue);
    expect(await done, isFalse);
    expect(s.lists.listById('a')!.contains('mangai'), isFalse);
    await pumpEventQueue();
    expect(s.saved.isSaved('mangai'), isFalse);
  });

  test('salvar falhou: a lista não é gravada e o membro reverte', () async {
    final s = await _make(seed: (_, l) => l.seed('me', 'a', 'A'));
    addTearDown(s.dispose);
    s.savedRepo.writeError = Exception('network');

    expect(await s.lists.setMembership('a', 'mangai', true), isFalse);
    expect(s.lists.listById('a')!.contains('mangai'), isFalse);
    expect(s.listsRepo.writes, isEmpty);
  });

  test('desmarcar tira só daquela lista; continua no Quero ir', () async {
    final s = await _make(
      seed: (sv, l) {
        sv.seed('me', 'mangai', _t);
        l
          ..seed('me', 'a', 'A', placeIds: ['mangai'])
          ..seed('me', 'b', 'B', placeIds: ['mangai']);
      },
    );
    addTearDown(s.dispose);

    expect(await s.lists.setMembership('a', 'mangai', false), isTrue);
    expect(s.lists.listsContaining('mangai').map((l) => l.id), ['b']);
    expect(s.saved.isSaved('mangai'), isTrue);
    expect(s.savedRepo.writes, isEmpty);
  });

  test('lista com 200 locais não aceita mais', () async {
    final s = await _make(
      seed: (sv, l) {
        // Salvos: membro não salvo seria limpo pela reconciliação.
        for (var i = 0; i < 200; i++) {
          sv.seed('me', 'p$i', _t);
        }
        l.seed('me', 'a', 'A', placeIds: [for (var i = 0; i < 200; i++) 'p$i']);
      },
    );
    addTearDown(s.dispose);
    expect(s.lists.listById('a')!.isFull, isTrue);
    expect(await s.lists.setMembership('a', 'mangai', true), isFalse);
    expect(s.listsRepo.writes, isEmpty);
  });

  test(
    'remover do Quero ir: um batch tira de tudo; Desfazer restaura tudo',
    () async {
      final s = await _make(
        seed: (sv, l) {
          sv.seed('me', 'mangai', _t);
          l
            ..seed('me', 'a', 'A', placeIds: ['mangai'])
            ..seed('me', 'b', 'B', placeIds: ['mangai'])
            ..seed('me', 'c', 'C');
        },
      );
      addTearDown(s.dispose);

      final from = [for (final l in s.lists.listsContaining('mangai')) l.id];
      expect(from, ['a', 'b']);
      expect(await s.saved.setSaved('mangai', false), isTrue);
      // Nada de remove avulso: só o batch.
      expect(s.savedRepo.writes, isEmpty);
      expect(s.listsRepo.writes, ['removeEverywhere:mangai:a,b']);
      expect(s.savedRepo.byUser['me']!.containsKey('mangai'), isFalse);
      expect(s.listsRepo.get('me', 'a')!.placeIds, isEmpty);
      expect(s.lists.listsContaining('mangai'), isEmpty);
      expect(s.lists.countOf(s.lists.listById('a')!), 0);

      expect(await s.lists.restore('mangai', from), RestoreResult.ok);
      expect(s.saved.isSaved('mangai'), isTrue);
      expect(s.listsRepo.get('me', 'a')!.placeIds, ['mangai']);
      expect(s.listsRepo.get('me', 'b')!.placeIds, ['mangai']);
      expect(s.listsRepo.get('me', 'c')!.placeIds, isEmpty);
    },
  );

  test('batch falhou: volta ao Quero ir e às listas', () async {
    final s = await _make(
      seed: (sv, l) {
        sv.seed('me', 'mangai', _t);
        l.seed('me', 'a', 'A', placeIds: ['mangai']);
      },
    );
    addTearDown(s.dispose);
    s.listsRepo.writeError = Exception('network');

    expect(await s.saved.setSaved('mangai', false), isFalse);
    expect(s.saved.isSaved('mangai'), isTrue);
    expect(s.lists.listsContaining('mangai').map((l) => l.id), ['a']);
    expect(s.savedRepo.byUser['me']!.containsKey('mangai'), isTrue);
  });

  test('contagem só considera locais salvos', () async {
    final s = await _make(
      seed: (sv, l) {
        sv.seed('me', 'a1', _t);
        l.seed('me', 'a', 'A', placeIds: ['a1', 'fora']);
      },
    );
    addTearDown(s.dispose);
    expect(s.lists.countOf(s.lists.listById('a')!), 1);
  });

  test('renomear: otimista, valida e reverte em falha', () async {
    final s = await _make(
      seed: (_, l) => l
        ..seed('me', 'a', 'A')
        ..seed('me', 'b', 'Bares'),
    );
    addTearDown(s.dispose);

    expect(await s.lists.rename('a', 'bares'), isFalse);
    expect(await s.lists.rename('a', ''), isFalse);
    expect(s.listsRepo.writes, isEmpty);

    expect(await s.lists.rename('a', '  Almoço ', emoji: '🍕'), isTrue);
    expect(s.lists.listById('a')!.label, '🍕 Almoço');
    expect(s.listsRepo.get('me', 'a')!.name, 'Almoço');

    s.listsRepo.writeGate = Completer();
    s.listsRepo.writeError = Exception('x');
    final done = s.lists.rename('a', 'Outro');
    expect(s.lists.listById('a')!.name, 'Outro');
    s.listsRepo.writeGate!.complete();
    expect(await done, isFalse);
    expect(s.lists.listById('a')!.name, 'Almoço');
  });

  test('excluir lista não remove os locais do Quero ir', () async {
    final s = await _make(
      seed: (sv, l) {
        sv.seed('me', 'mangai', _t);
        l.seed('me', 'a', 'A', placeIds: ['mangai']);
      },
    );
    addTearDown(s.dispose);

    final done = s.lists.delete('a');
    expect(s.lists.listById('a'), isNull);
    expect(await done, isTrue);
    expect(s.listsRepo.get('me', 'a'), isNull);
    expect(s.saved.isSaved('mangai'), isTrue);
    expect(s.savedRepo.byUser['me']!.containsKey('mangai'), isTrue);
  });

  test('excluir falhou: a lista volta', () async {
    final s = await _make(seed: (_, l) => l.seed('me', 'a', 'A'));
    addTearDown(s.dispose);
    s.listsRepo.writeError = Exception('x');
    expect(await s.lists.delete('a'), isFalse);
    expect(s.lists.listById('a'), isNotNull);
  });

  test('criar falhou: a lista some', () async {
    final s = await _make();
    addTearDown(s.dispose);
    s.listsRepo.writeError = Exception('x');
    final created = s.lists.create('Nova')!;
    expect(s.lists.lists, hasLength(1));
    expect(await created.done, isFalse);
    expect(s.lists.lists, isEmpty);
  });

  test(
    'toques rápidos na mesma lista: escritas em ordem, estado final = último',
    () async {
      final s = await _make(
        seed: (sv, l) {
          sv.seed('me', 'mangai', _t);
          l.seed('me', 'a', 'A');
        },
      );
      addTearDown(s.dispose);
      s.listsRepo.writeGate = Completer();
      final f1 = s.lists.setMembership('a', 'mangai', true);
      final f2 = s.lists.setMembership('a', 'mangai', false);
      final f3 = s.lists.setMembership('a', 'mangai', true);
      expect(s.lists.listById('a')!.contains('mangai'), isTrue);
      s.listsRepo.writeGate!.complete();
      await Future.wait([f1, f2, f3]);
      expect(s.lists.listById('a')!.contains('mangai'), isTrue);
      expect(s.listsRepo.get('me', 'a')!.placeIds, ['mangai']);
    },
  );

  test('app reaberto: listas e membros continuam lá', () async {
    final first = await _make();
    final created = first.lists.create('Sábado', withPlace: 'mangai')!;
    await created.done;
    first.dispose();

    final auth = FakeAuthRepository(uid: 'me');
    final saved = SavedPlacesStore(
      authRepository: auth,
      savedRepository: first.savedRepo,
    );
    final lists = ListsStore(
      authRepository: auth,
      listsRepository: first.listsRepo,
      savedStore: saved,
    );
    addTearDown(() {
      lists.dispose();
      saved.dispose();
    });
    await pumpEventQueue();
    final l = lists.lists.single;
    expect(l.name, 'Sábado');
    expect(lists.countOf(l), 1);
  });

  test('troca de usuário limpa e recarrega', () async {
    final s = await _make(
      seed: (_, l) => l
        ..seed('me', 'a', 'A')
        ..seed('outra', 'x', 'X'),
    );
    addTearDown(s.dispose);
    s.auth.restoreSession('outra');
    await pumpEventQueue();
    expect(s.lists.lists.map((l) => l.id), ['x']);
  });

  test('erro ao carregar: hasError e reload tenta de novo', () async {
    final auth = FakeAuthRepository(uid: 'me');
    final savedRepo = FakeSavedRepository();
    final listsRepo = FakeListsRepository(saved: savedRepo)
      ..listError = Exception('network');
    final saved = SavedPlacesStore(
      authRepository: auth,
      savedRepository: savedRepo,
    );
    final lists = ListsStore(
      authRepository: auth,
      listsRepository: listsRepo,
      savedStore: saved,
    );
    addTearDown(() {
      lists.dispose();
      saved.dispose();
    });
    await pumpEventQueue();
    expect(lists.hasError, isTrue);
    listsRepo.listError = null;
    await lists.reload();
    expect(lists.isReady, isTrue);
  });

  test('dispose devolve o remover padrão ao SavedPlacesStore', () async {
    final s = await _make();
    expect(s.saved.remover, isNotNull);
    s.lists.dispose();
    expect(s.saved.remover, isNull);
    s.saved.dispose();
  });

  group('revisão: reconciliação (lista ⊂ Quero ir)', () {
    test('membro-fantasma (não salvo) é limpo no carregamento', () async {
      final s = await _make(
        seed: (sv, l) {
          sv.seed('me', 'y', _t);
          l.seed('me', 'a', 'A', placeIds: ['x', 'y']);
        },
      );
      addTearDown(s.dispose);
      await pumpEventQueue();
      expect(s.listsRepo.writes, ['drop:a:x']);
      expect(s.listsRepo.get('me', 'a')!.placeIds, ['y']);
      expect(s.lists.listById('a')!.placeIds, ['y']);
    });

    test('re-salvar antes da limpeza não traz o local de volta', () async {
      final auth = FakeAuthRepository(uid: 'me');
      final savedRepo = FakeSavedRepository();
      final listsRepo = FakeListsRepository(saved: savedRepo)
        ..seed('me', 'a', 'A', placeIds: ['x'])
        ..writeGate = Completer();
      final saved = SavedPlacesStore(
        authRepository: auth,
        savedRepository: savedRepo,
      );
      final lists = ListsStore(
        authRepository: auth,
        listsRepository: listsRepo,
        savedStore: saved,
      );
      addTearDown(() {
        lists.dispose();
        saved.dispose();
      });
      await pumpEventQueue();
      // Limpeza já agendada (e escondida) ao carregar.
      expect(lists.listById('a')!.contains('x'), isFalse);

      expect(await saved.setSaved('x', true), isTrue);
      expect(lists.listById('a')!.contains('x'), isFalse);

      listsRepo.writeGate!.complete();
      await pumpEventQueue();
      expect(listsRepo.get('me', 'a')!.placeIds, isEmpty);
      expect(lists.listById('a')!.contains('x'), isFalse);
      expect(saved.isSaved('x'), isTrue);
    });

    test(
      'listas indisponíveis: remove só o salvo; a limpeza vem depois',
      () async {
        final s = await _make(
          seed: (sv, l) {
            sv.seed('me', 'p', _t);
            l
              ..seed('me', 'a', 'A', placeIds: ['p'])
              ..listError = Exception('network');
          },
        );
        addTearDown(s.dispose);
        expect(s.lists.hasError, isTrue);

        expect(await s.saved.setSaved('p', false), isTrue);
        expect(s.savedRepo.writes, ['remove:p']);
        expect(s.savedRepo.byUser['me']!.containsKey('p'), isFalse);
        // A recarga disparada pela remoção ainda falha (rede).
        await pumpEventQueue();
        expect(s.listsRepo.get('me', 'a')!.placeIds, ['p']);

        s.listsRepo.listError = null;
        await s.lists.reload();
        await pumpEventQueue();
        expect(s.listsRepo.get('me', 'a')!.placeIds, isEmpty);
      },
    );

    test(
      'lista apagada em outro aparelho: recarrega e tenta sem ela',
      () async {
        final s = await _make(
          seed: (sv, l) {
            sv.seed('me', 'p', _t);
            l
              ..seed('me', 'l1', 'Um', placeIds: ['p'])
              ..seed('me', 'l2', 'Dois', placeIds: ['p']);
          },
        );
        addTearDown(s.dispose);
        s.listsRepo.byUser['me']!.remove('l2');

        expect(await s.saved.setSaved('p', false), isTrue);
        expect(s.listsRepo.writes, [
          'removeEverywhere:p:l1,l2',
          'removeEverywhere:p:l1',
        ]);
        expect(s.savedRepo.byUser['me']!.containsKey('p'), isFalse);
        expect(s.listsRepo.get('me', 'l1')!.placeIds, isEmpty);
        expect(s.lists.listById('l2'), isNull);
      },
    );

    test(
      'add pendente → remove do Quero ir → libera: a lista fica sem o local',
      () async {
        final s = await _make(
          seed: (sv, l) {
            sv.seed('me', 'p', _t);
            l.seed('me', 'a', 'A');
          },
        );
        addTearDown(s.dispose);
        s.listsRepo.writeGate = Completer();
        final add = s.lists.setMembership('a', 'p', true);
        await pumpEventQueue();
        final removed = s.saved.setSaved('p', false);
        s.listsRepo.writeGate!.complete();
        await add;
        expect(await removed, isTrue);
        await pumpEventQueue();
        expect(s.listsRepo.get('me', 'a')!.placeIds, isEmpty);
        expect(s.lists.listById('a')!.contains('p'), isFalse);
        expect(s.savedRepo.byUser['me']!.containsKey('p'), isFalse);
      },
    );

    test(
      'criar com local → remove do Quero ir → libera: a lista fica sem ele',
      () async {
        final s = await _make(seed: (sv, _) => sv.seed('me', 'p', _t));
        addTearDown(s.dispose);
        s.listsRepo.writeGate = Completer();
        final created = s.lists.create('Nova', withPlace: 'p')!;
        await pumpEventQueue();
        final removed = s.saved.setSaved('p', false);
        s.listsRepo.writeGate!.complete();
        expect(await created.done, isTrue);
        expect(await removed, isTrue);
        await pumpEventQueue();
        expect(s.listsRepo.get('me', created.id)!.placeIds, isEmpty);
      },
    );

    test(
      'exclusão pendente falha e a lista volta sem quem saiu do Quero ir',
      () async {
        final s = await _make(
          seed: (sv, l) {
            sv.seed('me', 'p', _t);
            l.seed('me', 'a', 'A', placeIds: ['p']);
          },
        );
        addTearDown(s.dispose);
        s.listsRepo
          ..writeGate = Completer()
          ..failWhen = (op) => op.startsWith('delete:');
        final deleted = s.lists.delete('a');
        final removed = s.saved.setSaved('p', false);
        s.listsRepo.writeGate!.complete();
        expect(await deleted, isFalse);
        expect(await removed, isTrue);
        await pumpEventQueue();
        expect(s.lists.listById('a'), isNotNull);
        expect(s.listsRepo.get('me', 'a')!.placeIds, isEmpty);
      },
    );
  });

  group('revisão: offline não trava', () {
    test(
      'reload das listas espera escritas pendentes no máximo o limite',
      () async {
        final s = await _make(
          seed: (sv, l) {
            sv.seed('me', 'p', _t);
            l.seed('me', 'a', 'A');
          },
          waitTimeout: const Duration(milliseconds: 20),
        );
        addTearDown(s.dispose);
        s.listsRepo.writeGate = Completer(); // nunca liberado (offline)
        unawaited(s.lists.setMembership('a', 'p', true));
        await s.lists.reload().timeout(const Duration(seconds: 2));
        expect(s.lists.isReady, isTrue);
      },
    );

    test(
      'reload dos salvos espera escritas pendentes no máximo o limite',
      () async {
        final s = await _make(waitTimeout: const Duration(milliseconds: 20));
        addTearDown(s.dispose);
        s.savedRepo.writeGate = Completer(); // nunca liberado (offline)
        unawaited(s.saved.setSaved('p', true));
        await s.saved.reload().timeout(const Duration(seconds: 2));
        expect(s.saved.isReady, isTrue);
      },
    );
  });

  group('revisão: falha ao adicionar desfaz o salvamento que causou', () {
    test('create(withPlace) falhou: local volta a não salvo', () async {
      final s = await _make();
      addTearDown(s.dispose);
      s.listsRepo.failWhen = (op) => op.startsWith('create:');
      final created = s.lists.create('Nova', withPlace: 'p')!;
      expect(s.saved.isSaved('p'), isTrue);
      expect(await created.done, isFalse);
      await pumpEventQueue();
      expect(s.saved.isSaved('p'), isFalse);
      expect(s.savedRepo.byUser['me']?.containsKey('p') ?? false, isFalse);
    });

    test(
      'duas marcações concorrentes, uma falha: continua salvo e na outra',
      () async {
        final s = await _make(
          seed: (_, l) => l
            ..seed('me', 'a', 'A')
            ..seed('me', 'b', 'B'),
        );
        addTearDown(s.dispose);
        s.listsRepo.failWhen = (op) => op == 'add:a:p';
        final ra = s.lists.setMembership('a', 'p', true);
        final rb = s.lists.setMembership('b', 'p', true);
        expect(await ra, isFalse);
        expect(await rb, isTrue);
        await pumpEventQueue();
        expect(s.saved.isSaved('p'), isTrue);
        expect(s.listsRepo.get('me', 'b')!.placeIds, ['p']);
      },
    );

    test(
      'duas marcações concorrentes, as duas falham: desfaz o salvamento',
      () async {
        final s = await _make(
          seed: (_, l) => l
            ..seed('me', 'a', 'A')
            ..seed('me', 'b', 'B'),
        );
        addTearDown(s.dispose);
        s.listsRepo.failWhen = (op) => op.startsWith('add:');
        final ra = s.lists.setMembership('a', 'p', true);
        final rb = s.lists.setMembership('b', 'p', true);
        expect(await ra, isFalse);
        expect(await rb, isFalse);
        await pumpEventQueue();
        expect(s.saved.isSaved('p'), isFalse);
      },
    );
  });

  group('revisão: restore e renomear', () {
    test('restore repõe sem checar isFull e reporta falha parcial', () async {
      final s = await _make(
        seed: (sv, l) {
          sv.seed('me', 'p', _t);
          for (var i = 0; i < 199; i++) {
            sv.seed('me', 'o$i', _t);
          }
          l
            ..seed(
              'me',
              'a',
              'A',
              placeIds: ['p', for (var i = 0; i < 199; i++) 'o$i'],
            )
            ..seed('me', 'b', 'B', placeIds: ['p']);
        },
      );
      addTearDown(s.dispose);
      expect(await s.saved.setSaved('p', false), isTrue);
      // A lista "a" foi completada enquanto isso (exibida como cheia).
      expect(await s.lists.setMembership('a', 'q', true), isTrue);
      expect(s.lists.listById('a')!.isFull, isTrue);

      final result = await s.lists.restore('p', ['a', 'b']);
      expect(s.listsRepo.writes, contains('add:a:p'));
      expect(result, RestoreResult.someListsFailed);
      expect(s.saved.isSaved('p'), isTrue);
      expect(s.listsRepo.get('me', 'b')!.placeIds, ['p']);
    });

    test('restore sem falhas: ok', () async {
      final s = await _make(
        seed: (sv, l) {
          sv.seed('me', 'p', _t);
          l.seed('me', 'a', 'A', placeIds: ['p']);
        },
      );
      addTearDown(s.dispose);
      await s.saved.setSaved('p', false);
      expect(await s.lists.restore('p', ['a']), RestoreResult.ok);
      expect(s.listsRepo.get('me', 'a')!.placeIds, ['p']);
    });

    test('renomear sem mudança não escreve', () async {
      final s = await _make(
        seed: (_, l) => l.seed('me', 'a', 'Sábado', emoji: '🎉'),
      );
      addTearDown(s.dispose);
      expect(await s.lists.rename('a', '  Sábado ', emoji: '🎉'), isTrue);
      expect(s.listsRepo.writes, isEmpty);
    });
  });
}
