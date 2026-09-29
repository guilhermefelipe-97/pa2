import 'package:flutter/material.dart';

import '../../../domain/models/review.dart';
import '../../../domain/relative_time.dart';
import 'author_avatar.dart';
import 'axis_scores.dart';

/// Uma avaliação completa: autor, 3 eixos, comentário e contexto
/// (período · companhia · tempo relativo).
class ReviewTile extends StatelessWidget {
  const ReviewTile({super.key, required this.review, required this.now});

  final Review review;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = [
      review.dayPeriod.label,
      if (review.companion != null) review.companion!.label,
      relativeTime(review.createdAt, now),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AuthorAvatar(
            id: review.authorId,
            name: review.authorName,
            radius: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(review.authorName, style: theme.textTheme.titleMedium),
                Text(
                  meta,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                AxisScores.scores(review.scores),
                if (review.comment?.trim().isNotEmpty ?? false) ...[
                  const SizedBox(height: 8),
                  Text(review.comment!, style: theme.textTheme.bodyMedium),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
