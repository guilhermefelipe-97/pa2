import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/place.dart';
import '../repositories/place_repository.dart';

class FirestorePlaceRepository implements PlaceRepository {
  FirestorePlaceRepository(this._db);

  final FirebaseFirestore _db;

  @override
  Future<List<Place>> listPlaces() async {
    // Ordena no cliente: coleção pequena (seed) e evita depender do tipo do
    // campo no orderBy do servidor.
    final snap = await _db.collection('places').get();
    final places = <Place>[];
    for (final d in snap.docs) {
      final place = _fromData(d.id, d.data());
      if (place != null) places.add(place);
    }
    places.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return places;
  }

  /// Documento malformado (ex.: `name` ausente ou não-string) é ignorado em
  /// vez de derrubar a lista inteira.
  static Place? _fromData(String id, Map<String, dynamic> data) {
    final name = data['name'];
    if (name is! String || name.trim().isEmpty) return null;
    String optional(String key) {
      final v = data[key];
      return v is String ? v : '';
    }

    String? nonEmpty(String key) {
      final v = optional(key).trim();
      return v.isEmpty ? null : v;
    }

    return Place(
      id: id,
      name: name,
      category: optional('category'),
      neighborhood: optional('neighborhood'),
      city: optional('city'),
      photoUrl: nonEmpty('photoUrl'),
      photoAuthor: nonEmpty('photoAuthor'),
      photoLicense: nonEmpty('photoLicense'),
      photoIllustrative: data['photoIllustrative'] == true,
    );
  }
}
