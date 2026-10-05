import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/data/repositories/saved_repository.dart';
import 'package:naarea/ui/saved/saved_places_store.dart';

import '../support/fakes.dart';

void main() {
  late FakeAuthRepository auth;
  late FakeSavedRepository repo;
  final now = DateTime.utc(2026, 9, 28, 15);

  SavedPlacesStore make() => SavedPlacesStore(
    authRepository: auth,
    savedRepository: repo,
    clock: () => now,
  );

  setUp(() {
    auth = FakeAuthRepository(uid: 'me');
    repo = FakeSavedRepository()
      ..seed('me', 'velho', DateTime.utc(2026, 9, 1))
      ..seed('me', 'novo', DateTime.utc(2026, 9, 20));
  });

  test('carrega os salvos do usuário uma vez, mais recente primeiro', () async {
    final store = make();
    expect(store.isLoading, isTrue);
    await pumpEventQueue();
    expect(store.isReady, isTrue);
    expect(store.entries.map((e) => e.placeId), ['novo', 'velho']);
    expect(store.isSaved('novo'), isTrue);
    expect(repo.listCalls, 1);
  });

  test('salvar: ícone muda já (otimista), escreve e vai para o topo', () async {
    final store = make();
    await pumpEventQueue();
    repo.writeGate = Completer();

    final change = store.toggle('mangai')!;
    expect(change.saved, isTrue);
    expect(
      store.isSaved('mangai'),
      isTrue,
      reason: 'antes da resposta do servidor',
    );
    expect(store.entries.first.placeId, 'mangai');

    repo.writeGate!.complete();
    expect(await change.done, isTrue);
    expect(repo.byUser['me']!.containsKey('mangai'), isTrue);
  });

  test('remover: some já e apaga', () async {
    final store = make();
    await pumpEventQueue();
    final change = store.toggle('novo')!;
    expect(change.saved, isFalse);
    expect(store.isSaved('novo'), isFalse);
    expect(await change.done, isTrue);
    expect(repo.byUser['me']!.containsKey('novo'), isFalse);
  });

  test('falha ao salvar volta a vazio', () async {
    final store = make();
    await pumpEventQueue();
    repo.writeError = Exception('permission-denied');
    final change = store.toggle('mangai')!;
    expect(store.isSaved('mangai'), isTrue);
    expect(await change.done, isFalse);
    expect(store.isSaved('mangai'), isFalse);
  });

  test('falha ao remover volta a cheio, com a data original', () async {
    final store = make();
    await pumpEventQueue();
    repo.writeError = Exception('offline');
    final change = store.toggle('velho')!;
    expect(store.isSaved('velho'), isFalse);
    expect(await change.done, isFalse);
    expect(store.isSaved('velho'), isTrue);
    expect(store.entries.last.placeId, 'velho');
  });

  test(
    '3 toques rápidos: estado final = último toque; nunca 2 escritas simultâneas do mesmo id',
    () async {
      final store = make();
      await pumpEventQueue();
      repo.writeGate = Completer();

      final a = store.toggle('mangai')!; // salva (escrita em voo)
      final b = store.toggle('mangai')!; // remove
      final c = store.toggle('mangai')!; // salva
      expect([a.saved, b.saved, c.saved], [true, false, true]);
      expect(store.isSaved('mangai'), isTrue);
      expect(repo.writes, [
        'save:mangai',
      ], reason: 'só uma escrita saiu até agora');

      repo.writeGate!.complete();
      expect(await c.done, isTrue);
      expect(repo.maxConcurrentPerId, 1);
      expect(repo.writes, [
        'save:mangai',
      ], reason: 'o servidor já está no estado do último toque');
      expect(store.isSaved('mangai'), isTrue);
    },
  );

  test(
    'toques rápidos terminando em "remover": escritas em série até convergir',
    () async {
      final store = make();
      await pumpEventQueue();
      repo.writeGate = Completer();

      store.toggle('mangai'); // salva
      final last = store.toggle('mangai')!; // remove
      repo.writeGate!.complete();
      expect(await last.done, isTrue);
      expect(repo.writes, ['save:mangai', 'remove:mangai']);
      expect(repo.maxConcurrentPerId, 1);
      expect(store.isSaved('mangai'), isFalse);
      expect(repo.byUser['me']!.containsKey('mangai'), isFalse);
    },
  );

  test(
    'falha com o último toque já igual ao servidor não acusa erro',
    () async {
      final store = make();
      await pumpEventQueue();
      repo
        ..writeGate = Completer()
        ..writeError = Exception('x');
      store.toggle('mangai'); // salva (vai falhar)
      final undo = store.toggle('mangai')!; // volta a não salvo
      repo.writeGate!.complete();
      expect(await undo.done, isTrue);
      expect(store.isSaved('mangai'), isFalse);
    },
  );

  test('antes de carregar não troca (não dá para saber o estado)', () async {
    final gate = Completer<List<SavedPlace>>();
    repo.listOverride = (_) => gate.future;
    final store = make();
    expect(store.toggle('mangai'), isNull);
    gate.complete(const []);
    await pumpEventQueue();
    expect(store.toggle('mangai'), isNotNull);
  });

  test('erro na carga: reload tenta de novo', () async {
    repo.listError = Exception('offline');
    final store = make();
    await pumpEventQueue();
    expect(store.hasError, isTrue);

    repo.listError = null;
    await store.reload();
    expect(store.isReady, isTrue);
    expect(store.isSaved('novo'), isTrue);
  });

  test('troca de usuário limpa e carrega os salvos do novo', () async {
    repo.seed('outra', 'dela', DateTime.utc(2026, 9, 5));
    final store = make();
    await pumpEventQueue();

    auth.restoreSession(null);
    expect(store.entries, isEmpty);
    auth.restoreSession('outra');
    await pumpEventQueue();
    expect(store.entries.map((e) => e.placeId), ['dela']);
  });

  test('notifica ouvintes a cada mudança otimista', () async {
    final store = make();
    await pumpEventQueue();
    var n = 0;
    store.addListener(() => n++);
    store.toggle('mangai');
    expect(n, 1);
  });

  group('save sobre doc já existente', () {
    test(
      'set negado porque já existe: confirma como salvo, com o createdAt do servidor',
      () async {
        final store = make();
        await pumpEventQueue();
        // Outro aparelho salvou depois da carga desta sessão.
        final serverAt = DateTime.utc(2026, 9, 25, 10);
        repo.seed('me', 'mangai', serverAt);

        final change = store.toggle('mangai')!;
        expect(await change.done, isTrue);
        expect(store.isSaved('mangai'), isTrue);
        expect(
          store.entries.firstWhere((e) => e.placeId == 'mangai').savedAt,
          serverAt,
        );
        // Remover depois funciona: o confirmado ficou "salvo".
        expect(await store.toggle('mangai')!.done, isTrue);
        expect(repo.byUser['me']!.containsKey('mangai'), isFalse);
      },
    );

    test('falha e o doc não existe: reverte', () async {
      final store = make();
      await pumpEventQueue();
      repo.writeError = Exception('timeout');
      expect(await store.toggle('mangai')!.done, isFalse);
      expect(store.isSaved('mangai'), isFalse);
      expect(repo.savedAtOfCalls, 1);
    });

    test('falha e a releitura também falha: reverte', () async {
      final store = make();
      await pumpEventQueue();
      repo
        ..writeError = Exception('timeout')
        ..savedAtOfError = Exception('offline');
      expect(await store.toggle('mangai')!.done, isFalse);
      expect(store.isSaved('mangai'), isFalse);
    });

    test(
      'depois de confirmar, usa o createdAt real do servidor (não o relógio do aparelho)',
      () async {
        repo.clock = () => DateTime.utc(2026, 9, 28, 15, 0, 7);
        final store = make();
        await pumpEventQueue();
        expect(await store.toggle('mangai')!.done, isTrue);
        expect(
          store.entries.first.savedAt,
          DateTime.utc(2026, 9, 28, 15, 0, 7),
        );
      },
    );
  });

  group('reload com escritas em voo', () {
    test('espera as escritas e não desfaz o toque otimista', () async {
      final store = make();
      await pumpEventQueue();
      repo.writeGate = Completer();
      store.toggle('mangai'); // salvo, escrita presa
      store.toggle('novo'); // removido, escrita presa

      final reloading = store.reload();
      await pumpEventQueue();
      expect(store.isSaved('mangai'), isTrue);
      expect(store.isSaved('novo'), isFalse);
      expect(
        store.isReady,
        isTrue,
        reason: 'recarga de fundo não bloqueia o marcador',
      );

      repo.writeGate!.complete();
      await reloading;
      expect(store.isSaved('mangai'), isTrue);
      expect(store.isSaved('novo'), isFalse);
      expect(repo.byUser['me']!.keys, unorderedEquals(['velho', 'mangai']));
    });

    test(
      'toque durante a leitura da recarga é reaplicado por cima do servidor',
      () async {
        final store = make();
        await pumpEventQueue();
        final gate = Completer<List<SavedPlace>>();
        repo.listOverride = (_) => gate.future;
        final reloading = store.reload();
        await pumpEventQueue();

        repo.writeGate = Completer();
        store.toggle('mangai'); // salva durante a leitura
        gate.complete([
          SavedPlace(placeId: 'novo', savedAt: DateTime.utc(2026, 9, 20)),
        ]);
        await reloading;
        expect(
          store.isSaved('mangai'),
          isTrue,
          reason: 'o servidor ainda não tinha o mangai',
        );
        expect(
          store.isSaved('velho'),
          isFalse,
          reason: 'o resto segue o servidor',
        );

        repo.writeGate!.complete();
        await pumpEventQueue();
        expect(repo.byUser['me']!.containsKey('mangai'), isTrue);
      },
    );
  });

  test('"Desfazer" de uma remoção restaura a data original', () async {
    final store = make();
    await pumpEventQueue();
    repo.writeGate = Completer();
    store.toggle('velho'); // remove (em voo)
    store.setSaved('velho', true); // desfazer
    expect(store.entries.last.placeId, 'velho');
    expect(store.entries.last.savedAt, DateTime.utc(2026, 9, 1));
    repo.writeGate!.complete();
    await pumpEventQueue();
  });
}
