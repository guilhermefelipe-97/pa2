import 'geo.dart';
import 'models/day_period.dart';
import 'models/open_report.dart';

export 'models/open_report.dart';

/// Só relatos desta janela contam para o status (F20): depois disso o
/// status some (nunca se infere aberto/fechado sem relato recente).
const Duration openReportWindow = Duration(hours: 3);

/// Sim e Não dentro desta janela = "Informações divergentes".
const Duration openDivergenceWindow = Duration(minutes: 30);

/// Intervalo mínimo entre dois relatos do mesmo usuário no mesmo local.
/// MESMO valor de `duration.value(30, 'm')` em `firebase/firestore.rules`
/// (`match /openReportLocks`; teste de paridade em
/// test/domain/open_status_test.dart): as Rules são a garantia, o app só
/// evita um envio que seria negado.
const Duration openReportCooldown = Duration(minutes: 30);

/// O botão de relato só aparece com o aparelho a até esta distância do
/// local (checagem no cliente; a posição nunca é enviada).
const double openReportRadiusMeters = 150;

/// Limite para ler a trava de relato. Estourou: segue sem trava e as Rules
/// decidem no envio.
const Duration openReportLockTimeout = Duration(seconds: 5);

/// Máximo de relatos lidos no detalhe (os mais recentes da janela).
const int openReportsPlaceLimit = 50;

/// Máximo de relatos por lote de 30 locais no Perto.
const int openReportsBatchLimit = 300;

/// Início da janela de leitura dos relatos ([openReportWindow]).
DateTime openReportsSince(DateTime now) => now.subtract(openReportWindow);

/// O aparelho em [device] está perto o bastante de [place] para relatar.
bool isNearForOpenReport(LatLng device, LatLng place) =>
    distanceMeters(device, place) <= openReportRadiusMeters;

enum OpenStatusKind { open, closed, divergent }

/// Status exibido a partir dos relatos recentes de um local.
class OpenStatus {
  const OpenStatus({
    required this.kind,
    required this.latest,
    this.recentCount = 0,
  });

  final OpenStatusKind kind;

  /// Relato mais recente (quem confirmou/informou, e quando).
  final OpenReport latest;

  /// Relatos na última meia hora (usado em [OpenStatusKind.divergent]).
  final int recentCount;

  bool get isOpen => kind == OpenStatusKind.open;
}

/// [at] está a no máximo [window] de [now] (no futuro, relógio atrasado,
/// conta como agora).
bool _within(DateTime at, DateTime now, Duration window) =>
    now.difference(at) <= window;

/// Status de um local a partir dos [reports] dele: só os das últimas 3 h
/// contam; Sim e Não na última meia hora = divergente; senão o mais recente
/// vence. `null` = sem relato recente (nada é inferido).
OpenStatus? openStatusOf(Iterable<OpenReport> reports, DateTime now) {
  final recent =
      reports.where((r) => _within(r.createdAt, now, openReportWindow)).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  if (recent.isEmpty) return null;
  final latest = recent.first;
  final lastHalfHour = recent
      .where((r) => _within(r.createdAt, now, openDivergenceWindow))
      .toList();
  final hasYes = lastHalfHour.any((r) => r.open);
  final hasNo = lastHalfHour.any((r) => !r.open);
  if (hasYes && hasNo) {
    return OpenStatus(
      kind: OpenStatusKind.divergent,
      latest: latest,
      recentCount: lastHalfHour.length,
    );
  }
  return OpenStatus(
    kind: latest.open ? OpenStatusKind.open : OpenStatusKind.closed,
    latest: latest,
  );
}

/// Status por local, a partir de relatos de vários locais (Perto).
Map<String, OpenStatus> openStatusesByPlace(
  Iterable<OpenReport> reports,
  DateTime now,
) {
  final byPlace = <String, List<OpenReport>>{};
  for (final r in reports) {
    (byPlace[r.placeId] ??= []).add(r);
  }
  return {for (final e in byPlace.entries) e.key: ?openStatusOf(e.value, now)};
}

