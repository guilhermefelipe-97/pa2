import 'package:flutter/material.dart';
import '../../domain/models/place.dart';
import '../../domain/models/place_activity.dart';
import '../../domain/models/scores.dart';
import '../../domain/relative_time.dart';
import '../core/save_button.dart';
import '../feed/widgets/axis_scores.dart';
import '../feed/widgets/review_photo.dart';
import '../owner/reply_line.dart';

class ProfileReviewCard extends StatelessWidget {
  const ProfileReviewCard({
    super.key,
    required this.review,
    required this.now,
    required this.onTap,
    this.place,
    this.isOwn = false,
  });
  final Review review;
  final DateTime now;
  final VoidCallback onTap;
  final Place? place;
  final bool isOwn;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = Theme.of(context).colorScheme;
    final axes = [
      review.scores.food,
      review.scores.ambience,
      review.scores.service,
    ].whereType<int>().toList();
    final overall = axes.reduce((a, b) => a + b) / axes.length;
    final location = [
      place?.neighborhood,
      place?.city,
      place?.category,
    ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' · ');
    Widget pill(IconData icon, String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          Icon(icon, size: 14, color: scheme.secondary),
          Text(text, style: theme.textTheme.bodySmall),
        ],
      ),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x081F1B17),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            onTap: onTap,
            label: 'Abrir ${review.placeName}',
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          relativeTime(review.createdAt, now),
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          review.placeName,
                          style: theme.textTheme.titleLarge,
                        ),
                        if (location.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            location,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Média dos eixos avaliados nesta experiência',
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star, size: 16, color: scheme.secondary),
                          const SizedBox(width: 4),
                          Text(
                            formatAverage(overall),
                            style: theme.textTheme.titleMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 4,
            runSpacing: 6,
            children: [
              if (review.companion != null)
                pill(Icons.people_outline, review.companion!.label),
              pill(Icons.wb_sunny_outlined, review.dayPeriod.label),
              if (review.priceBand != null)
                pill(Icons.payments_outlined, review.priceBand!.perPersonLabel),
            ],
          ),
          const SizedBox(height: 12),
          AxisScores.scores(review.scores, stitchLayout: true),
          if (review.comment?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 16),
            Text(
              review.comment!,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
            ),
          ],
          if (review.hasPhoto) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AspectRatio(
                aspectRatio: 1.6,
                child: ReviewPhoto(
                  review: review,
                  placeName: review.placeName,
                  isOwn: isOwn,
                ),
              ),
            ),
          ],
          ReplyLine(reviewId: review.id, framed: true),
          if (place?.inCatalog == true) ...[
            const Divider(height: 24),
            Align(
              alignment: Alignment.centerRight,
              child: SaveButton(
                placeId: review.placeId,
                showLabel: true,
                compact: true,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
