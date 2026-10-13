import 'package:flutter/foundation.dart';

import '../../data/activity_batch.dart';
import '../../data/repositories/review_repository.dart';
import '../../data/repositories/visit_repository.dart';
import '../../domain/models/place_activity.dart';

/// Resultado de [loadVisitsOrEmpty]: as visitas lidas (vazias se falhou) e
/// se a leitura deu certo.
typedef VisitsRead = ({ActivityBatch<Visit> batch, bool ok});

/// Lê visitas ("Voltei aqui", F15) sem derrubar a tela: as visitas são um
/// sinal a mais sobre as avaliações, então a falha vira "nenhuma visita"
/// (`ok: false`, registrada com `debugPrint`) e quem chama decide se guarda
/// o resultado (o Perto não guarda; o detalhe mantém as anteriores). Usado
/// pelo feed, Perto, perfil e detalhe.
Future<VisitsRead> loadVisitsOrEmpty(
  String where,
  Future<ActivityBatch<Visit>> Function() read,
) async {
  try {
    return (batch: await read(), ok: true);
  } on Object catch (e) {
    debugPrint('Visitas indisponíveis ($where): $e');
    return (batch: const ActivityBatch<Visit>([]), ok: false);
  }
}

/// Idas (avaliações + visitas) de [authors] para o feed e o Perto, com o
/// corte comum das duas leituras ([commonCutoff]): nada anterior ao mais
/// recente dos cortes, para uma consulta não mostrar uma janela de tempo
/// maior que a outra. Falha das avaliações sobe; das visitas, vira
/// `visitsOk: false` (só avaliações).
Future<({List<PlaceActivity> activities, bool visitsOk})> loadFriendActivities({
  required ReviewRepository reviews,
  required VisitRepository visits,
  required List<String> authors,
  required String where,
}) async {
  final visitsRead = loadVisitsOrEmpty(
    where,
    () => visits.fetchVisitsByAuthors(authors),
  );
  final reviewBatch = await reviews.fetchReviewsByAuthors(authors);
  final visitBatch = await visitsRead;
  final cut = commonCutoff([reviewBatch.cutoff, visitBatch.batch.cutoff]);
  return (
    activities: <PlaceActivity>[
      ...keepFrom(reviewBatch.items, cut),
      ...keepFrom(visitBatch.batch.items, cut),
    ],
    visitsOk: visitBatch.ok,
  );
}
