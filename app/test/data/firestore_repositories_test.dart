import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/data/firebase/firestore_place_repository.dart';
import 'package:naarea/data/firebase/firestore_review_repository.dart';
import 'package:naarea/data/firebase/firestore_user_repository.dart';
import 'package:naarea/domain/models/companion.dart';
import 'package:naarea/domain/models/review.dart';
import 'package:naarea/domain/models/scores.dart';

import '../support/builders.dart';

NewReview _newReview({Companion? companion}) => NewReview(
      authorId: 'alice',
      authorName: 'Alice',
      placeId: 'mangai',
      placeName: 'Mangai',
      scores: Scores(food: 5, ambience: 4, service: 3),
      companion: companion,
    );

Future<void> _addReview(
  FakeFirebaseFirestore db, {
  required String authorId,
  required DateTime createdAt,
  String placeId = 'p',
}) {
  return db.collection('reviews').add({
    'authorId': authorId,
    'authorName': authorId.toUpperCase(),
    'placeId': placeId,
    'placeName': 'Local $placeId',
    'food': 4,
    'ambience': 4,
    'service': 4,
    'companion': null,
    'createdAt': Timestamp.fromDate(createdAt),
  });
}

void main() {
  group('FirestoreReviewRepository.createReview', () {
    test('grava exatamente as 9 chaves que as Rules exigem', () async {
      final db = FakeFirebaseFirestore();
      await FirestoreReviewRepository(db).createReview(_newReview(companion: Companion.amigos));

      final docs = (await db.collection('reviews').get()).docs;
      expect(docs, hasLength(1));
      final data = docs.single.data();
      expect(data.keys.toSet(), {
        'authorId', 'authorName', 'placeId', 'placeName',
        'food', 'ambience', 'service', 'companion', 'createdAt',
      });
      expect(data['authorId'], 'alice');
      expect(data['authorName'], 'Alice');
      expect(data['food'], 5);
      expect(data['ambience'], 4);
      expect(data['service'], 3);
      expect(data['companion'], 'amigos');
      // FieldValue.serverTimestamp() é resolvido pelo fake como Timestamp.
      expect(data['createdAt'], isA<Timestamp>());
    });

    test('companion ausente é gravado como null (chave presente)', () async {
      final db = FakeFirebaseFirestore();
      await FirestoreReviewRepository(db).createReview(_newReview());
      final data = (await db.collection('reviews').get()).docs.single.data();
      expect(data.containsKey('companion'), isTrue);
      expect(data['companion'], isNull);
    });
  });

  group('FirestoreReviewRepository.fetchReviewsByAuthors', () {
    test('65 autores (3 lotes de whereIn): junta todos, sem duplicar, mais recente primeiro', () async {
      final db = FakeFirebaseFirestore();
      final authors = List.generate(65, (i) => 'u$i');
      for (var i = 0; i < authors.length; i++) {
        await _addReview(db, authorId: authors[i], createdAt: DateTime.utc(2026, 1, 1).add(Duration(hours: i)));
      }
      await _addReview(db, authorId: 'nao-seguido', createdAt: DateTime.utc(2026, 6, 1));

      // ids repetidos na entrada não podem duplicar resultados
      final result = await FirestoreReviewRepository(db)
          .fetchReviewsByAuthors([...authors, 'u0', 'u64']);

      expect(result, hasLength(65));
      expect(result.map((r) => r.id).toSet(), hasLength(65));
      expect(result.map((r) => r.authorId).toSet(), authors.toSet());
      expect(result.first.authorId, 'u64');
      expect(result.last.authorId, 'u0');
    });

    test('lista vazia não consulta nada', () async {
      expect(await FirestoreReviewRepository(FakeFirebaseFirestore()).fetchReviewsByAuthors([]), isEmpty);
    });

    test('lote cheio corta avaliações mais antigas que o limite dele', () async {
      final db = FakeFirebaseFirestore();
      // Lote 1 (u0..u29): u0 tem 5 avaliações recentes (dias 10..14) -> lote cheio com limite 3.
      for (var d = 10; d <= 14; d++) {
        await _addReview(db, authorId: 'u0', createdAt: DateTime.utc(2026, 9, d));
      }
      final batch1 = List.generate(30, (i) => 'u$i');
      // Lote 2 (v0): avaliações antigas (dia 1) e recente (dia 13).
      await _addReview(db, authorId: 'v0', createdAt: DateTime.utc(2026, 9, 1));
      await _addReview(db, authorId: 'v0', createdAt: DateTime.utc(2026, 9, 13));

      final result = await FirestoreReviewRepository(db, perBatchLimit: 3)
          .fetchReviewsByAuthors([...batch1, 'v0']);

      // Lote 1 trouxe dias 14, 13, 12 (cheio; mais antigo = 12). Corte = dia 12.
      // v0 do dia 1 é descartado: o lote 1 pode ter avaliações daquela época
      // que não vieram.
      expect(result.map((r) => r.createdAt.toUtc().day), [14, 13, 13, 12]);
    });

    test('documento fora do schema é ignorado', () async {
      final db = FakeFirebaseFirestore();
      await _addReview(db, authorId: 'a', createdAt: DateTime.utc(2026, 9, 1));
      await db.collection('reviews').add({'authorId': 'a', 'food': 'x', 'createdAt': Timestamp.now()});
      final result = await FirestoreReviewRepository(db).fetchReviewsByAuthors(['a']);
      expect(result, hasLength(1));
    });
  });

  group('FirestoreReviewRepository.applyBatchCutoff', () {
    test('sem corte só ordena; com corte mantém >= corte', () {
      final a = review(createdAt: DateTime.utc(2026, 9, 1));
      final b = review(createdAt: DateTime.utc(2026, 9, 5));
      final c = review(createdAt: DateTime.utc(2026, 9, 3));
      expect(FirestoreReviewRepository.applyBatchCutoff([a, b, c], null), [b, c, a]);
      expect(FirestoreReviewRepository.applyBatchCutoff([a, b, c], DateTime.utc(2026, 9, 3)), [b, c]);
    });
  });

  group('FirestoreUserRepository', () {
    test('searchByName: prefixo de displayNameLower, sem pegar vizinhos', () async {
      final db = FakeFirebaseFirestore();
      final repo = FirestoreUserRepository(db);
      await repo.createProfile(uid: 'bianca', displayName: 'Bianca');
      await repo.createProfile(uid: 'bia2', displayName: 'Bia Souza');
      await repo.createProfile(uid: 'bernardo', displayName: 'Bernardo');
      await repo.createProfile(uid: 'bj', displayName: 'Bj');
      await repo.createProfile(uid: 'toni', displayName: 'Toni');

      final found = await repo.searchByName('  BIA ');
      expect(found.map((p) => p.uid).toSet(), {'bianca', 'bia2'});
      expect(await repo.searchByName(''), isEmpty);
    });

    test('createProfile normaliza e grava displayNameLower', () async {
      final db = FakeFirebaseFirestore();
      await FirestoreUserRepository(db).createProfile(uid: 'u', displayName: '  Ana Luíza ');
      final data = (await db.doc('users/u').get()).data();
      expect(data, {'displayName': 'Ana Luíza', 'displayNameLower': 'ana luíza'});
    });

    test('follow / getFollowing / unfollow', () async {
      final repo = FirestoreUserRepository(FakeFirebaseFirestore());
      await repo.follow(uid: 'me', targetUid: 'a');
      await repo.follow(uid: 'me', targetUid: 'b');
      expect(await repo.getFollowing('me'), {'a', 'b'});
      await repo.unfollow(uid: 'me', targetUid: 'a');
      expect(await repo.getFollowing('me'), {'b'});
    });
  });

  group('FirestorePlaceRepository', () {
    test('ignora documentos malformados sem derrubar a lista', () async {
      final db = FakeFirebaseFirestore();
      await db.doc('places/ok').set({'name': 'Mangai', 'category': 'Restaurante', 'neighborhood': 'Tirol', 'city': 'Natal'});
      await db.doc('places/parcial').set({'name': 'Beco da Lama', 'category': 42});
      await db.doc('places/sem-nome').set({'category': 'Bar'});
      await db.doc('places/nome-numero').set({'name': 7});
      await db.doc('places/nome-vazio').set({'name': '  '});

      final places = await FirestorePlaceRepository(db).listPlaces();
      expect(places.map((p) => p.id).toSet(), {'ok', 'parcial'});
      final parcial = places.firstWhere((p) => p.id == 'parcial');
      expect(parcial.category, '');
      expect(parcial.neighborhood, '');
    });
  });
}
