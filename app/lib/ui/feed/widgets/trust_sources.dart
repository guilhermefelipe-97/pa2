import 'package:flutter/material.dart' hide DayPeriod;

import '../../../domain/feed.dart';
import '../../../domain/models/companion.dart';
import '../../../domain/models/day_period.dart';
import '../../../domain/models/place_activity.dart';
import '../../../domain/relative_time.dart';
import 'author_avatar.dart';
import 'axis_scores.dart';

/// Nome mostrado de quem avaliou; vazio vira "Alguém" (nunca nota sem dono
/// visível).
String displayAuthorName(String name) =>
    name.trim().isEmpty ? 'Alguém' : name.trim();

/// "com amigos", "em casal"... como parte de uma frase.
String companionPhrase(Companion c) => switch (c) {
  Companion.sozinho => 'sem companhia',
  Companion.casal => 'em casal',
  Companion.amigos => 'com amigos',
  Companion.familia => 'com a família',
  Companion.trabalho => 'a trabalho',
};

/// "à noite", "no almoço"... como parte de uma frase.
String periodPhrase(DayPeriod p) => switch (p) {
  DayPeriod.madrugada => 'de madrugada',
  DayPeriod.manha => 'de manhã',
  DayPeriod.almoco => 'no almoço',
  DayPeriod.tarde => 'à tarde',
  DayPeriod.noite => 'à noite',
};

/// Companhia + período da ida: "com amigos à noite" ou só "à noite".
String visitContext(PlaceActivity r) => [
  if (r.companion != null) companionPhrase(r.companion!),
  periodPhrase(r.dayPeriod),
].join(' ');

/// "foi 3 vezes"; `null` com uma ida só (não ocupa espaço no card).
String? visitsLabel(int trips) => trips > 1 ? 'foi $trips vezes' : null;

/// Ida mais recente que é visita (F15), com companhia e período: "voltou
/// com amigos à noite"; com uma única ida, "foi aqui à noite".
String visitPhrase(TrustSource source) =>
    '${source.trips > 1 ? 'voltou' : 'foi aqui'} '
    '${visitContext(source.latest)}';

/// Marca dos eixos de uma avaliação anterior à visita mais recente:
/// "avaliou há 5 dias", "avaliou ontem", "avaliou em 20/09".
String reviewedAgoLabel(DateTime at, DateTime now) {
  final rel = relativeTime(at, now);
  return RegExp(r'^\d').hasMatch(rel) ? 'avaliou em $rel' : 'avaliou $rel';
}

/// "+1 pessoa", "+3 pessoas".
String morePeopleLabel(int extra) =>
    extra == 1 ? '+1 pessoa' : '+$extra pessoas';

/// Rótulo acessível do "+N": "Ver a outra pessoa", "Ver as 3 outras pessoas".
String morePeopleSemantics(int extra) =>
    extra == 1 ? 'Ver a outra pessoa' : 'Ver as $extra outras pessoas';

/// O que o leitor de tela diz de uma fonte (mesma ordem do que se vê):
/// - avaliação mais recente: "Ana, você segue, comida 5, ambiente 4,
///   atendimento 5, com amigos à noite, foi 2 vezes, há 2 horas";
/// - visita depois de uma avaliação: "Ana, você segue, comida 5, avaliou
///   há 5 dias, voltou com amigos à noite, foi 2 vezes, há 2 horas";
/// - só visitas: "Ana, você segue, voltou com amigos à noite, foi 2 vezes,
///   há 2 horas" (com uma ida: "foi aqui à noite").
String sourceSemanticsLabel(
  TrustSource source, {
  required bool following,
  required DateTime now,
}) {
  final latest = source.latest;
  final r = source.latestReview;
  return [
    displayAuthorName(source.authorName),
    if (following) 'você segue',
    // Só os eixos avaliados (F14): eixo sem nota não é falado.
    if (r?.scores.food != null) 'comida ${r!.scores.food}',
    if (r?.scores.ambience != null) 'ambiente ${r!.scores.ambience}',
    if (r?.scores.service != null) 'atendimento ${r!.scores.service}',
    if (source.reviewIsOlder)
      'avaliou ${relativeTimeSpoken(r!.createdAt, now)}',
    if (latest is Review) visitContext(latest) else visitPhrase(source),
    ?visitsLabel(source.trips),
    relativeTimeSpoken(latest.createdAt, now),
  ].join(', ');
}

