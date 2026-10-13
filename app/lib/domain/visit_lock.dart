import 'models/day_period.dart';

/// Intervalo mínimo entre duas visitas ("Voltei aqui", F15) do mesmo usuário
/// no mesmo local. MESMO valor de `duration.value(12, 'h')` em
/// `firebase/firestore.rules` (`match /visitLocks`; teste de paridade em
/// test/domain/visit_lock_test.dart): as Rules são a garantia, o app só
/// evita um envio que seria negado.
const Duration visitCooldown = Duration(hours: 12);

/// Limite para ler a trava de visita (detalhe e sheet). Estourou: segue sem
/// trava e as Rules decidem no envio.
const Duration visitLockTimeout = Duration(seconds: 5);

/// A partir de quando o usuário pode registrar outra visita ao local
/// visitado em [lastAt] (hora do servidor).
DateTime visitAllowedAt(DateTime lastAt) => lastAt.add(visitCooldown);

/// Ainda dentro do intervalo? `null` (nunca registrou visita) nunca bloqueia.
bool isVisitBlocked(DateTime? lastAt, DateTime now) =>
    lastAt != null && now.isBefore(visitAllowedAt(lastAt));

/// "Você registrou uma visita em 12/10 às 20h. De novo a partir de 13/10
/// às 8h." (UTC-3; a liberação é arredondada para o minuto seguinte quando
/// há segundos, para nunca mostrar uma hora anterior à real).
String visitBlockedMessage(DateTime lastAt) =>
    'Você registrou uma visita em ${formatDayMonthHour(lastAt)}. '
    'De novo a partir de '
    '${formatDayMonthHour(ceilToMinute(visitAllowedAt(lastAt)))}.';
