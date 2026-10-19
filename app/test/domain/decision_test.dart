import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/decision.dart';
import 'package:naarea/domain/models/companion.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/domain/models/scores.dart';
import 'package:naarea/domain/open_status.dart';

import '../support/builders.dart';

/// Sábado, 20h em Natal (noite).
final _now = DateTime.utc(2026, 10, 17, 23);

/// Noite (20h em Natal) e almoço (12h em Natal), dias antes.
final _night = DateTime.utc(2026, 10, 10, 23);
final _lunch = DateTime.utc(2026, 10, 10, 15);

Place _p(String id, {double? lat, double? lng}) => Place(
  id: id,
  name: 'Local $id',
  category: 'Bar',
  neighborhood: 'Tirol',
  city: 'Natal',
  lat: lat,
  lng: lng,
);

/// Candidato salvo há [hoursAgo] horas.
DecisionCandidate _c(Place p, {int hoursAgo = 24}) =>
    (place: p, savedAt: _now.subtract(Duration(hours: hoursAgo)));

List<String> _ids(List<DecisionOption> options) => [
  for (final o in options) o.place.id,
];

OpenReport _report(String placeId, {required bool open}) => OpenReport(
  id: 'o-$placeId',
  authorId: 'x',
  authorName: 'X',
  placeId: placeId,
  open: open,
  createdAt: _now.subtract(const Duration(minutes: 10)),
);

