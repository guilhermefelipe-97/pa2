import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/open_status.dart';

import '../support/rules_source.dart';

// 12/10/2030 às 20h40 em Natal = 23h40 UTC.
final _now = DateTime.utc(2030, 10, 12, 23, 40);

OpenReport _r(
  String id, {
  required bool open,
  required Duration ago,
  String author = 'ana',
  String name = 'Ana',
  String placeId = 'mangai',
}) => OpenReport(
  id: id,
  authorId: author,
  authorName: name,
  placeId: placeId,
  open: open,
  createdAt: _now.subtract(ago),
);

void main() {
  group('constantes (F20)', () {
    test('janela de 3 h, divergência em 30 min, trava de 30 min, 150 m', () {
      expect(openReportWindow, const Duration(hours: 3));
      expect(openDivergenceWindow, const Duration(minutes: 30));
      expect(openReportCooldown, const Duration(minutes: 30));
      expect(openReportRadiusMeters, 150);
      expect(openReportsSince(_now), _now.subtract(const Duration(hours: 3)));
    });

    test("openReportCooldown = duration.value(N, 'm') da trava nas Rules "
        '(paridade)', () {
      final rules = stripRulesComments(readFirestoreRules());
      final block = RegExp(
        r'match\s+/openReportLocks/\{\s*placeId\s*\}\s*\{([\s\S]*?)\n\s*\}',
      ).firstMatch(rules);
      expect(block, isNotNull, reason: 'match /openReportLocks ausente');
      final durations = RegExp(
        r"duration\s*\.\s*value\s*\(\s*(\d+)\s*,\s*'([a-z]+)'\s*\)",
      ).allMatches(block!.group(1)!).toList();
      expect(durations, hasLength(1));
      expect(durations.single.group(2), 'm');
      expect(
        int.parse(durations.single.group(1)!),
        openReportCooldown.inMinutes,
      );
      expect(
        openReportCooldown,
        Duration(minutes: openReportCooldown.inMinutes),
      );
    });

    test('schema do relato nas Rules: 5 chaves, open bool', () {
      final body = rulesFunctionBody(readFirestoreRules(), 'openReportKeys');
      expect(body, isNotNull);
      final keys = RegExp(
        r"'([a-zA-Z]+)'",
      ).allMatches(body!).map((m) => m.group(1)).toSet();
      expect(keys, {'authorId', 'authorName', 'placeId', 'open', 'createdAt'});
    });
  });

  group('openStatusOf', () {
    test('sem relatos: sem status', () {
      expect(openStatusOf(const [], _now), isNull);
    });

    test('mais recente vence (Ana Sim há 20 min, Caio Não há 2 h)', () {
      final s = openStatusOf([
        _r('c', open: false, ago: const Duration(hours: 2), name: 'Caio'),
        _r('a', open: true, ago: const Duration(minutes: 20)),
      ], _now)!;
      expect(s.kind, OpenStatusKind.open);
      expect(s.latest.id, 'a');
      expect(openStatusLabel(s, _now), 'Aberto · confirmado por Ana há 20 min');
      expect(
        openStatusSemantics(s, _now),
        'Aberto agora, confirmado por Ana há 20 minutos',
      );
    });

    test('fechado: "informado por"', () {
      final s = openStatusOf([
        _r('c', open: false, ago: const Duration(hours: 1), name: 'Caio'),
      ], _now)!;
      expect(s.kind, OpenStatusKind.closed);
      expect(openStatusLabel(s, _now), 'Fechado · informado por Caio há 1 h');
      expect(
        openStatusSemantics(s, _now),
        'Fechado, informado por Caio há 1 hora',
      );
    });

    test('divergente: Sim há 10 min e Não há 20 min', () {
      final s = openStatusOf([
        _r('a', open: true, ago: const Duration(minutes: 10)),
        _r('c', open: false, ago: const Duration(minutes: 20), author: 'c'),
      ], _now)!;
      expect(s.kind, OpenStatusKind.divergent);
      expect(s.isOpen, isFalse);
      expect(
        openStatusLabel(s, _now),
        'Informações divergentes · 2 relatos na última meia hora',
      );
      expect(
        openStatusSemantics(s, _now),
        'Informações divergentes: 2 relatos na última meia hora',
      );
    });

    test('Não há 40 min e Sim há 5 min: não diverge (fora da meia hora)', () {
      final s = openStatusOf([
        _r('c', open: false, ago: const Duration(minutes: 40), author: 'c'),
        _r('a', open: true, ago: const Duration(minutes: 5)),
      ], _now)!;
      expect(s.kind, OpenStatusKind.open);
    });

    test('expirado: último relato há 3 h 05 min = sem status', () {
      expect(
        openStatusOf([
          _r('a', open: true, ago: const Duration(hours: 3, minutes: 5)),
        ], _now),
        isNull,
      );
      expect(
        openStatusOf([
          _r('a', open: true, ago: const Duration(hours: 3)),
        ], _now),
        isNotNull,
      );
    });

    test('relato do próprio usuário: "você agora"', () {
      final s = openStatusOf([
        _r('me', open: true, ago: Duration.zero, author: 'me', name: 'Eu'),
      ], _now)!;
      expect(
        openStatusLabel(s, _now, currentUserId: 'me'),
        'Aberto · confirmado por você agora',
      );
    });

    test(
      'relógio do aparelho atrasado (relato "no futuro") conta como agora',
      () {
        final s = openStatusOf([
          _r('a', open: true, ago: const Duration(seconds: -30)),
        ], _now)!;
        expect(openStatusLabel(s, _now), 'Aberto · confirmado por Ana agora');
      },
    );

    test('nome vazio nunca esconde: "Alguém"', () {
      final s = openStatusOf([
        _r('a', open: true, ago: const Duration(minutes: 3), name: '  '),
      ], _now)!;
      expect(
        openStatusLabel(s, _now),
        'Aberto · confirmado por Alguém há 3 min',
      );
    });

    test('openStatusesByPlace agrupa por local', () {
      final map = openStatusesByPlace([
        _r('a', open: true, ago: const Duration(minutes: 3)),
        _r('b', open: false, ago: const Duration(minutes: 3), placeId: 'x'),
        _r('c', open: false, ago: const Duration(hours: 4), placeId: 'y'),
      ], _now);
      expect(map.keys.toSet(), {'mangai', 'x'});
      expect(map['mangai']!.kind, OpenStatusKind.open);
      expect(map['x']!.kind, OpenStatusKind.closed);
    });
  });

  group('trava de 30 min', () {
    final lastAt = DateTime.utc(2030, 10, 12, 23, 10); // 20h10 em Natal

    test('bloqueia até o instante da liberação; null nunca bloqueia', () {
      expect(isOpenReportBlocked(null, lastAt), isFalse);
      expect(isOpenReportBlocked(lastAt, lastAt), isTrue);
      expect(
        isOpenReportBlocked(lastAt, lastAt.add(const Duration(minutes: 29))),
        isTrue,
      );
      expect(isOpenReportBlocked(lastAt, openReportAllowedAt(lastAt)), isFalse);
    });

    test('mensagem: "Você informou às 20h10. De novo a partir das 20h40."', () {
      expect(
        openReportBlockedMessage(lastAt),
        'Você informou às 20h10. De novo a partir das 20h40.',
      );
      // Segundos arredondam a liberação para cima.
      expect(
        openReportBlockedMessage(DateTime.utc(2030, 10, 12, 23, 10, 5)),
        'Você informou às 20h10. De novo a partir das 20h41.',
      );
      // 1h: singular.
      expect(
        openReportBlockedMessage(DateTime.utc(2030, 10, 13, 4)),
        'Você informou à 1h. De novo a partir da 1h30.',
      );
    });
  });

  test('proximidade: até 150 m', () {
    const place = (lat: -5.8, lng: -35.2);
    // ~1 grau de latitude = 111 km: 0,001° ≈ 111 m.
    expect(isNearForOpenReport((lat: -5.801, lng: -35.2), place), isTrue);
    expect(isNearForOpenReport((lat: -5.802, lng: -35.2), place), isFalse);
    expect(isNearForOpenReport((lat: -5.818, lng: -35.2), place), isFalse);
  });
}
