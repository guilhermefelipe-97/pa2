import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/data/firebase/firestore_place_repository.dart';
import 'package:naarea/data/firebase/firestore_review_repository.dart';
import 'package:naarea/data/firebase/firestore_user_repository.dart';
import 'package:naarea/domain/models/companion.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/domain/models/review.dart';
import 'package:naarea/domain/models/scores.dart';
import 'package:naarea/domain/search_tokens.dart';

import '../support/builders.dart';

NewReview _newReview({Companion? companion, String? comment}) => NewReview(
  authorId: 'alice',
  authorName: 'Alice',
  placeId: 'mangai',
  placeName: 'Mangai',
  scores: Scores(food: 5, ambience: 4, service: 3),
  companion: companion,
  comment: comment,
);

Future<void> _addReview(
  FakeFirebaseFirestore db, {
  required String authorId,
  required DateTime createdAt,
  String placeId = 'p',
  Object? comment,
  bool omitComment = false,
  Object? hasPhoto,
  bool omitHasPhoto = true,
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
    if (!omitComment) 'comment': comment,
    if (!omitHasPhoto) 'hasPhoto': hasPhoto,
    'createdAt': Timestamp.fromDate(createdAt),
  });
}

/// Lê os docs por id (getPlaces) — o repositório não tem "listar tudo".
Future<Map<String, Place>> _allById(FakeFirebaseFirestore db) async {
  final ids = (await db.collection('places').get()).docs.map((d) => d.id);
  return FirestorePlaceRepository(db).getPlaces(ids);
}

Future<List<Place>> _all(FakeFirebaseFirestore db) async =>
    (await _allById(db)).values.toList();

/// Doc de `places` como o seed grava (nameLower + searchTokens).
Future<void> _seedPlace(
  FakeFirebaseFirestore db,
  String id,
  String name, {
  String source = 'osm',
  String? photoUrl,
  String category = 'Restaurante',
}) => db.doc('places/$id').set({
  'name': name,
  'nameLower': nameLower(name),
  'searchTokens': searchTokens(name),
  'category': category,
  'neighborhood': 'Ponta Negra',
  'city': 'Natal',
  'source': source,
  'photoUrl': ?photoUrl,
});

