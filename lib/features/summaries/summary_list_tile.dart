import 'package:flutter/material.dart';

import '../../core/viz/status_palette.dart';
import '../../models/daily_summary.dart';

Color summaryStatusColor(SummaryStatus status) {
  switch (status) {
    case SummaryStatus.booked:
      return VizChrome.info;
    case SummaryStatus.delivered:
      return StatusLevel.good.color;
    case SummaryStatus.partiallyDelivered:
      return StatusLevel.warning.color;
    case SummaryStatus.cancelled:
      return StatusLevel.critical.color;
  }
}
