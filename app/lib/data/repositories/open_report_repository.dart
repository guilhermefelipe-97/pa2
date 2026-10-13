import '../../domain/models/open_report.dart';
import '../../domain/models/place.dart';

/// Resultado de [OpenReportRepository.createReport].
typedef CreateOpenReportResult = ({bool placeCreated});

/// "Está aberto agora?" (F20): relatos de quem está no local.
abstract class OpenReportRepository {
  /// Grava `openReports/{id}` e cria ou renova a trava
  /// `users/{uid}/openReportLocks/{placeId}` num único batch: as Rules negam
  /// o relato dentro de `openReportCooldown` do anterior no mesmo local.
  ///
  /// Com [newPlace] (local só descoberto pelo Photon, G2) e sem doc em
  /// `places/{id}`, o local é criado no MESMO batch. Se outra pessoa o criou
  /// antes (corrida), o relato é gravado sem recriá-lo.
  /// [CreateOpenReportResult.placeCreated] diz se ESTA chamada criou o local.
  Future<CreateOpenReportResult> createReport(
    NewOpenReport report, {
    Place? newPlace,
  });

  /// Hora do último relato de [uid] no local (trava do F20), ou `null` sem
  /// trava. Lida do servidor; quem chama aplica o `openReportLockTimeout`.
  Future<DateTime?> openReportLockOf(String uid, String placeId);

  /// Relatos do local a partir de [since], mais recentes primeiro
  /// (`placeId ==` + `createdAt >=`, limitado).
  Future<List<OpenReport>> fetchForPlace(
    String placeId, {
    required DateTime since,
  });

  /// Relatos dos [placeIds] a partir de [since] (`placeId in` em lotes de
  /// 30), mais recentes primeiro.
  Future<List<OpenReport>> fetchForPlaces(
    List<String> placeIds, {
    required DateTime since,
  });
}