/// "🔁 Ana voltou 3 vezes" em linha (F15): o ícone é decorativo (fora da
/// semântica); o leitor de tela fala só [label].
class RecurrenceLine extends StatelessWidget {
  const RecurrenceLine({super.key, required this.label, this.style});

  final String label;
  final TextStyle? style;

  static const String icon = '🔁';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle =
        style ??
        theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.tertiary,
          fontWeight: FontWeight.w700,
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(child: Text(icon, style: textStyle)),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyle,
          ),
        ),
      ],
    );
  }
}

/// Selo de recorrência (F15): "🔁 Ana voltou 3 vezes", acima das notas.
class RecurrenceBadge extends StatelessWidget {
  const RecurrenceBadge({super.key, required this.label});

  /// Sem o emoji (o selo acrescenta o ícone).
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: RecurrenceLine(
        label: label,
        style: TextStyle(
          color: scheme.onTertiaryContainer,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Bloco "Quem foi" do card (F06): até [maxShown] pessoas em destaque, cada
/// uma com os 3 eixos *dela* (nunca número sem dono), e um botão "+N pessoas"
/// que abre o detalhe com todas.
class TrustSources extends StatelessWidget {
  const TrustSources({
    super.key,
    required this.item,
    required this.now,
    this.isFollowing,
    this.onOpenPerson,
    this.onShowAll,
  });

  final FeedItem item;
  final DateTime now;

  /// Relação com quem lê (calculada no cliente, sem leituras extras).
  final bool Function(String uid)? isFollowing;

  /// Toque numa pessoa: abre o perfil dela.
  final void Function(TrustSource source)? onOpenPerson;

  /// "+N pessoas": abre o detalhe do local.
  final VoidCallback? onShowAll;

  static const int maxShown = 2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sources = item.sources;
    final shown = sources.take(maxShown).toList();
    final extra = sources.length - shown.length;
    final recurrent = item.recurrent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // F15: recorrência acima das notas.
        if (recurrent != null) ...[
          RecurrenceBadge(
            key: const Key('trust-recurrence'),
            label: recurrenceLabel(
              displayAuthorName(recurrent.authorName),
              recurrent.trips,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Text(
          'Quem foi',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        for (final s in shown)
          TrustSourceRow(
            key: ValueKey('trust-source-${s.authorId}'),
            source: s,
            now: now,
            following: isFollowing?.call(s.authorId) ?? false,
            onTap: onOpenPerson == null ? null : () => onOpenPerson!(s),
          ),
        if (extra > 0)
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: TextButton(
              key: const Key('trust-sources-more'),
              onPressed: onShowAll,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(
                morePeopleLabel(extra),
                semanticsLabel: morePeopleSemantics(extra),
              ),
            ),
          ),
      ],
    );
  }
}

/// Uma pessoa: avatar, nome, selo "você segue", tempo da ida mais recente;
/// na segunda linha os eixos da avaliação mais recente dela (marcados
/// "avaliou há…" quando uma visita veio depois), companhia + período da ida
/// mais recente e quantas vezes foi. Só com visitas (F15): "voltou com
/// amigos à noite", sem eixos.
class TrustSourceRow extends StatelessWidget {
  const TrustSourceRow({
    super.key,
    required this.source,
    required this.now,
    required this.following,
    this.onTap,
  });

  final TrustSource source;
  final DateTime now;
  final bool following;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final latest = source.latest;
    final r = source.latestReview;
    final name = displayAuthorName(source.authorName);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final visit = [
      if (latest is Review) visitContext(latest) else visitPhrase(source),
      ?visitsLabel(source.trips),
    ].join(' · ');

    return Semantics(
      container: true,
      button: onTap != null,
      label: sourceSemanticsLabel(source, following: following, now: now),
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AuthorAvatar(id: source.authorId, name: name, radius: 14),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Nome (e selo) encolhem com reticências; o tempo
                        // também, em vez de estourar a linha.
                        Expanded(
                          flex: 3,
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (following) ...[
                                const SizedBox(width: 6),
                                const Flexible(child: FollowingBadge()),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            relativeTime(latest.createdAt, now),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: muted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (r != null) AxisScores.scores(r.scores, dense: true),
                        if (source.reviewIsOlder)
                          Text(
                            '(${reviewedAgoLabel(r!.createdAt, now)})',
                            style: muted,
                          ),
                        Text(visit, style: muted),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Selo "você segue".
class FollowingBadge extends StatelessWidget {
  const FollowingBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'você segue',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: scheme.onSecondaryContainer,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
