import 'package:flutter/material.dart';

import 'status_palette.dart';

class StatusCount {
  const StatusCount({required this.label, required this.count, required this.color, this.icon});

  final String label;
  final int count;
  final Color color;
  final IconData? icon;
}

/// Part-to-whole breakdown: a single stacked bar plus a direct-labeled
/// legend (count is never color-alone). Segments under one physical pixel
/// worth of proportion still keep a sliver so a nonzero count is never
/// invisible.
class StatusBreakdownBar extends StatelessWidget {
  const StatusBreakdownBar({required this.counts, super.key});

  final List<StatusCount> counts;

  @override
  Widget build(BuildContext context) {
    final total = counts.fold<int>(0, (sum, c) => sum + c.count);
    final visible = counts.where((c) => c.count > 0).toList();

    if (total == 0) {
      return const Text('No data yet', style: TextStyle(fontSize: 12, color: VizChrome.secondaryInk));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 12,
            child: Row(
              children: [
                for (final c in visible) ...[
                  Expanded(
                    flex: c.count,
                    child: Container(color: c.color),
                  ),
                  if (c != visible.last) Container(width: 2, color: Colors.white),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            for (final c in counts)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: c.color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text('${c.label} (${c.count})', style: const TextStyle(fontSize: 12)),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
