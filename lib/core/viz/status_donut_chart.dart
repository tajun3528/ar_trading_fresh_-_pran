import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../design/design_tokens.dart';
import '../motion/motion.dart';

import 'status_breakdown_bar.dart' show StatusCount;
import 'status_palette.dart';

/// Part-to-whole breakdown as a donut — center shows the total, with a
/// direct-labeled legend below (count is never color-alone). Same [StatusCount]
/// model as [StatusBreakdownBar]; pick whichever form reads faster for the
/// number of segments on hand.
class StatusDonutChart extends StatelessWidget {
  const StatusDonutChart({required this.counts, this.centerLabel, super.key});

  final List<StatusCount> counts;
  final String? centerLabel;

  @override
  Widget build(BuildContext context) {
    final total = counts.fold<int>(0, (sum, c) => sum + c.count);
    final visible = counts.where((c) => c.count > 0).toList();

    if (total == 0) {
      return const SizedBox(
        height: 180,
        child: Center(
          child: Text('No data yet', style: TextStyle(color: VizChrome.secondaryInk)),
        ),
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 160,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Scaling every slice equally would look static, since the
              // proportions never change — so the ring grows outward from the
              // centre instead.
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: reduceMotionOf(context) ? Duration.zero : AppMotion.count,
                curve: AppMotion.enter,
                builder: (context, t, _) => PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 46,
                    sections: [
                      for (final c in visible)
                        PieChartSectionData(
                          value: c.count.toDouble(),
                          color: c.color,
                          radius: 26 * t,
                          showTitle: false,
                        ),
                    ],
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$total', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  if (centerLabel != null)
                    Text(centerLabel!, style: const TextStyle(fontSize: 11, color: VizChrome.secondaryInk)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 6,
          alignment: WrapAlignment.center,
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
