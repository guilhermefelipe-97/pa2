import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../repositories/auth_repository.dart';
import '../repositories/profile_media_repository.dart';

class FirestoreProfileMediaRepository extends ProfileMediaRepository {
  FirestoreProfileMediaRepository(this.db, this.auth) {
    auth.addListener(_sessionChanged);
  }
  final FirebaseFirestore db;
  final AuthRepository auth;
  final _cache = <String, Uint8List?>{};
  final _pending = <String, Future<Uint8List?>>{};
  int _generation = 0;
  void _sessionChanged() {
    _generation++;
    _cache.clear();
    _pending.clear();
    notifyListeners();
  }

  @override
  Future<Uint8List?> get(String uid, String kind) async {
    if (!['avatar', 'cover'].contains(kind)) throw ArgumentError.value(kind);
    final key = '$uid/$kind';
    if (_cache.containsKey(key)) {
      final value = _cache.remove(key);
      _cache[key] = value;
      return value;
    }
    if (_pending.containsKey(key)) return _pending[key];
    final generation = _generation;
    final request = db.doc('users/$uid/media/$kind').get().then((doc) {
      if (generation != _generation) return null;
      final blob = doc.data()?['jpeg'];
      final bytes = blob is Blob ? blob.bytes : null;
      _cache[key] = bytes;
      while (_cache.length > 60) {
        _cache.remove(_cache.keys.first);
      }
      return bytes;
    });
    _pending[key] = request;
    try {
      return await request;
    } finally {
      if (generation == _generation) _pending.remove(key);
    }
  }

  @override
  void invalidate(String uid) {
    _generation++;
    _cache.remove('$uid/avatar');
    _cache.remove('$uid/cover');
    _pending.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    auth.removeListener(_sessionChanged);
    super.dispose();
  }
}
