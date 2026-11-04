import 'package:flutter/material.dart';

import '../../../domain/models/review.dart';
import '../../../domain/relative_time.dart';
import 'author_avatar.dart';
import 'axis_scores.dart';
import 'review_photo.dart';

class ReviewTile extends StatelessWidget {
  const ReviewTile({
    super.key,
    required this.review,
    required this.now,
    this.onAuthorTap,
    this.isOwn = false,
    this.stitchLayout = false,
  });

  final Review review;
  final bool isOwn;
  final bool stitchLayout;
  final DateTime now;

  final VoidCallback? onAuthorTap;

  static const double minTapTarget = 48;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = [
      review.dayPeriod.label,
      if (review.companion != null) review.companion!.label,
      relativeTime(review.createdAt, now),
    ].join(' · ');
    final tappable = onAuthorTap != null;

    Widget author = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: minTapTarget),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: AuthorAvatar(
              id: review.authorId,
              name: review.authorName,
              radius: 18,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              review.authorName,
              style: tappable
                  ? theme.textTheme.titleMedium?.copyWith(
                      decoration: TextDecoration.underline,
                      decorationColor: theme.colorScheme.outlineVariant,
                    )
                  : theme.textTheme.titleMedium,
            ),
          ),
          if (tappable) const SizedBox(width: 8),
        ],
      ),
    );
    if (tappable) {
      author = Semantics(
        key: ValueKey('review-author-${review.id}'),
        button: true,
        label: 'Abrir perfil de ${review.authorName}',
        excludeSemantics: true,
        onTap: onAuthorTap,
        child: InkWell(
          onTap: onAuthorTap,
          borderRadius: BorderRadius.circular(24),
          child: author,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          author,
          Padding(
            padding: EdgeInsets.only(left: stitchLayout ? 0 : 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meta,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                AxisScores.scores(review.scores, stitchLayout: stitchLayout),
                if (review.comment?.trim().isNotEmpty ?? false) ...[
                  const SizedBox(height: 8),
                  Text(review.comment!, style: theme.textTheme.bodyMedium),
                ],
                if (review.hasPhoto)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: AspectRatio(
                        aspectRatio: 1.6,
                        child: ReviewPhoto(
                          review: review,
                          isOwn: isOwn,
                          placeName: review.placeName,
                          compactCredit: true,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
