import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../domain/models/place.dart';
import '../../domain/search_tokens.dart';
import '../chunk.dart';
import '../repositories/place_repository.dart';

class FirestorePlaceRepository implements PlaceRepository {
  FirestorePlaceRepository(this._db);

  final FirebaseFirestore _db;

  static const searchLimit = placeSearchLimit;

  /// Com termos extras (filtrados no cliente) a consulta traz mais candidatos
  /// para não esvaziar a página depois do filtro.
  static const _multiTermFetch = 60;

  /// Limite do `whereIn`.
  static const _whereInLimit = 30;

  /// `places` é somente leitura para o cliente: o que já foi lido (inclusive
  /// "não existe" → null) vale para a sessão inteira. Guardar o Future
  /// deduplica leituras em andamento.
  final Map<String, Future<Place?>> _byId = {};

  /// Ids que a última leitura deu como ausentes.
  final Set<String> _absent = {};
  List<Place>? _suggestions;

  /// Consultas `whereIn` feitas por [getPlaces] (para testes).
  @visibleForTesting
  int queryCount = 0;

  /// Id que pode ir ao `whereIn` de documentId (vazio ou com "/" lança).
  static bool _validId(String id) => id.isNotEmpty && !id.contains('/');

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('places');

  @override
  Future<List<Place>> search(String query) async {
    final terms = normalizeQuery(query);
    final term = serverTerm(terms);
    if (term == null) return const [];
    final others = [...terms]..remove(term);
    final snap = await _col
        .where('searchTokens', arrayContains: term)
        .orderBy('nameLower')
        .limit(others.isEmpty ? searchLimit : _multiTermFetch)
        .get();
    return _parse(
      snap.docs,
    ).where((p) => nameMatchesTerms(p.name, others)).take(searchLimit).toList();
  }

  @override
  Future<List<Place>> suggestions() async {
    final cached = _suggestions;
    if (cached != null) return cached;
    final snap = await _col.where('source', isEqualTo: 'curated').get();
    final list = _parse(snap.docs).where((p) => p.photoUrl != null).toList()
      ..sort((a, b) => nameLower(a.name).compareTo(nameLower(b.name)));
    return _suggestions = List.unmodifiable(list);
  }

  @override
  Future<Map<String, Place>> getPlaces(
    Iterable<String> ids, {
    bool refreshMissing = false,
  }) async {
    final wanted = ids.where(_validId).toSet();
    if (refreshMissing) {
      for (final id in wanted.where(_absent.contains).toList()) {
        _absent.remove(id);
        _byId.remove(id);
      }
    }
    final missing = wanted.where((id) => !_byId.containsKey(id)).toList()
      ..sort();
    for (final batch in chunked(missing, _whereInLimit)) {
      final fetch = _fetchBatch(batch);
      for (final id in batch) {
        _byId[id] = fetch.then((found) => found[id]);
      }
    }
    final entries = await Future.wait([
      for (final id in wanted) _byId[id]!.then((p) => MapEntry(id, p)),
    ]);
    return {for (final e in entries) e.key: ?e.value};
  }

  /// Uma consulta por lote. Em erro, os ids saem do cache (nova tentativa na
  /// próxima chamada) e o erro sobe.
  Future<Map<String, Place>> _fetchBatch(List<String> batch) async {
    queryCount++;
    try {
      final snap = await _col.where(FieldPath.documentId, whereIn: batch).get();
      final found = {for (final p in _parse(snap.docs)) p.id: p};
      _absent.addAll(batch.where((id) => !found.containsKey(id)));
      return found;
    } on Object {
      for (final id in batch) {
        _byId.remove(id);
      }
      rethrow;
    }
  }

  /// Converte e guarda no cache; documentos malformados ficam de fora.
  List<Place> _parse(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final out = <Place>[];
    for (final d in docs) {
      final place = placeFromData(d.id, d.data());
      if (place == null) continue;
      _byId[place.id] = Future.value(place);
      _absent.remove(place.id);
      out.add(place);
    }
    return out;
  }

  /// Documento malformado (ex.: `name` ausente ou não-string) é ignorado em
  /// vez de derrubar a lista inteira; campos opcionais com tipo errado viram
  /// ausentes.
  static Place? placeFromData(String id, Map<String, dynamic> data) {
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

    double? coordinate(String key, double max) {
      final v = data[key];
      if (v is! num) return null;
      final d = v.toDouble();
      return d.isFinite && d.abs() <= max ? d : null;
    }

    final lat = coordinate('lat', 90);
    final lng = coordinate('lng', 180);
    final hasCoords = lat != null && lng != null;

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
      lat: hasCoords ? lat : null,
      lng: hasCoords ? lng : null,
      cuisine: nonEmpty('cuisine'),
      address: nonEmpty('address'),
      openingHours: nonEmpty('openingHours'),
      osmId: nonEmpty('osmId'),
      source: PlaceSource.parse(data['source']),
    );
  }
}
