import 'dart:typed_data';

import '../../domain/models/place.dart';
import '../../domain/models/review.dart';

/// Resultado de [ReviewRepository.createReview].
typedef CreateReviewResult = ({bool placeCreated});

abstract class ReviewRepository {
  /// Limite do operador `whereIn` do Firestore.
  static const int whereInLimit = 30;

  /// Grava a avaliação. Com [photo] (JPEG já recodificado, ≤ 150.000 bytes),
  /// grava `reviews/{id}` com `hasPhoto: true` e `reviewPhotos/{id}` num único
  /// batch: ou as duas, ou nenhuma.
  ///
  /// Com [newPlace] (local só descoberto pelo Photon, G2) e sem doc em
  /// `places/{id}`, o local é criado no MESMO batch (as Rules exigem o local
  /// ao fim do batch). Se outra pessoa o criou antes (corrida), a avaliação
  /// é gravada sem recriá-lo — com o nome que está gravado no local.
  /// [CreateReviewResult.placeCreated] diz se ESTA chamada criou o local.
  /// Também cria ou renova a trava do F03
  /// (`users/{uid}/reviewLocks/{placeId}`) no mesmo batch: as Rules negam a
  /// avaliação dentro de `reviewCooldown` da anterior no mesmo local.
  Future<CreateReviewResult> createReview(
    NewReview review, {
    Uint8List? photo,
    Place? newPlace,
  });

  /// Hora da última avaliação de [uid] no local (trava do F03), ou `null`
  /// quando não há trava (nunca avaliou, ou só antes do F03 sem backfill).
  /// Lida do servidor; quem chama aplica o `reviewLockTimeout`.
  Future<DateTime?> reviewLockOf(String uid, String placeId);

  /// Avaliações dos [authorIds], mais recentes primeiro. Com [limit], só as
  /// [limit] mais recentes no total (ex.: o perfil mostra as 50 últimas).
  Future<List<Review>> fetchReviewsByAuthors(
    List<String> authorIds, {
    int? limit,
  });

  /// Avaliações de [authorIds] no local, mais recentes primeiro. Filtra no
  /// servidor (`placeId ==` + `authorId in`, lotes de [whereInLimit]): não
  /// lê avaliações de terceiros e não perde as de amigos mais antigas.
  Future<List<Review>> fetchReviewsForPlace(
    String placeId,
    List<String> authorIds,
  );
}
