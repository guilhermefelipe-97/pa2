import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/owner_workspace_repository.dart';

class SavedPlaceRating extends StatefulWidget {
  const SavedPlaceRating({super.key, required this.placeId});
  final String placeId;
  @override
  State<SavedPlaceRating> createState() => _RatingState();
}

class _RatingState extends State<SavedPlaceRating> {
  String? uid;
  Future<OwnerPlaceSummary>? read;
  @override
  Widget build(BuildContext context) {
    final current = context.watch<AuthRepository?>()?.currentUserId;
    final repo = context.read<OwnerWorkspaceRepository?>();
    if (repo == null || current == null) return const SizedBox.shrink();
    if (read == null || uid != current) {
      uid = current;
      read = repo.summary(widget.placeId);
    }
    return FutureBuilder<OwnerPlaceSummary>(
      key: ValueKey(uid),
      future: read,
      builder: (context, snapshot) {
        final rating = snapshot.hasError ? null : snapshot.data?.rating;
        if (rating == null) return const SizedBox.shrink();
        final theme = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Tooltip(
            message: 'Média das notas da comunidade',
            child: Text(
              '★ ${rating.toStringAsFixed(1).replaceAll('.', ',')}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.secondary,
              ),
            ),
          ),
        );
      },
    );
  }
}
