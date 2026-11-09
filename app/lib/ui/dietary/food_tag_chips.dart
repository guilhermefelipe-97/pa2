import 'package:flutter/material.dart';
import 'food_filter_options.dart';

class FoodTagChips extends StatelessWidget {
  const FoodTagChips({super.key, required this.tags});
  final Map<String, int> tags;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    children: [
      for (final entry in tags.entries)
        Chip(
          label: Text(
            '${foodTagLabel(entry.key)} · ${entry.value} pessoas da comunidade',
          ),
        ),
    ],
  );
}
