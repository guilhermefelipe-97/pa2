import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/ui/dietary/dietary_store.dart';
import '../support/fakes.dart';

class _SlowDietary extends FakeDietaryRepository {
  bool hang = true;
  final done = Completer<void>();
  @override
  Future<void> save(String uid, Set<String> tags) =>
      hang ? done.future : super.save(uid, tags);
}

void main() {
  test(
    'preferência sem confirmação libera interface e permite repetir sem perder a escolha salva',
    () async {
      final auth = FakeAuthRepository(uid: 'me');
      final repository = _SlowDietary()..stored['me'] = {'caseiro'};
      final store = DietaryStore(
        auth,
        repository,
        operationTimeout: const Duration(milliseconds: 10),
      );
      await store.load();
      expect(await store.save({'vegano'}), false);
      expect(store.tags, {'caseiro'});
      expect(store.loading, false);
      expect(store.error, contains('Não recebemos a confirmação'));
      repository.hang = false;
      expect(await store.save({'vegano'}), true);
      expect(store.tags, {'vegano'});
      repository.done.complete();
      store.dispose();
      auth.dispose();
    },
  );
}
