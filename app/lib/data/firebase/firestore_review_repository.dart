import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/companion.dart';
import '../../domain/models/place.dart';
import '../../domain/models/review.dart';
import '../../domain/models/scores.dart';
import '../../domain/photo_compression.dart';
import '../chunk.dart';
import '../repositories/review_repository.dart';
import 'place_doc.dart';

class FirestoreReviewRepository implements ReviewRepository {
  FirestoreReviewRepository(
    this._db, {
    this.perBatchLimit = defaultPerBatchLimit,
  });

  final FirebaseFirestore _db;

  static const int defaultPerBatchLimit = 100;

  /// Limite por lote na consulta do feed.
  final int perBatchLimit;

  /// Coleção das fotos (bytes no Firestore; id = id da avaliação).
  static const String reviewPhotosCollection = 'reviewPhotos';

  /// Subcoleção das travas do F03: `users/{uid}/reviewLocks/{placeId}`.
  static const String reviewLocksCollection = 'reviewLocks';

  CollectionReference<Map<String, dynamic>> get _reviews =>
      _db.collection('reviews');

  DocumentReference<Map<String, dynamic>> _lockRef(
    String uid,
    String placeId,
  ) => _db
      .collection('users')
      .doc(uid)
      .collection(reviewLocksCollection)
      .doc(placeId);

  @override
  Future<DateTime?> reviewLockOf(String uid, String placeId) async {
    // Do servidor: a trava muda fora deste aparelho (outro aparelho, corrida)
    // e um cache velho abriria um formulário que as Rules negam.
    final snap = await _lockRef(
      uid,
      placeId,
    ).get(const GetOptions(source: Source.server));
    final lastAt = snap.data()?['lastAt'];
    return lastAt is Timestamp ? lastAt.toDate() : null;
  }

  @override
  Future<CreateReviewResult> createReview(
    NewReview review, {
    Uint8List? photo,
    Place? newPlace,
  }) async {
    if (photo != null && (photo.isEmpty || photo.length > maxPhotoBytes)) {
      throw ArgumentError.value(
        photo.length,
        'photo',
        'precisa ter de 1 a $maxPhotoBytes bytes',
      );
    }
    if (newPlace != null && newPlace.id != review.placeId) {
      throw ArgumentError.value(newPlace.id, 'newPlace', 'outro local');
    }
    // Id gerado no cliente: a foto usa o mesmo id da avaliação.
    final ref = _reviews.doc();
    final placeRef = newPlace != null && newPlace.discovered
        ? _db.collection(placesCollection).doc(newPlace.id)
        : null;
    var placeName = review.placeName;
    var createPlace = false;
    if (placeRef != null) {
      try {
        final existing = await placeRef.get();
        createPlace = !existing.exists;
        // O local já existe (outra pessoa criou; nome do OSM pode ter mudado
        // desde então): as Rules exigem o `name` do doc gravado.
        placeName = _storedName(existing) ?? placeName;
      } on Object {
        // Sem ler, tenta criar: se já existir, o batch falha e o ramo de
        // corrida abaixo resolve.
        createPlace = true;
      }
    }
    try {
      await _commit(
        ref,
        review,
        placeName,
        photo,
        createPlace ? newPlace : null,
      );
      return (placeCreated: createPlace);
    } on Object catch (error, stack) {
      // Ack perdido: o batch foi gravado (review + trava) mas a resposta não
      // chegou. Reenviar com o mesmo id seria negado (a review já existe e a
      // trava acabou de nascer); o caminho certo é reler a própria review e,
      // se ela existe, concluir com sucesso.
      if (await _existsOnServer(ref) == true) {
        return (placeCreated: createPlace);
      }
      if (!createPlace) Error.throwWithStackTrace(error, stack);
      // Corrida: o local nasceu entre a leitura e o commit (o set dele virou
      // update, negado, e derrubou o batch). Com o doc lá, grava sem ele, com
      // o nome que está gravado.
      final DocumentSnapshot<Map<String, dynamic>> existing;
      try {
        existing = await placeRef!.get(const GetOptions(source: Source.server));
      } on Object {
        // A releitura falhou: o erro que importa é o do commit.
        Error.throwWithStackTrace(error, stack);
      }
      if (!existing.exists) Error.throwWithStackTrace(error, stack);
      placeName = _storedName(existing) ?? placeName;
      await _commit(ref, review, placeName, photo, null);
      return (placeCreated: false);
    }
  }