void main() {
  group('FirestoreReviewRepository.createReview', () {
    test('grava exatamente as 11 chaves que as Rules exigem', () async {
      final db = FakeFirebaseFirestore();
      await FirestoreReviewRepository(
        db,
      ).createReview(_newReview(companion: Companion.amigos));

      final docs = (await db.collection('reviews').get()).docs;
      expect(docs, hasLength(1));
      final data = docs.single.data();
      expect(data.keys.toSet(), {
        'authorId',
        'authorName',
        'placeId',
        'placeName',
        'food',
        'ambience',
        'service',
        'companion',
        'comment',
        'hasPhoto',
        'createdAt',
      });
      expect(data['hasPhoto'], isFalse);
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

    test('sem comentário: chave comment presente com null', () async {
      final db = FakeFirebaseFirestore();
      await FirestoreReviewRepository(
        db,
      ).createReview(_newReview(comment: '   '));
      final data = (await db.collection('reviews').get()).docs.single.data();
      expect(data.containsKey('comment'), isTrue);
      expect(data['comment'], isNull);
    });

    test('sem foto: hasPhoto false e nenhum doc em reviewPhotos', () async {
      final db = FakeFirebaseFirestore();
      await FirestoreReviewRepository(db).createReview(_newReview());
      final data = (await db.collection('reviews').get()).docs.single.data();
      expect(data['hasPhoto'], isFalse);
      expect((await db.collection('reviewPhotos').get()).docs, isEmpty);
    });

    test(
      'com foto: review hasPhoto true + reviewPhotos/{mesmo id} com bytes',
      () async {
        final db = FakeFirebaseFirestore();
        final jpeg = Uint8List.fromList([0xFF, 0xD8, 1, 2, 3]);
        await FirestoreReviewRepository(
          db,
        ).createReview(_newReview(), photo: jpeg);
        final review = (await db.collection('reviews').get()).docs.single;
        expect(review.data()['hasPhoto'], isTrue);
        final photos = (await db.collection('reviewPhotos').get()).docs;
        expect(photos, hasLength(1));
        expect(photos.single.id, review.id);
        final photo = photos.single.data();
        expect(photo.keys.toSet(), {'authorId', 'jpeg', 'createdAt'});
        expect(photo['authorId'], 'alice');
        expect((photo['jpeg'] as Blob).bytes, jpeg);
        expect(photo['createdAt'], isA<Timestamp>());
      },
    );

    test(
      'foto vazia ou acima de 150.000 bytes nem chega ao Firestore',
      () async {
        final db = FakeFirebaseFirestore();
        final repo = FirestoreReviewRepository(db);
        expect(
          () => repo.createReview(_newReview(), photo: Uint8List(150001)),
          throwsArgumentError,
        );
        expect(
          () => repo.createReview(_newReview(), photo: Uint8List(0)),
          throwsArgumentError,
        );
        expect((await db.collection('reviews').get()).docs, isEmpty);
      },
    );

    test('comentário é gravado aparado', () async {
      final db = FakeFirebaseFirestore();
      await FirestoreReviewRepository(
        db,
      ).createReview(_newReview(comment: '  Fila grande, valeu a pena. '));
      final data = (await db.collection('reviews').get()).docs.single.data();
      expect(data['comment'], 'Fila grande, valeu a pena.');
    });
  });

  group('FirestoreReviewRepository.fetchReviewsByAuthors', () {
    test('limit: só as N mais recentes no total, entre lotes', () async {
      final db = FakeFirebaseFirestore();
      final authors = List.generate(40, (i) => 'w$i'); // 2 lotes de whereIn
      for (var i = 0; i < authors.length; i++) {
        for (var k = 0; k < 2; k++) {
          await _addReview(
            db,
            authorId: authors[i],
            createdAt: DateTime.utc(2026, 1, 1).add(Duration(hours: i * 2 + k)),
          );
        }
      }
      final result = await FirestoreReviewRepository(
        db,
      ).fetchReviewsByAuthors(authors, limit: 5);
      expect(result, hasLength(5));
      expect(result.map((r) => r.createdAt.toUtc()), [
        for (var h = 79; h > 74; h--)
          DateTime.utc(2026, 1, 1).add(Duration(hours: h)),
      ]);
    });

    test(
      '65 autores (3 lotes de whereIn): junta todos, sem duplicar, mais recente primeiro',
      () async {
        final db = FakeFirebaseFirestore();
        final authors = List.generate(65, (i) => 'u$i');
        for (var i = 0; i < authors.length; i++) {
          await _addReview(
            db,
            authorId: authors[i],
            createdAt: DateTime.utc(2026, 1, 1).add(Duration(hours: i)),
          );
        }
        await _addReview(
          db,
          authorId: 'nao-seguido',
          createdAt: DateTime.utc(2026, 6, 1),
        );

        // ids repetidos na entrada não podem duplicar resultados
        final result = await FirestoreReviewRepository(
          db,
        ).fetchReviewsByAuthors([...authors, 'u0', 'u64']);

        expect(result, hasLength(65));
        expect(result.map((r) => r.id).toSet(), hasLength(65));
        expect(result.map((r) => r.authorId).toSet(), authors.toSet());
        expect(result.first.authorId, 'u64');
        expect(result.last.authorId, 'u0');
      },
    );

    test('lista vazia não consulta nada', () async {
      expect(
        await FirestoreReviewRepository(
          FakeFirebaseFirestore(),
        ).fetchReviewsByAuthors([]),
        isEmpty,
      );
    });

    test('lote cheio corta avaliações mais antigas que o limite dele', () async {
      final db = FakeFirebaseFirestore();
      // Lote 1 (u0..u29): u0 tem 5 avaliações recentes (dias 10..14) -> lote cheio com limite 3.
      for (var d = 10; d <= 14; d++) {
        await _addReview(
          db,
          authorId: 'u0',
          createdAt: DateTime.utc(2026, 9, d),
        );
      }
      final batch1 = List.generate(30, (i) => 'u$i');
      // Lote 2 (v0): avaliações antigas (dia 1) e recente (dia 13).
      await _addReview(db, authorId: 'v0', createdAt: DateTime.utc(2026, 9, 1));
      await _addReview(
        db,
        authorId: 'v0',
        createdAt: DateTime.utc(2026, 9, 13),
      );

      final result = await FirestoreReviewRepository(
        db,
        perBatchLimit: 3,
      ).fetchReviewsByAuthors([...batch1, 'v0']);

      // Lote 1 trouxe dias 14, 13, 12 (cheio; mais antigo = 12). Corte = dia 12.
      // v0 do dia 1 é descartado: o lote 1 pode ter avaliações daquela época
      // que não vieram.
      expect(result.map((r) => r.createdAt.toUtc().day), [14, 13, 13, 12]);
    });

    test(
      'lê comment normalizado; doc antigo sem a chave ou tipo errado vira null',
      () async {
        final db = FakeFirebaseFirestore();
        await _addReview(
          db,
          authorId: 'a',
          createdAt: DateTime.utc(2026, 9, 3),
          comment: 'Top!',
        );
        await _addReview(
          db,
          authorId: 'a',
          createdAt: DateTime.utc(2026, 9, 2),
          comment: 7,
        );
        await _addReview(
          db,
          authorId: 'a',
          createdAt: DateTime.utc(2026, 9, 1),
          omitComment: true,
        );
        await _addReview(
          db,
          authorId: 'a',
          createdAt: DateTime.utc(2026, 8, 31),
          comment: '   ',
        );
        await _addReview(
          db,
          authorId: 'a',
          createdAt: DateTime.utc(2026, 8, 30),
          comment: '  Bom  ',
        );
        final result = await FirestoreReviewRepository(
          db,
        ).fetchReviewsByAuthors(['a']);
        expect(
          result.map((r) => r.comment),
          ['Top!', null, null, null, 'Bom'],
          reason: 'normaliza na leitura: só espaços vira null, pontas aparadas',
        );
      },
    );

    test(
      'lê hasPhoto; doc antigo sem a chave ou tipo errado = sem foto',
      () async {
        final db = FakeFirebaseFirestore();
        await _addReview(
          db,
          authorId: 'a',
          createdAt: DateTime.utc(2026, 9, 3),
          omitHasPhoto: false,
          hasPhoto: true,
        );
        await _addReview(
          db,
          authorId: 'a',
          createdAt: DateTime.utc(2026, 9, 2),
          omitHasPhoto: false,
          hasPhoto: false,
        );
        await _addReview(
          db,
          authorId: 'a',
          createdAt: DateTime.utc(2026, 9, 1),
        );
        await _addReview(
          db,
          authorId: 'a',
          createdAt: DateTime.utc(2026, 8, 31),
          omitHasPhoto: false,
          hasPhoto: 'true',
        );
        final result = await FirestoreReviewRepository(
          db,
        ).fetchReviewsByAuthors(['a']);
        expect(result.map((r) => r.hasPhoto), [true, false, false, false]);
      },
    );

    test('documento fora do schema é ignorado', () async {
      final db = FakeFirebaseFirestore();
      await _addReview(db, authorId: 'a', createdAt: DateTime.utc(2026, 9, 1));
      await db.collection('reviews').add({
        'authorId': 'a',
        'food': 'x',
        'createdAt': Timestamp.now(),
      });
      final result = await FirestoreReviewRepository(
        db,
      ).fetchReviewsByAuthors(['a']);
      expect(result, hasLength(1));
    });
  });

  group('FirestoreReviewRepository.applyBatchCutoff', () {
    test('sem corte só ordena; com corte mantém >= corte', () {
      final a = review(createdAt: DateTime.utc(2026, 9, 1));
      final b = review(createdAt: DateTime.utc(2026, 9, 5));
      final c = review(createdAt: DateTime.utc(2026, 9, 3));
      expect(FirestoreReviewRepository.applyBatchCutoff([a, b, c], null), [
        b,
        c,
        a,
      ]);
      expect(
        FirestoreReviewRepository.applyBatchCutoff([
          a,
          b,
          c,
        ], DateTime.utc(2026, 9, 3)),
        [b, c],
      );
    });
  });

  group('FirestoreUserRepository', () {
    test(
      'searchByName: prefixo de displayNameLower, sem pegar vizinhos',
      () async {
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
      },
    );

    test('createProfile normaliza e grava displayNameLower', () async {
      final db = FakeFirebaseFirestore();
      await FirestoreUserRepository(
        db,
      ).createProfile(uid: 'u', displayName: '  Ana Luíza ');
      final data = (await db.doc('users/u').get()).data();
      expect(data, {
        'displayName': 'Ana Luíza',
        'displayNameLower': 'ana luíza',
      });
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
      await db.doc('places/ok').set({
        'name': 'Mangai',
        'category': 'Restaurante',
        'neighborhood': 'Tirol',
        'city': 'Natal',
      });
      await db.doc('places/parcial').set({
        'name': 'Beco da Lama',
        'category': 42,
      });
      await db.doc('places/sem-nome').set({'category': 'Bar'});
      await db.doc('places/nome-numero').set({'name': 7});
      await db.doc('places/nome-vazio').set({'name': '  '});

      final places = await _all(db);
      expect(places.map((p) => p.id).toSet(), {'ok', 'parcial'});
      final parcial = places.firstWhere((p) => p.id == 'parcial');
      expect(parcial.category, '');
      expect(parcial.neighborhood, '');
    });

    test('lê photoUrl; ausente, vazio ou não-string vira null', () async {
      final db = FakeFirebaseFirestore();
      await db.doc('places/com').set({
        'name': 'A',
        'photoUrl': 'https://upload.wikimedia.org/x.jpg',
      });
      await db.doc('places/sem').set({'name': 'B'});
      await db.doc('places/vazio').set({'name': 'C', 'photoUrl': '  '});
      await db.doc('places/numero').set({'name': 'D', 'photoUrl': 3});
      final byId = await _allById(db);
      expect(byId['com']!.photoUrl, 'https://upload.wikimedia.org/x.jpg');
      expect(byId['sem']!.photoUrl, isNull);
      expect(byId['vazio']!.photoUrl, isNull);
      expect(byId['numero']!.photoUrl, isNull);
    });

    test(
      'lê crédito da foto (autor, licença, ilustrativa) de forma tolerante',
      () async {
        final db = FakeFirebaseFirestore();
        await db.doc('places/a').set({
          'name': 'A',
          'photoUrl': 'https://upload.wikimedia.org/a.jpg',
          'photoAuthor': ' Beraldo Leal ',
          'photoLicense': 'CC BY 2.0',
          'photoIllustrative': true,
        });
        await db.doc('places/b').set({
          'name': 'B',
          'photoAuthor': 3,
          'photoIllustrative': 'sim',
        });
        final byId = await _allById(db);
        expect(byId['a']!.photoAuthor, 'Beraldo Leal');
        expect(byId['a']!.photoLicense, 'CC BY 2.0');
        expect(byId['a']!.photoIllustrative, isTrue);
        expect(byId['b']!.photoAuthor, isNull);
        expect(byId['b']!.photoLicense, isNull);
        expect(byId['b']!.photoIllustrative, isFalse);
      },
    );

    test(
      'lê os campos do OSM (coordenadas, cozinha, endereço, horário, origem)',
      () async {
        final db = FakeFirebaseFirestore();
        await db.doc('places/osm-n1').set({
          'name': 'Camarões',
          'lat': -5.88,
          'lng': -35.17,
          'cuisine': 'Frutos do mar',
          'address': 'Av. Engenheiro Roberto Freire, 2610',
          'openingHours': 'Mo-Su 11:30-23:00',
          'osmId': 'node/1',
          'source': 'osm',
        });
        await db.doc('places/ruim').set({
          'name': 'X',
          'lat': 'a',
          'lng': -35,
          'source': 3,
        });
        await db.doc('places/meia').set({'name': 'Y', 'lat': -5.8});
        final byId = await _allById(db);
        final p = byId['osm-n1']!;
        expect(p.lat, -5.88);
        expect(p.lng, -35.17);
        expect(p.cuisine, 'Frutos do mar');
        expect(p.address, 'Av. Engenheiro Roberto Freire, 2610');
        expect(p.openingHours, 'Mo-Su 11:30-23:00');
        expect(p.osmId, 'node/1');
        expect(p.source, PlaceSource.osm);
        expect(p.hasOsmData, isTrue);
        expect(byId['ruim']!.lat, isNull);
        expect(byId['ruim']!.lng, isNull);
        expect(byId['ruim']!.source, PlaceSource.curated);
        expect(byId['meia']!.lat, isNull, reason: 'sem par lat/lng completo');
        expect(byId['meia']!.hasOsmData, isFalse);
      },
    );

    test(
      'search: token sem acento/caixa, ordenado por nome, termos extras no cliente',
      () async {
        final db = FakeFirebaseFirestore();
        await _seedPlace(db, 'c1', 'Camarões Potiguar');
        await _seedPlace(db, 'c2', 'Camarões');
        await _seedPlace(db, 'c3', 'Bar do Camarada');
        await _seedPlace(db, 'm', 'Mangai');
        final repo = FirestorePlaceRepository(db);

        expect((await repo.search('CAMAR')).map((p) => p.id), [
          'c3',
          'c2',
          'c1',
        ]);
        expect((await repo.search('camarões pot')).map((p) => p.id), ['c1']);
        expect((await repo.search('pot camar')).map((p) => p.id), ['c1']);
        expect(await repo.search('c'), isEmpty);
        expect(await repo.search('  '), isEmpty);
        expect(await repo.search('xyz'), isEmpty);
      },
    );

    test(
      'search: manda ao servidor o termo mais longo; o doc que casa todos aparece mesmo depois do 20º',
      () async {
        final db = FakeFirebaseFirestore();
        // 70 docs com "de" antes do alvo em nameLower: com o 1º termo ("de")
        // a página de 60 enche e o alvo fica de fora.
        for (var i = 0; i < 70; i++) {
          await _seedPlace(db, 'b$i', 'Bar de ${i.toString().padLeft(2, '0')}');
        }
        // 25 docs com "camaroes" antes do alvo (o alvo é o 26º).
        for (var i = 0; i < 25; i++) {
          await _seedPlace(
            db,
            'c$i',
            'Camarões ${i.toString().padLeft(2, '0')}',
          );
        }
        await _seedPlace(db, 'alvo', 'Camarões de Zé');
        final r = await FirestorePlaceRepository(db).search('de camarões');
        expect(r.map((p) => p.id), ['alvo']);
      },
    );

    test('search: no máximo 20 resultados', () async {
      final db = FakeFirebaseFirestore();
      for (var i = 0; i < 25; i++) {
        await _seedPlace(db, 'b$i', 'Bar ${i.toString().padLeft(2, '0')}');
      }
      final r = await FirestorePlaceRepository(db).search('bar');
      expect(r, hasLength(20));
      expect(r.first.name, 'Bar 00');
    });

    test('suggestions: só curados com foto, por nome', () async {
      final db = FakeFirebaseFirestore();
      await _seedPlace(
        db,
        'z',
        'Zé',
        source: 'curated',
        photoUrl: 'https://f/z.jpg',
      );
      await _seedPlace(
        db,
        'a',
        'Árvore',
        source: 'curated',
        photoUrl: 'https://f/a.jpg',
      );
      await _seedPlace(db, 'sem-foto', 'Sem foto', source: 'curated');
      await _seedPlace(db, 'osm', 'Do OSM', photoUrl: 'https://f/o.jpg');
      final r = await FirestorePlaceRepository(db).suggestions();
      expect(r.map((p) => p.id), ['a', 'z']);
    });

    test(
      'getPlaces: ids vazios ou com "/" são ignorados sem consultar',
      () async {
        final db = FakeFirebaseFirestore();
        await _seedPlace(db, 'p1', 'Local 1');
        final repo = FirestorePlaceRepository(db);
        expect(await repo.getPlaces(['', 'a/b', '/']), isEmpty);
        expect(repo.queryCount, 0);
        expect((await repo.getPlaces(['', 'p1', 'x/y'])).keys, ['p1']);
        expect(repo.queryCount, 1);
      },
    );

    test(
      'getPlaces: id ausente fica em cache e não é consultado de novo na sessão',
      () async {
        final db = FakeFirebaseFirestore();
        final repo = FirestorePlaceRepository(db);
        expect(await repo.getPlaces(['sumiu']), isEmpty);
        expect(repo.queryCount, 1);
        await _seedPlace(db, 'sumiu', 'Voltou');
        expect(await repo.getPlaces(['sumiu']), isEmpty);
        expect(repo.queryCount, 1);
      },
    );

    test('getPlaces(refreshMissing): relê só quem estava ausente', () async {
      final db = FakeFirebaseFirestore();
      final repo = FirestorePlaceRepository(db);
      await _seedPlace(db, 'ok', 'Já existia');
      expect((await repo.getPlaces(['ok', 'sumiu'])).keys, ['ok']);
      expect(repo.queryCount, 1);

      await _seedPlace(db, 'sumiu', 'Voltou');
      final again = await repo.getPlaces(['ok', 'sumiu'], refreshMissing: true);
      expect(again['sumiu']!.name, 'Voltou');
      expect(repo.queryCount, 2);
    });

    test(
      'getPlaces: chamadas simultâneas pelos mesmos ids compartilham a consulta',
      () async {
        final db = FakeFirebaseFirestore();
        await _seedPlace(db, 'p1', 'Local 1');
        await _seedPlace(db, 'p2', 'Local 2');
        final repo = FirestorePlaceRepository(db);
        final results = await Future.wait([
          repo.getPlaces(['p1', 'p2']),
          repo.getPlaces(['p2', 'p1']),
          repo.getPlaces(['p1']),
        ]);
        expect(repo.queryCount, 1);
        expect(results[0].keys.toSet(), {'p1', 'p2'});
        expect(results[1].keys.toSet(), {'p1', 'p2'});
        expect(results[2].keys, ['p1']);
      },
    );

    test(
      'getPlaces: lotes de 30, ids ausentes ficam de fora, cache em memória',
      () async {
        final db = FakeFirebaseFirestore();
        for (var i = 0; i < 65; i++) {
          await _seedPlace(db, 'p$i', 'Local $i');
        }
        final repo = FirestorePlaceRepository(db);
        final ids = [for (var i = 0; i < 65; i++) 'p$i', 'nao-existe', ''];
        final byId = await repo.getPlaces(ids);
        expect(byId.keys.toSet(), {for (var i = 0; i < 65; i++) 'p$i'});

        // Cache: apagar no banco não muda o que já foi lido nesta sessão.
        await db.doc('places/p0').delete();
        expect((await repo.getPlaces(['p0']))['p0']!.name, 'Local 0');
        expect(await repo.getPlaces(const []), isEmpty);
      },
    );
  });
}
