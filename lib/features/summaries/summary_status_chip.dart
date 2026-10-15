import 'package:flutter/material.dart';

import '../../core/viz/status_palette.dart';
import '../../models/daily_summary.dart';

class SummaryStatusChip extends StatelessWidget {
  const SummaryStatusChip({required this.status, super.key});

  final SummaryStatus status;

  (Color, IconData) _visual() {
    switch (status) {
      case SummaryStatus.booked:
        return (VizChrome.info, Icons.schedule);
      case SummaryStatus.delivered:
        return (StatusLevel.good.color, StatusLevel.good.icon);
      case SummaryStatus.partiallyDelivered:
        return (StatusLevel.warning.color, StatusLevel.warning.icon);
      case SummaryStatus.cancelled:
        return (StatusLevel.critical.color, StatusLevel.critical.icon);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (color, icon) = _visual();
    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(status.label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );
  }
}
