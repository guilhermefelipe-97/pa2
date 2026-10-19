import 'package:flutter/foundation.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/open_report_repository.dart';
import '../../data/repositories/review_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/services/location_service.dart';
import '../../domain/decision.dart';
import '../../domain/geo.dart';
import '../../domain/models/companion.dart';
import '../../domain/models/place_activity.dart';
import '../../domain/open_status.dart';
import '../core/safe_change_notifier.dart';

enum DecisionPhase {
  /// Toque 1 feito: escolhendo a companhia.
  choosing,

  /// Companhia escolhida, sinais ainda chegando.
  loading,

  /// Um lugar na tela.
  result,

  /// Todos os candidatos com "Fechado" relatado (ou nenhum candidato).
  noneOpen,
}

/// Sinais lidos para o ranking. Cada um é opcional: a leitura que falhar
/// vira "sem sinal" e o critério dela é ignorado.
typedef _Signals = ({
  List<Review> reviews,
  Map<String, OpenStatus> openStatuses,
  LatLng? position,
});

/// Modo decisão (F09): "Decidir por mim" no Quero ir. Toque 1 abre a escolha
/// de companhia (e já começa a ler os sinais); toque 2 escolhe e mostra 1
/// lugar dos salvos do chip ativo, com "Outra opção".
///
/// Sinais: avaliações de quem o usuário segue (`fetchReviewsByAuthors`,
/// mesmo padrão do feed e do Perto), relatos "Está aberto agora?" e a
/// última posição conhecida, SÓ se a permissão já existe (nunca pede).
class DecisionViewModel extends SafeChangeNotifier {
  DecisionViewModel({
    required List<DecisionCandidate> candidates,
    required AuthRepository authRepository,
    required UserRepository userRepository,
    required ReviewRepository reviewRepository,
    OpenReportRepository? openReportRepository,
    LocationService? locationService,
    DateTime Function()? clock,
  }) : _candidates = List.unmodifiable(candidates),
       _auth = authRepository,
       _users = userRepository,
       _reviews = reviewRepository,
       _openReports = openReportRepository,
       _location = locationService,
       _clock = clock ?? DateTime.now;

  static const noneOpenText = 'Nenhum lugar desta lista está aberto agora';
  static const wrappedText = 'Essas eram todas as opções';

  final List<DecisionCandidate> _candidates;
  final AuthRepository _auth;
  final UserRepository _users;
  final ReviewRepository _reviews;
  final OpenReportRepository? _openReports;
  final LocationService? _location;
  final DateTime Function() _clock;

  DecisionPhase _phase = DecisionPhase.choosing;
  DecisionPhase get phase => _phase;

  Future<_Signals>? _signals;

  Companion? _companion;

  /// Companhia escolhida (`null` = "Tanto faz").
  Companion? get companion => _companion;

  DateTime? _decidedAt;
  List<DecisionOption> _options = const [];

  /// Do melhor para o pior (vazio antes do toque 2 ou se todos fechados).
  List<DecisionOption> get options => _options;

  int _index = 0;

  /// "Outra opção" passou do último e voltou ao 1º.
  bool _wrapped = false;
  bool get wrapped => _wrapped;

  /// Lugar exibido.
  DecisionOption? get current =>
      _phase == DecisionPhase.result && _options.isNotEmpty
      ? _options[_index]
      : null;

  /// Motivo do lugar exibido (do critério que desempatou).
  String? get reason {
    final o = current;
    final at = _decidedAt;
    if (o == null || at == null) return null;
    return decisionReason(o, companion: _companion, now: at);
  }

  int _seq = 0;

  /// Começa a ler os sinais (no toque 1, enquanto a pessoa escolhe a
  /// companhia). Chamadas repetidas reusam a mesma leitura.
  Future<void> prepare() => _signals ??= _loadSignals();

  /// Toque 2: escolhe a companhia (`null` = "Tanto faz") e ranqueia.
  Future<void> choose(Companion? companion) async {
    final seq = ++_seq;
    _companion = companion;
    _phase = DecisionPhase.loading;
    notifyListeners();
    final signals = await (_signals ??= _loadSignals());
    if (seq != _seq || isDisposed) return;
    final now = _clock();
    _decidedAt = now;
    _options = rankDecision(
      candidates: _candidates,
      followedReviews: signals.reviews,
      companion: companion,
      now: now,
      position: signals.position,
      openStatuses: signals.openStatuses,
    );
    _index = 0;
    _wrapped = false;
    _phase = _options.isEmpty ? DecisionPhase.noneOpen : DecisionPhase.result;
    notifyListeners();
  }

  /// "Outra opção": o próximo; depois do último, volta ao 1º e avisa
  /// ([wrapped]).
  void next() {
    if (_phase != DecisionPhase.result || _options.isEmpty) return;
    if (_index + 1 < _options.length) {
      _index++;
      _wrapped = false;
    } else {
      _index = 0;
      _wrapped = true;
    }
    notifyListeners();
  }

  /// Volta para a escolha de companhia.
  void back() {
    _seq++;
    _phase = DecisionPhase.choosing;
    _options = const [];
    _wrapped = false;
    notifyListeners();
  }

  Future<_Signals> _loadSignals() async {
    final results = await Future.wait<Object?>([
      _loadReviews(),
      _loadOpenStatuses(),
      _loadPosition(),
    ]);
    return (
      reviews: results[0]! as List<Review>,
      openStatuses: results[1]! as Map<String, OpenStatus>,
      position: results[2] as LatLng?,
    );
  }

  /// Avaliações de quem o usuário segue; falha (seguidos ou avaliações) =
  /// nenhuma (os critérios de avaliação são ignorados).
  Future<List<Review>> _loadReviews() async {
    final me = _auth.currentUserId;
    if (me == null || _candidates.isEmpty) return const [];
    try {
      final following = await _users.getFollowing(me);
      if (following.isEmpty) return const [];
      final batch = await _reviews.fetchReviewsByAuthors(following.toList());
      final ids = {for (final c in _candidates) c.place.id};
      return [
        for (final r in batch.items)
          if (ids.contains(r.placeId)) r,
      ];
    } on Object catch (e) {
      debugPrint('Avaliações indisponíveis (modo decisão): $e');
      return const [];
    }
  }

  /// "Está aberto agora?" dos candidatos; falha = nenhum fechado.
  Future<Map<String, OpenStatus>> _loadOpenStatuses() async {
    final repo = _openReports;
    if (repo == null || _candidates.isEmpty) return const {};
    try {
      final now = _clock();
      final reports = await repo.fetchForPlaces([
        for (final c in _candidates) c.place.id,
      ], since: openReportsSince(now));
      return openStatusesByPlace(reports, now);
    } on Object catch (e) {
      debugPrint('Relatos indisponíveis (modo decisão): $e');
      return const {};
    }
  }

  /// Última posição, só com a permissão já concedida (nunca pede).
  Future<LatLng?> _loadPosition() async {
    final location = _location;
    if (location == null) return null;
    try {
      return await location.lastKnownPositionIfGranted();
    } on Object {
      return null;
    }
  }
}
