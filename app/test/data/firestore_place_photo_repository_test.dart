import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/data/firebase/firestore_place_photo_repository.dart';
import 'package:naarea/data/repositories/place_photo_repository.dart';

void main() {
  test('galeria persiste várias fotos com autoria e lê todas', () async {
    final db = FakeFirebaseFirestore();
    final repo = FirestorePlacePhotoRepository(db);
    final jpeg = Uint8List.fromList([255, 216, 255, 217]);
    await repo.add(
      'p1',
      authorId: 'me',
      authorName: 'Ana',
      photos: [jpeg, jpeg],
    );
    final found = await repo.list('p1');
    expect(found.photos, hasLength(2));
    expect(
      found.photos.every((p) => p.authorId == 'me' && p.authorName == 'Ana'),
      isTrue,
    );
    expect(found.photos.first.jpeg, orderedEquals(jpeg));
    await repo.remove('p1', found.photos.first.id);
    expect((await repo.list('p1')).photos, hasLength(1));
  });
  test('não grava lote inválido nem JPEG acima do limite', () async {
    final db = FakeFirebaseFirestore();
    final repo = FirestorePlacePhotoRepository(db);
    for (final photos in <List<Uint8List>>[
      [],
      [Uint8List(150001)],
      [Uint8List(5)],
      List.generate(7, (_) => Uint8List.fromList([255, 216, 255, 217])),
    ]) {
      await expectLater(
        repo.add('p1', authorId: 'me', authorName: 'Ana', photos: photos),
        throwsArgumentError,
      );
    }
    expect((await db.collection('places/p1/photos').get()).docs, isEmpty);
  });
  test('paginação mantém ordenação estável sem duplicar imagens', () async {
    final db = FakeFirebaseFirestore();
    final repo = FirestorePlacePhotoRepository(db);
    for (var i = 0; i < placeGalleryPageSize + 3; i++) {
      await db.doc('places/p1/photos/${i.toString().padLeft(3, '0')}').set({
        'authorId': 'a',
        'authorName': 'Ana',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 11, 1)),
        'jpeg': Blob(Uint8List.fromList([255, 216, 255, 217])),
      });
    }
    final first = await repo.list('p1');
    final next = await repo.list('p1', after: first.cursor);
    expect(first.photos, hasLength(placeGalleryPageSize));
    expect(next.photos, hasLength(3));
    expect({
      ...first.photos.map((p) => p.id),
      ...next.photos.map((p) => p.id),
    }, hasLength(placeGalleryPageSize + 3));
  });
}