void main() {
  group('ranking lexicográfico', () {
    test('companhia E período vence quem tem mais avaliações', () {
      final a = _p('a');
      final b = _p('b');
      final options = rankDecision(
        candidates: [_c(a), _c(b)],
        followedReviews: [
          review(placeId: 'a', companion: Companion.amigos, createdAt: _night),
          review(placeId: 'b', companion: Companion.casal, createdAt: _lunch),
          review(placeId: 'b', companion: Companion.casal, createdAt: _lunch),
          review(placeId: 'b', companion: Companion.casal, createdAt: _lunch),
        ],
        companion: Companion.amigos,
        now: _now,
      );
      expect(_ids(options), ['a', 'b']);
      expect(options.first.reason, DecisionCriterion.companionAndPeriod);
      expect(options.first.both, 1);
    });

    test('empate em companhia E período: companhia OU período desempata', () {
      final options = rankDecision(
        candidates: [_c(_p('a')), _c(_p('b'))],
        followedReviews: [
          review(placeId: 'a', companion: Companion.casal, createdAt: _lunch),
          review(placeId: 'a', companion: Companion.casal, createdAt: _lunch),
          review(placeId: 'b', companion: Companion.amigos, createdAt: _lunch),
        ],
        companion: Companion.amigos,
        now: _now,
      );
      expect(_ids(options), ['b', 'a']);
      expect(options.first.reason, DecisionCriterion.companionOrPeriod);
    });

    test('depois, o total de avaliações', () {
      final options = rankDecision(
        candidates: [_c(_p('a')), _c(_p('b'))],
        followedReviews: [
          review(placeId: 'a', companion: Companion.casal, createdAt: _lunch),
          review(placeId: 'b', companion: Companion.casal, createdAt: _lunch),
          review(placeId: 'b', companion: Companion.casal, createdAt: _lunch),
        ],
        companion: Companion.amigos,
        now: _now,
      );
      expect(_ids(options), ['b', 'a']);
      expect(options.first.reason, DecisionCriterion.reviewCount);
    });

    test('depois, a média dos eixos preenchidos (interna)', () {
      final options = rankDecision(
        candidates: [_c(_p('a'), hoursAgo: 1), _c(_p('b'), hoursAgo: 50)],
        followedReviews: [
          review(placeId: 'a', scores: Scores(food: 3), createdAt: _lunch),
          // Eixos vazios não puxam a média para baixo.
          review(placeId: 'b', scores: Scores(service: 5), createdAt: _lunch),
        ],
        companion: Companion.amigos,
        now: _now,
      );
      expect(_ids(options), ['b', 'a']);
      expect(options.first.reason, DecisionCriterion.average);
      expect(options.first.average, 5);
    });

    test('depois, a distância; sem coordenadas vai para o fim', () {
      const me = (lat: -5.7945, lng: -35.2110);
      final near = _p('near', lat: -5.7950, lng: -35.2110);
      final far = _p('far', lat: -5.8100, lng: -35.2110);
      final nowhere = _p('nowhere');
      final options = rankDecision(
        candidates: [_c(nowhere, hoursAgo: 1), _c(far), _c(near)],
        followedReviews: const [],
        companion: Companion.amigos,
        now: _now,
        position: me,
      );
      expect(_ids(options), ['near', 'far', 'nowhere']);
      expect(options[0].reason, DecisionCriterion.distance);
      expect(options[1].reason, DecisionCriterion.distance);
      expect(options[2].distanceMeters, isNull);
    });

    test('sem localização a distância sai do critério: vale o salvo mais '
        'recente', () {
      final near = _p('near', lat: -5.7950, lng: -35.2110);
      final far = _p('far', lat: -5.8100, lng: -35.2110);
      final options = rankDecision(
        candidates: [_c(near, hoursAgo: 48), _c(far, hoursAgo: 2)],
        followedReviews: const [],
        companion: null,
        now: _now,
      );
      expect(_ids(options), ['far', 'near']);
      expect(options.first.reason, DecisionCriterion.savedAt);
      expect(options.first.distanceMeters, isNull);
    });

    test('empate total: ordem estável pelo id', () {
      final options = rankDecision(
        candidates: [_c(_p('b')), _c(_p('a'))],
        followedReviews: const [],
        companion: null,
        now: _now,
      );
      expect(_ids(options), ['a', 'b']);
    });

    test('"Tanto faz" ignora a companhia: só o período desempata', () {
      final options = rankDecision(
        candidates: [_c(_p('a')), _c(_p('b'))],
        followedReviews: [
          review(placeId: 'a', companion: Companion.amigos, createdAt: _lunch),
          review(placeId: 'a', companion: Companion.amigos, createdAt: _lunch),
          review(
            placeId: 'b',
            companion: Companion.trabalho,
            createdAt: _night,
          ),
        ],
        companion: null,
        now: _now,
      );
      expect(_ids(options), ['b', 'a']);
      expect(options.first.both, 1);
      expect(options.first.reason, DecisionCriterion.companionAndPeriod);
    });

    test('só contam avaliações dos candidatos (e cada uma uma vez)', () {
      final r = review(
        id: 'dup',
        placeId: 'a',
        companion: Companion.amigos,
        createdAt: _night,
      );
      final options = rankDecision(
        candidates: [_c(_p('a'))],
        followedReviews: [
          r,
          r,
          review(placeId: 'fora', companion: Companion.amigos),
        ],
        companion: Companion.amigos,
        now: _now,
      );
      expect(options.single.total, 1);
      expect(options.single.both, 1);
    });

    test('sem avaliações (leitura falhou): critérios delas ignorados', () {
      final options = rankDecision(
        candidates: [_c(_p('a'), hoursAgo: 5), _c(_p('b'), hoursAgo: 1)],
        followedReviews: const [],
        companion: Companion.amigos,
        now: _now,
      );
      expect(_ids(options), ['b', 'a']);
      expect(options.every((o) => o.total == 0 && o.average == null), isTrue);
    });
  });

  group('"Fechado" relatado sai antes de ordenar', () {
    test('fechado sai; aberto e divergente ficam', () {
      final options = rankDecision(
        candidates: [_c(_p('a')), _c(_p('b')), _c(_p('c'))],
        followedReviews: [
          review(placeId: 'a', companion: Companion.amigos, createdAt: _night),
        ],
        companion: Companion.amigos,
        now: _now,
        openStatuses: openStatusesByPlace([
          _report('a', open: false),
          _report('b', open: true),
        ], _now),
      );
      expect(_ids(options), ['b', 'c']);
    });

    test('todos fechados: nenhuma opção', () {
      final options = rankDecision(
        candidates: [_c(_p('a')), _c(_p('b'))],
        followedReviews: const [],
        companion: null,
        now: _now,
        openStatuses: openStatusesByPlace([
          _report('a', open: false),
          _report('b', open: false),
        ], _now),
      );
      expect(options, isEmpty);
    });
  });

  group('motivo exibido (do critério que desempatou)', () {
    String reasonOf(DecisionOption o, Companion? companion) =>
        decisionReason(o, companion: companion, now: _now);

    test('"2 pessoas que você segue foram com amigos à noite"', () {
      final options = rankDecision(
        candidates: [_c(_p('a')), _c(_p('b'))],
        followedReviews: [
          review(
            authorId: 'ana',
            placeId: 'a',
            companion: Companion.amigos,
            createdAt: _night,
          ),
          review(
            authorId: 'caio',
            placeId: 'a',
            companion: Companion.amigos,
            createdAt: _night,
          ),
        ],
        companion: Companion.amigos,
        now: _now,
      );
      expect(
        reasonOf(options.first, Companion.amigos),
        '2 pessoas que você segue foram com amigos à noite',
      );
    });

    test('singular e "Tanto faz"', () {
      final options = rankDecision(
        candidates: [_c(_p('a')), _c(_p('b'))],
        followedReviews: [review(placeId: 'a', createdAt: _night)],
        companion: null,
        now: _now,
      );
      expect(
        reasonOf(options.first, null),
        '1 pessoa que você segue foi lá à noite',
      );
    });

    test('companhia OU período, total e média', () {
      final either = rankDecision(
        candidates: [_c(_p('a')), _c(_p('b'))],
        followedReviews: [
          review(placeId: 'a', companion: Companion.familia, createdAt: _lunch),
        ],
        companion: Companion.familia,
        now: _now,
      );
      expect(
        reasonOf(either.first, Companion.familia),
        '1 pessoa que você segue foi com a família ou à noite',
      );
      final total = rankDecision(
        candidates: [_c(_p('a')), _c(_p('b'))],
        followedReviews: [
          review(authorId: 'x', placeId: 'a', createdAt: _lunch),
          review(authorId: 'y', placeId: 'a', createdAt: _lunch),
          review(authorId: 'z', placeId: 'a', createdAt: _lunch),
        ],
        companion: Companion.casal,
        now: _now,
      );
      expect(
        reasonOf(total.first, Companion.casal),
        'Avaliado por 3 pessoas que você segue',
      );
      final average = rankDecision(
        candidates: [_c(_p('a')), _c(_p('b'))],
        followedReviews: [
          review(placeId: 'a', scores: Scores(food: 5), createdAt: _lunch),
          review(placeId: 'b', scores: Scores(food: 2), createdAt: _lunch),
        ],
        companion: Companion.casal,
        now: _now,
      );
      final text = reasonOf(average.first, Companion.casal);
      expect(text, 'Bem avaliado por quem você segue');
      expect(text, isNot(matches(RegExp(r'\d'))), reason: 'sem nota exibida');
    });

    test('média baixa desempatando não vira elogio: diz quem avaliou', () {
      final options = rankDecision(
        candidates: [_c(_p('a')), _c(_p('b'))],
        followedReviews: [
          review(placeId: 'a', scores: Scores(food: 3), createdAt: _lunch),
          review(placeId: 'b', scores: Scores(food: 2), createdAt: _lunch),
        ],
        companion: Companion.casal,
        now: _now,
      );
      expect(options.first.reason, DecisionCriterion.average);
      expect(
        reasonOf(options.first, Companion.casal),
        'Avaliado por 1 pessoa que você segue',
      );
    });

    test('nenhum texto é superlativo (a comparação é só com o seguinte)', () {
      const me = (lat: -5.7945, lng: -35.2110);
      final options = rankDecision(
        candidates: [
          _c(_p('x', lat: -5.7976, lng: -35.2110), hoursAgo: 3),
          _c(_p('y', lat: -5.8000, lng: -35.2110), hoursAgo: 2),
          _c(_p('z'), hoursAgo: 1),
        ],
        followedReviews: [
          review(placeId: 'x', scores: Scores(food: 5), createdAt: _lunch),
          review(placeId: 'y', scores: Scores(food: 4), createdAt: _lunch),
        ],
        companion: Companion.casal,
        now: _now,
        position: me,
      );
      for (final o in options) {
        final text = reasonOf(o, Companion.casal);
        expect(text, isNot(contains('mais')), reason: text);
      }
    });

    test('distância e salvo: comparando com o seguinte e sozinho', () {
      const me = (lat: -5.7945, lng: -35.2110);
      final options = rankDecision(
        candidates: [
          _c(_p('near', lat: -5.7976, lng: -35.2110)),
          _c(_p('far', lat: -5.8100, lng: -35.2110)),
        ],
        followedReviews: const [],
        companion: null,
        now: _now,
        position: me,
      );
      expect(reasonOf(options[0], null), 'A 340 m de você');
      expect(reasonOf(options[1], null), 'A 1,7 km de você');
      final single = rankDecision(
        candidates: [_c(_p('a'))],
        followedReviews: const [],
        companion: null,
        now: _now,
      );
      // Salvo há 24 h: 16/10 em Natal.
      expect(reasonOf(single.single, null), 'Salvo no Quero ir em 16/10');
      final bySaved = rankDecision(
        candidates: [_c(_p('a'), hoursAgo: 1), _c(_p('b'), hoursAgo: 30)],
        followedReviews: const [],
        companion: null,
        now: _now,
      );
      expect(reasonOf(bySaved.first, null), 'Salvo no Quero ir em 17/10');
    });

    test('empate total (mesmo savedAt): o sinal mais forte, sem afirmar '
        'desempate', () {
      final tied = rankDecision(
        candidates: [_c(_p('a')), _c(_p('b'))],
        followedReviews: [
          review(authorId: 'x', placeId: 'a', createdAt: _lunch),
          review(authorId: 'x', placeId: 'b', createdAt: _lunch),
        ],
        companion: Companion.casal,
        now: _now,
      );
      expect(tied.first.reason, DecisionCriterion.reviewCount);
      expect(
        reasonOf(tied.first, Companion.casal),
        'Avaliado por 1 pessoa que você segue',
      );
      const me = (lat: -5.7945, lng: -35.2110);
      final sameSpot = rankDecision(
        candidates: [
          _c(_p('a', lat: -5.7976, lng: -35.2110)),
          _c(_p('b', lat: -5.7976, lng: -35.2110)),
        ],
        followedReviews: const [],
        companion: null,
        now: _now,
        position: me,
      );
      expect(sameSpot.first.reason, DecisionCriterion.distance);
      expect(reasonOf(sameSpot.first, null), 'A 340 m de você');
    });
  });
}
