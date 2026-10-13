import '../domain/models/place_activity.dart';

/// Idas (avaliações ou visitas) lidas por autores em lotes, mais recentes
/// primeiro, e o corte que deixou os lotes consistentes entre si.
class ActivityBatch<T extends PlaceActivity> {
  const ActivityBatch(this.items, {this.cutoff});

  /// Mais recentes primeiro; nada anterior a [cutoff].
  final List<T> items;

  /// Antes deste instante a leitura pode estar incompleta (algum lote bateu
  /// o limite, ou o `limit` total cortou): nada anterior a ele foi mantido.
  /// `null` = completa.
  final DateTime? cutoff;
}

/// Um lote da consulta por autores: os docs válidos ([items]), o
/// `createdAt` bruto de TODOS os docs que o têm ([createdAts], inclusive os
/// que não passaram na leitura do schema) e quantos docs vieram
/// ([docCount]).
typedef RawBatch<T extends PlaceActivity> = ({
  List<T> items,
  List<DateTime> createdAts,
  int docCount,
});

/// Junta os lotes de uma consulta por autores. Um lote que bateu
/// [batchLimit] pode ter idas mais antigas que não vieram: o resultado é
/// cortado no mais recente dos "createdAt mais antigos" entre os lotes
/// cheios — medido nos docs brutos, para um doc fora do schema não esconder
/// o buraco. Com [limit], só as [limit] mais recentes no total (o corte passa
/// a ser a mais antiga mantida).
ActivityBatch<T> mergeAuthorBatches<T extends PlaceActivity>(
  Iterable<RawBatch<T>> batches, {
  required int batchLimit,
  int? limit,
}) {
  final byId = <String, T>{};
  DateTime? cutoff;
  for (final b in batches) {
    for (final item in b.items) {
      byId[item.id] = item;
    }
    if (b.docCount < batchLimit || b.createdAts.isEmpty) continue;
    final oldest = b.createdAts.reduce((a, c) => c.isBefore(a) ? c : a);
    if (cutoff == null || oldest.isAfter(cutoff)) cutoff = oldest;
  }
  final kept = keepFrom(byId.values, cutoff);
  if (limit == null || kept.length <= limit) {
    return ActivityBatch(kept, cutoff: cutoff);
  }
  final truncated = kept.sublist(0, limit);
  return ActivityBatch(truncated, cutoff: truncated.last.createdAt);
}

/// Remove idas anteriores a [cutoff] (quando houver) e ordena da mais
/// recente para a mais antiga.
List<T> keepFrom<T extends PlaceActivity>(Iterable<T> items, DateTime? cutoff) {
  final kept = cutoff == null
      ? items.toList()
      : items.where((r) => !r.createdAt.isBefore(cutoff)).toList();
  kept.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return kept;
}

/// Corte comum (F15): avaliações e visitas lidas em consultas separadas
/// têm cortes diferentes; para o feed e o Perto não misturarem uma janela
/// longa de uma com uma curta da outra, as duas param no mais recente dos
/// cortes.
DateTime? commonCutoff(Iterable<DateTime?> cutoffs) {
  DateTime? latest;
  for (final c in cutoffs) {
    if (c != null && (latest == null || c.isAfter(latest))) latest = c;
  }
  return latest;
}