  static String? _storedName(DocumentSnapshot<Map<String, dynamic>> snap) {
    final name = snap.data()?['name'];
    return snap.exists && name is String ? name : null;
  }

  /// `true`/`false` lido no servidor; `null` se a leitura falhou.
  static Future<bool?> _existsOnServer(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    try {
      return (await ref.get(const GetOptions(source: Source.server))).exists;
    } on Object {
      return null;
    }
  }

  Future<void> _commit(
    DocumentReference<Map<String, dynamic>> ref,
    NewReview review,
    String placeName,
    Uint8List? photo,
    Place? createPlace,
  ) {
    final batch = _db.batch();
    if (createPlace != null) {
      // Mesmo batch: as Rules da review exigem o local ao fim dele.
      batch.set(
        _db.collection(placesCollection).doc(createPlace.id),
        newPlaceData(createPlace, uid: review.authorId),
      );
    }
    // Schema exato (11 chaves) validado pelas Rules (hasOnly/hasAll). O período
    // do dia NÃO é gravado; createdAt é sempre o timestamp do servidor.
    // Eixo não avaliado vai como null (F14): a chave está sempre presente.
    // `comment` já vem normalizado (aparado; null quando não há).
    batch.set(ref, {
      'authorId': review.authorId,
      'authorName': review.authorName,
      'placeId': review.placeId,
      'placeName': placeName,
      'food': review.scores.food,
      'ambience': review.scores.ambience,
      'service': review.scores.service,
      'companion': review.companion?.value,
      'comment': review.comment,
      'hasPhoto': photo != null,
      'createdAt': FieldValue.serverTimestamp(),
    });
    if (photo != null) {
      // As Rules só aceitam a foto no mesmo batch da review nova do mesmo id.
      batch.set(_db.collection(reviewPhotosCollection).doc(ref.id), {
        'authorId': review.authorId,
        'jpeg': Blob(photo),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    // F03: trava criada/renovada no mesmo batch, apontando para esta
    // avaliação. Dentro dos 30 dias as Rules negam a trava e a review juntas.
    // Retry: só acontece quando a review NÃO foi gravada (ver createReview),
    // então o mesmo id ainda é novo para as Rules.
    // Offline: o batch fica enfileirado no cache local e o commit só conclui
    // ao sincronizar; até lá a trava não existe no servidor (outro aparelho
    // ainda pode avaliar) e, se as Rules negarem na sincronização, o SDK
    // desfaz as escritas locais.
    batch.set(_lockRef(review.authorId, review.placeId), {
      'lastAt': FieldValue.serverTimestamp(),
      'reviewId': ref.id,
      'placeId': review.placeId,
    });
    return batch.commit();
  }

  @override
  Future<List<Review>> fetchReviewsByAuthors(
    List<String> authorIds, {
    int? limit,
  }) async {
    assert(limit == null || limit > 0);
    final ids = authorIds.toSet().toList();
    if (ids.isEmpty) return [];
    // Cada lote traz as suas `batchLimit` mais recentes: as `limit` mais
    // recentes do total estão sempre na união.
    final batchLimit = limit == null || limit > perBatchLimit
        ? perBatchLimit
        : limit;
    final batches = chunked(ids, ReviewRepository.whereInLimit);
    final snaps = await Future.wait(
      batches.map(
        (batch) => _reviews
            .where('authorId', whereIn: batch)
            .orderBy('createdAt', descending: true)
            .limit(batchLimit)
            .get(),
      ),
    );
    final byId = <String, Review>{};
    // Um lote que bateu o limite pode ter avaliações mais antigas que não
    // vieram. Para os lotes ficarem consistentes entre si, corta o resultado
    // no mais recente dos "createdAt mais antigos" entre os lotes cheios.
    DateTime? cutoff;
    for (final snap in snaps) {
      DateTime? oldestInBatch;
      for (final doc in snap.docs) {
        final r = _fromDoc(doc);
        if (r == null) continue;
        byId[r.id] = r;
        if (oldestInBatch == null || r.createdAt.isBefore(oldestInBatch)) {
          oldestInBatch = r.createdAt;
        }
      }
      if (snap.docs.length >= batchLimit && oldestInBatch != null) {
        if (cutoff == null || oldestInBatch.isAfter(cutoff)) {
          cutoff = oldestInBatch;
        }
      }
    }
    final result = applyBatchCutoff(byId.values, cutoff);
    return limit == null || result.length <= limit
        ? result
        : result.sublist(0, limit);
  }

  @override
  Future<List<Review>> fetchReviewsForPlace(
    String placeId,
    List<String> authorIds,
  ) async {
    final ids = authorIds.toSet().toList();
    if (ids.isEmpty) return [];
    final snaps = await Future.wait(
      chunked(ids, ReviewRepository.whereInLimit).map(
        (batch) => _reviews
            .where('placeId', isEqualTo: placeId)
            .where('authorId', whereIn: batch)
            .orderBy('createdAt', descending: true)
            .get(),
      ),
    );
    final byId = {
      for (final snap in snaps)
        for (final r in snap.docs.map(_fromDoc).whereType<Review>()) r.id: r,
    };
    return applyBatchCutoff(byId.values, null);
  }

  /// Remove avaliações anteriores a [cutoff] (quando houver) e ordena da mais
  /// recente para a mais antiga.
  static List<Review> applyBatchCutoff(
    Iterable<Review> reviews,
    DateTime? cutoff,
  ) {
    final kept = cutoff == null
        ? reviews.toList()
        : reviews.where((r) => !r.createdAt.isBefore(cutoff)).toList();
    kept.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return kept;
  }

  /// Leitura estrita de um eixo (F14), espelhando as Rules: a chave precisa
  /// existir e valer `null` (não avaliado) ou um `int` de 1 a 5. Chave
  /// ausente, decimal (4.5) ou texto invalida o doc (ignorado em [_fromDoc]).
  /// Os 3 null também: `Scores` exige ao menos um eixo.
  static int? _axis(Map<String, dynamic> d, String key) {
    if (!d.containsKey(key)) throw FormatException('eixo "$key" ausente');
    final v = d[key];
    if (v == null) return null;
    if (v is int && Scores.isValid(v)) return v;
    throw FormatException('eixo "$key" inválido: $v');
  }

  Review? _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final ts = d['createdAt'];
    if (ts is! Timestamp) return null;
    try {
      return Review(
        id: doc.id,
        authorId: d['authorId'] as String,
        authorName: d['authorName'] as String,
        placeId: d['placeId'] as String,
        placeName: d['placeName'] as String,
        scores: Scores(
          food: _axis(d, 'food'),
          ambience: _axis(d, 'ambience'),
          service: _axis(d, 'service'),
        ),
        companion: Companion.fromValue(d['companion'] as String?),
        // Normaliza na leitura: avaliações da Onda 1 não têm a chave, e vazio
        // ou só espaços vira null (a UI nunca mostra citação vazia).
        comment: Review.normalizeComment(
          d['comment'] is String ? d['comment'] as String : null,
        ),
        createdAt: ts.toDate(),
        // Reviews anteriores ao G1 não têm a chave: sem foto.
        hasPhoto: d['hasPhoto'] == true,
      );
    } on Object {
      // Documento fora do schema: ignora em vez de derrubar o feed.
      return null;
    }
  }
}
