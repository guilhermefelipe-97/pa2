import '../../domain/models/place.dart';
import '../../domain/models/visit.dart';
import '../activity_batch.dart';

/// Resultado de [VisitRepository.createVisit].
typedef CreateVisitResult = ({bool placeCreated});

/// "Voltei aqui" (F15): visitas sem nota, que contam como recorrência.
abstract class VisitRepository {
  /// Grava `visits/{id}` e cria ou renova a trava
  /// `users/{uid}/visitLocks/{placeId}` num único batch: as Rules negam a
  /// visita dentro de `visitCooldown` da anterior no mesmo local.
  ///
  /// Com [newPlace] (local só descoberto pelo Photon, G2) e sem doc em
  /// `places/{id}`, o local é criado no MESMO batch. Se outra pessoa o criou
  /// antes (corrida), a visita é gravada sem recriá-lo, com o nome gravado.
  /// [CreateVisitResult.placeCreated] diz se ESTA chamada criou o local.
  Future<CreateVisitResult> createVisit(NewVisit visit, {Place? newPlace});

  /// Hora da última visita de [uid] ao local (trava do F15), ou `null` sem
  /// trava. Lida do servidor; quem chama aplica o `visitLockTimeout`.
  Future<DateTime?> visitLockOf(String uid, String placeId);

  /// Visitas dos [authorIds], mais recentes primeiro (lotes de 30 no
  /// `whereIn`, com o mesmo corte consistente das avaliações, exposto em
  /// [ActivityBatch.cutoff]). Com [limit], só as [limit] mais recentes.
  Future<ActivityBatch<Visit>> fetchVisitsByAuthors(
    List<String> authorIds, {
    int? limit,
  });

  /// Visitas de [authorIds] no local, mais recentes primeiro (filtro no
  /// servidor: `placeId ==` + `authorId in`).
  Future<List<Visit>> fetchVisitsForPlace(
    String placeId,
    List<String> authorIds,
  );
}
