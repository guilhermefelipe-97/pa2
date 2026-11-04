import 'dart:typed_data';
import 'package:naarea/data/repositories/place_photo_repository.dart';
import 'package:naarea/data/repositories/queue_repository.dart';
import 'package:naarea/data/services/place_photo_picker.dart';
import 'package:naarea/domain/models/place.dart';

class FakePlacePhotoRepository implements PlacePhotoRepository {
  final photos = <PlaceGalleryPhoto>[];
  bool failWrite = false;
  int writes = 0;
  @override
  Future<PlaceGalleryPage> list(String placeId, {String? after}) async =>
      PlaceGalleryPage(List.of(photos));
  @override
  Future<void> add(
    String placeId, {
    required String authorId,
    required String authorName,
    required List<Uint8List> photos,
  }) async {
    if (failWrite) throw StateError('offline');
    writes++;
    for (final jpeg in photos) {
      this.photos.add(
        PlaceGalleryPhoto(
          id: '${this.photos.length}',
          authorId: authorId,
          authorName: authorName,
          createdAt: DateTime.utc(2026, 11, 1),
          jpeg: jpeg,
        ),
      );
    }
  }

  @override
  Future<void> remove(String placeId, String photoId) async =>
      photos.removeWhere((p) => p.id == photoId);
}

class FakePlacePhotoPicker implements PlacePhotoPicker {
  List<Uint8List> selected = [];
  @override
  Future<List<Uint8List>> pickMany() async => selected;
}

class FakeGalleryQueue implements QueueRepository {
  FakeGalleryQueue(this.at);
  final DateTime at;
  final reports = <QueueReport>[];
  @override
  Future<List<QueueReport>> fetchForPlace(
    String placeId, {
    required DateTime since,
  }) async => reports;
  @override
  Future<DateTime?> queueReportLockOf(String uid, String placeId) async => null;
  @override
  Future<QueueReceipt?> reconcilePending(String uid, String placeId) async =>
      null;
  @override
  Future<QueueReceipt> createReport(
    NewQueueReport report, {
    Place? newPlace,
  }) async => throw UnimplementedError();
}
