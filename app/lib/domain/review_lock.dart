import 'models/day_period.dart';

/// Período mínimo entre duas avaliações do mesmo usuário no mesmo local
/// (F03; Fase 1, "Não faz"). MESMO valor de `duration.value(30, 'd')` em
/// `firebase/firestore.rules` (`match /reviewLocks`; teste de paridade em
/// test/domain/review_lock_test.dart): as Rules são a garantia, o app só
/// evita abrir um formulário que seria negado.
const Duration reviewCooldown = Duration(days: 30);

/// Limite para ler a trava (formulário e detalhe). Estourou: segue sem
/// trava e as Rules decidem no envio.
const Duration reviewLockTimeout = Duration(seconds: 5);

/// A partir de quando o usuário pode avaliar de novo o local avaliado em
/// [lastAt] (a hora da última avaliação, do servidor).
DateTime reviewAllowedAt(DateTime lastAt) => lastAt.add(reviewCooldown);

/// Ainda dentro do período mínimo? `null` (sem trava: nunca avaliou ou só
/// tem avaliação anterior ao F03 sem backfill) nunca bloqueia.
bool isReviewBlocked(DateTime? lastAt, DateTime now) =>
    lastAt != null && now.isBefore(reviewAllowedAt(lastAt));

/// Arredonda para o minuto seguinte quando há segundos: a hora exibida nunca
/// é anterior à liberação real.
DateTime _ceilToMinute(DateTime t) {
  final floor = DateTime.fromMicrosecondsSinceEpoch(
    t.microsecondsSinceEpoch -
        t.microsecondsSinceEpoch % Duration.microsecondsPerMinute,
    isUtc: true,
  );
  return floor.isBefore(t.toUtc())
      ? floor.add(const Duration(minutes: 1))
      : floor;
}

/// "Pode avaliar de novo a partir de 11/11 às 20h" (UTC-3).
String reviewAgainFromLabel(DateTime lastAt) =>
    'Pode avaliar de novo a partir de '
    '${formatDayMonthHour(_ceilToMinute(reviewAllowedAt(lastAt)))}';

/// "Você avaliou este lugar em 12/10. Pode avaliar de novo a partir de
/// 11/11 às 20h." (UTC-3).
String reviewBlockedMessage(DateTime lastAt) =>
    'Você avaliou este lugar em ${formatDayMonth(lastAt)}. '
    '${reviewAgainFromLabel(lastAt)}.';
