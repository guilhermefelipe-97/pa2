import 'package:flutter/foundation.dart';

abstract class ProfileMediaRepository extends ChangeNotifier {
  Future<Uint8List?> get(String uid, String kind);
  void invalidate(String uid);
}