/// "agora", "há 20 min", "há 1 h" (dentro da janela de 3 h).
String _ago(DateTime at, DateTime now) {
  final d = now.difference(at);
  if (d.inMinutes < 1) return 'agora';
  if (d.inHours < 1) return 'há ${d.inMinutes} min';
  return 'há ${d.inHours} h';
}

String _agoSpoken(DateTime at, DateTime now) {
  final d = now.difference(at);
  if (d.inMinutes < 1) return 'agora';
  if (d.inHours < 1) {
    return d.inMinutes == 1 ? 'há 1 minuto' : 'há ${d.inMinutes} minutos';
  }
  return d.inHours == 1 ? 'há 1 hora' : 'há ${d.inHours} horas';
}

/// Quem relatou: "você" para o próprio usuário; nunca escondido (nome
/// vazio vira "Alguém").
String _who(OpenReport r, String? currentUserId) {
  if (currentUserId != null && r.authorId == currentUserId) return 'você';
  final name = r.authorName.trim();
  return name.isEmpty ? 'Alguém' : name;
}

String _reportsLabel(int n) => n == 1 ? '1 relato' : '$n relatos';

/// "Aberto · confirmado por Ana há 20 min", "Fechado · informado por Caio
/// há 1 h" ou "Informações divergentes · 2 relatos na última meia hora".
String openStatusLabel(
  OpenStatus status,
  DateTime now, {
  String? currentUserId,
}) {
  final r = status.latest;
  final who = _who(r, currentUserId);
  return switch (status.kind) {
    OpenStatusKind.open =>
      'Aberto · confirmado por $who ${_ago(r.createdAt, now)}',
    OpenStatusKind.closed =>
      'Fechado · informado por $who ${_ago(r.createdAt, now)}',
    OpenStatusKind.divergent =>
      'Informações divergentes · '
          '${_reportsLabel(status.recentCount)} na última meia hora',
  };
}

/// O mesmo, por extenso para leitores de tela.
String openStatusSemantics(
  OpenStatus status,
  DateTime now, {
  String? currentUserId,
}) {
  final r = status.latest;
  final who = _who(r, currentUserId);
  return switch (status.kind) {
    OpenStatusKind.open =>
      'Aberto agora, confirmado por $who ${_agoSpoken(r.createdAt, now)}',
    OpenStatusKind.closed =>
      'Fechado, informado por $who ${_agoSpoken(r.createdAt, now)}',
    OpenStatusKind.divergent =>
      'Informações divergentes: '
          '${_reportsLabel(status.recentCount)} na última meia hora',
  };
}

/// A partir de quando o usuário pode relatar de novo o local relatado em
/// [lastAt] (hora do servidor).
DateTime openReportAllowedAt(DateTime lastAt) => lastAt.add(openReportCooldown);

/// Ainda dentro do intervalo? `null` (nunca relatou) nunca bloqueia.
bool isOpenReportBlocked(DateTime? lastAt, DateTime now) =>
    lastAt != null && now.isBefore(openReportAllowedAt(lastAt));

/// "às 20h10" / "à 1h" (UTC-3).
String _atHour(DateTime t) {
  final h = formatHour(t);
  return h.startsWith('1h') ? 'à $h' : 'às $h';
}

/// "das 20h40" / "da 1h" (UTC-3).
String _fromHour(DateTime t) {
  final h = formatHour(t);
  return h.startsWith('1h') ? 'da $h' : 'das $h';
}

/// "Você informou às 20h10. De novo a partir das 20h40." (UTC-3; a
/// liberação é arredondada para o minuto seguinte quando há segundos).
String openReportBlockedMessage(DateTime lastAt) =>
    'Você informou ${_atHour(lastAt)}. '
    'De novo a partir ${_fromHour(ceilToMinute(openReportAllowedAt(lastAt)))}.';
