import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../domain/geo.dart';
import '../../domain/models/place.dart';
import '../../domain/search_tokens.dart';
import '../chunk.dart';
import '../repositories/place_repository.dart';
import 'place_doc.dart';

class FirestorePlaceRepository implements PlaceRepository {
  FirestorePlaceRepository(this._db);

  final FirebaseFirestore _db;

  static const searchLimit = placeSearchLimit;

  /// Com termos extras (filtrados no cliente) a consulta traz mais candidatos
  /// para não esvaziar a página depois do filtro.
  static const _multiTermFetch = 60;

  /// O cliente nunca edita `places` (só cria, G2): o que já foi lido
  /// (inclusive "não existe" → null) vale para a sessão inteira, até
  /// [markPersisted]/[ensurePersisted]. Guardar o Future
  /// deduplica leituras em andamento.
  final Map<String, Future<Place?>> _byId = {};

  /// Ids que a última leitura deu como ausentes.
  final Set<String> _absent = {};
  List<Place>? _suggestions;

  /// Máximo de documentos por faixa de geohash em [nearby]. O catálogo tem
  /// ~650 locais; a faixa mais larga (3 km) cabe folgada.
  static const nearbyLimitPerRange = 200;

  /// Faixas de geohash consultadas por [nearby] (para testes).
  @visibleForTesting
  int nearbyRangeCount = 0;

  /// Consultas `whereIn` feitas por [getPlaces] (para testes).
  @visibleForTesting
  int queryCount = 0;

  /// Id que pode ir ao `whereIn` de documentId (vazio ou com "/" lança).
  static bool _validId(String id) => id.isNotEmpty && !id.contains('/');

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(placesCollection);

  /// Criações em andamento por id (dedupe de toques/telas simultâneos).
  final Map<String, Future<void>> _creating = {};

  /// Documentos criados por [ensurePersisted] (para testes).
  @visibleForTesting
  int createCount = 0;

  @override
  Future<List<Place>> search(String query, {LatLng? near}) async {
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
  Future<NearbyResult> nearby(
    double lat,
    double lng,
    double radiusMeters,
  ) async {
    final center = (lat: lat, lng: lng);
    final ranges = geohashQueryBounds(center, radiusMeters);
    nearbyRangeCount += ranges.length;
    final snaps = await Future.wait([
      for (final r in ranges)
        // Igual a `orderBy + startAt/endAt` do geofire; docs sem `geohash`
        // (sem coordenadas) nunca entram numa faixa.
        _col
            .where('geohash', isGreaterThanOrEqualTo: r.start)
            .where('geohash', isLessThanOrEqualTo: r.end)
            .orderBy('geohash')
            .limit(nearbyLimitPerRange)
            .get(),
    ]);
    final seen = <String>{};
    final out = <NearbyPlace>[];
    for (final snap in snaps) {
      for (final p in _parse(snap.docs)) {
        if (!seen.add(p.id) || !p.hasCoordinates) continue;
        // O geohash só escolhe candidatos; quem decide é a distância real
        // sobre lat/lng (um geohash forjado não põe ninguém no raio).
        final d = distanceMeters(center, (lat: p.lat!, lng: p.lng!));
        if (d <= radiusMeters) out.add((place: p, distanceMeters: d));
      }
    }
    return NearbyResult(out..sort(compareNearby));
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
    for (final batch in chunked(missing, whereInLimit)) {
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

  @override
  Future<void> ensurePersisted(Place place, {required String uid}) {
    if (!place.discovered) return Future.value();
    final running = _creating[place.id];
    if (running != null) return running;
    final future = _create(place, uid).whenComplete(() {
      _creating.remove(place.id);
    });
    _creating[place.id] = future;
    return future;
  }

  Future<void> _create(Place place, String uid) async {
    final ref = _col.doc(place.id);
    // Já existe (seed, outra pessoa ou outra tela): usa o que está lá. Se a
    // leitura falhar, tenta criar assim mesmo (as Rules impedem duplicar).
    bool? exists;
    try {
      exists = await _readExisting(ref);
    } on Object {
      exists = null;
    }
    if (exists == true) return;
    try {
      createCount++;
      await ref.set(newPlaceData(place, uid: uid));
    } on Object catch (error, stack) {
      // Corrida: alguém criou entre a leitura e a escrita (o create virou
      // update, negado). Se o doc está lá (no servidor), segue.
      try {
        if (await _readExisting(ref, fromServer: true)) return;
      } on Object {
        // A releitura também falhou: o erro que importa é o da criação.
      }
      Error.throwWithStackTrace(error, stack);
    }
    markPersisted(place);
  }

  /// Lê `places/{id}`; se existir, guarda no cache e devolve `true`. Doc
  /// existente mas malformado: limpa o cache do id (a próxima leitura tenta
  /// de novo) e também devolve `true` — ele existe, não há o que criar.
  Future<bool> _readExisting(
    DocumentReference<Map<String, dynamic>> ref, {
    bool fromServer = false,
  }) async {
    final snap = fromServer
        ? await ref.get(const GetOptions(source: Source.server))
        : await ref.get();
    final data = snap.data();
    if (!snap.exists || data == null) return false;
    final existing = placeFromData(ref.id, data);
    if (existing != null) {
      _byId[existing.id] = Future.value(existing);
      _absent.remove(existing.id);
    } else {
      invalidate(ref.id);
    }
    return true;
  }

  @override
  void invalidate(String placeId) {
    _byId.remove(placeId);
    _absent.remove(placeId);
  }

  /// Os gravados nunca são "descobertos".
  @override
  Place? discoveredPlace(String placeId) => null;

  @override
  void markPersisted(Place place) {
    _byId[place.id] = Future.value(place.asPersisted());
    _absent.remove(place.id);
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
      geohash: hasCoords ? nonEmpty('geohash') : null,
      cuisine: nonEmpty('cuisine'),
      address: nonEmpty('address'),
      openingHours: nonEmpty('openingHours'),
      osmId: nonEmpty('osmId'),
      source: PlaceSource.parse(data['source']),
    );
  }
}
