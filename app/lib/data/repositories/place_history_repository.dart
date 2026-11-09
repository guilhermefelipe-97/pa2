import '../../domain/models/review.dart';
import '../../domain/models/visit.dart';

/// Histórico completo de um local a partir de uma data (F23 e F26), de
/// todas as pessoas, incluindo atividade silenciosa (F16), que só não
/// aparece no feed Amigos. Leitura paginada da janela inteira.
abstract class PlaceHistoryRepository {
  /// Avaliações de [placeId] criadas a partir de [since], mais recentes primeiro.
  Future<List<Review>> reviewsSince(String placeId, DateTime since);

  /// "Voltei aqui" de [placeId] criados a partir de [since], mais recentes primeiro.
  Future<List<Visit>> visitsSince(String placeId, DateTime since);
}
