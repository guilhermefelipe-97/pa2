import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/data/firebase/firestore_review_photo_repository.dart';
import 'package:naarea/data/repositories/review_photo_repository.dart';

import '../support/fakes.dart';

/// Fonte controlável para testar o contrato de cache.
class _Source extends CachedReviewPhotoRepository {
  _Source({super.authRepository, super.clock, super.maxCached});

  final Map<String, Uint8List> photos = {};
  final Set<String> failing = {};
  bool throwSync = false;
  final List<String> calls = [];

  @override
  Future<Uint8List?> fetch(String reviewId) {
    calls.add(reviewId);
    if (throwSync) throw StateError('sync');
    if (failing.contains(reviewId)) {
      return Future.error(Exception('network'));
    }
    return Future.value(photos[reviewId]);
  }
}

Uint8List _bytes(int n) => Uint8List.fromList([0xFF, 0xD8, 0xFF, n]);

void main() {
  group('FirestoreReviewPhotoRepository', () {
    late FakeFirebaseFirestore db;
    late FirestoreReviewPhotoRepository repo;
    final jpeg = _bytes(9);

    setUp(() async {
      db = FakeFirebaseFirestore();
      repo = FirestoreReviewPhotoRepository(db);
      await db.doc('reviewPhotos/r1').set({
        'authorId': 'ana',
        'jpeg': Blob(jpeg),
        'createdAt': Timestamp.now(),
      });
    });

    test('lê os bytes da foto pelo id da avaliação', () async {
      expect(await repo.getPhoto('r1'), jpeg);
      expect(repo.peek('r1'), jpeg);
    });

    test('foto inexistente: null, e null não fica em cache', () async {
      expect(await repo.getPhoto('sem-foto'), isNull);
      expect(await repo.getPhoto('sem-foto'), isNull);
      expect(repo.readCount, 2);
    });

    test('id inválido não consulta', () async {
      expect(await repo.getPhoto(''), isNull);
      expect(await repo.getPhoto('a/b'), isNull);
      expect(repo.readCount, 0);
    });

    test('cache: segunda chamada não lê de novo', () async {
      await repo.getPhoto('r1');
      await repo.getPhoto('r1');
      expect(repo.readCount, 1);
    });

    test('pedidos simultâneos do mesmo id viram uma leitura só', () async {
      final results = await Future.wait([
        repo.getPhoto('r1'),
        repo.getPhoto('r1'),
        repo.getPhoto('r1'),
      ]);
      expect(results, everyElement(jpeg));
      expect(repo.readCount, 1);
    });
  });

  group('CachedReviewPhotoRepository (contrato)', () {
    test('peek: null antes de carregar, bytes depois', () async {
      final repo = _Source()..photos['a'] = _bytes(1);
      expect(repo.peek('a'), isNull);
      await repo.getPhoto('a');
      expect(repo.peek('a'), _bytes(1));
    });

    test('erro e depois sucesso: backoff de 30 s antes de reler', () async {
      var now = DateTime.utc(2026, 10, 5, 12);
      final repo = _Source(clock: () => now)..failing.add('a');
      await expectLater(repo.getPhoto('a'), throwsException);
      expect(repo.readCount, 1);

      repo
        ..failing.clear()
        ..photos['a'] = _bytes(1);
      now = now.add(const Duration(seconds: 29));
      await expectLater(
        repo.getPhoto('a'),
        throwsA(isA<ReviewPhotoBackoffException>()),
      );
      expect(repo.readCount, 1, reason: 'dentro do backoff não relê');

      now = now.add(const Duration(seconds: 1));
      expect(await repo.getPhoto('a'), _bytes(1));
      expect(repo.readCount, 2);
    });

    test('throw síncrono da fonte não fica em cache', () async {
      var now = DateTime.utc(2026, 10, 5, 12);
      final repo = _Source(clock: () => now)..throwSync = true;
      await expectLater(repo.getPhoto('a'), throwsStateError);
      repo
        ..throwSync = false
        ..photos['a'] = _bytes(1);
      now = now.add(const Duration(seconds: 31));
      expect(await repo.getPhoto('a'), _bytes(1));
      expect(repo.readCount, 2);
    });

    test('LRU: guarda no máximo maxCached fotos, sai a menos usada', () async {
      final repo = _Source(maxCached: 3);
      for (var i = 0; i < 4; i++) {
        repo.photos['p$i'] = _bytes(i);
      }
      await repo.getPhoto('p0');
      await repo.getPhoto('p1');
      await repo.getPhoto('p2');
      repo.peek('p0'); // p0 passa a ser a mais recente
      await repo.getPhoto('p3'); // expulsa p1
      expect(repo.peek('p1'), isNull);
      expect(repo.peek('p0'), isNotNull);
      expect(repo.peek('p2'), isNotNull);
      expect(repo.peek('p3'), isNotNull);
    });

    test('LRU padrão é 60', () {
      expect(CachedReviewPhotoRepository.defaultMaxCached, 60);
      expect(_Source().maxCached, 60);
    });

    test('clear() esquece cache, backoff e leituras em voo', () async {
      final repo = _Source()..photos['a'] = _bytes(1);
      await repo.getPhoto('a');
      repo.clear();
      expect(repo.peek('a'), isNull);
      await repo.getPhoto('a');
      expect(repo.readCount, 2);
    });

    test('leitura em voo durante clear() não repovoa o cache', () async {
      final repo = _Source()..photos['a'] = _bytes(1);
      final pending = repo.getPhoto('a');
      repo.clear();
      await pending;
      expect(repo.peek('a'), isNull);
    });

    test('troca de usuário no auth limpa o cache; mesmo usuário não', () async {
      final auth = FakeAuthRepository(uid: 'ana');
      final repo = _Source(authRepository: auth)..photos['a'] = _bytes(1);
      await repo.getPhoto('a');
      auth.restoreSession('ana');
      expect(repo.peek('a'), isNotNull);
      await auth.signOut();
      expect(repo.peek('a'), isNull);
      repo.dispose();
    });
  });
}
