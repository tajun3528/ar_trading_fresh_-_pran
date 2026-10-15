import 'package:flutter/material.dart';

import '../design/design_tokens.dart';
import '../motion/motion.dart';

import 'status_palette.dart';

/// A single ratio against a limit — same-ramp track with a colored fill and
/// an optional tick marking the limit itself (e.g. the low-stock threshold).
/// This is the "meter" form: for one number judged against a bound, a gauge
/// reads faster than a bar chart with one bar.
class RatioMeter extends StatelessWidget {
  const RatioMeter({
    required this.ratio,
    required this.color,
    this.thresholdRatio,
    this.label,
    this.trailing,
    super.key,
  });

  /// 0..1 fill amount.
  final double ratio;
  final Color color;

  /// 0..1 position of the limit marker, if there is one to show.
  final double? thresholdRatio;
  final String? label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final clampedRatio = ratio.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null || trailing != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                if (label != null)
                  Text(label!, style: const TextStyle(fontSize: 12, color: VizChrome.secondaryInk)),
                const Spacer(),
                if (trailing != null)
                  Text(
                    trailing!,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
                  ),
              ],
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final tick = thresholdRatio;
            return SizedBox(
              height: 10,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    height: 8,
                    margin: const EdgeInsets.only(top: 1),
                    decoration: BoxDecoration(color: VizChrome.track, borderRadius: BorderRadius.circular(4)),
                  ),
                  // Fills from empty on first paint, and slides whenever the
                  // ratio changes, instead of snapping to its width.
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: clampedRatio),
                    duration: reduceMotionOf(context) ? Duration.zero : AppMotion.count,
                    curve: AppMotion.enter,
                    builder: (context, value, child) => FractionallySizedBox(
                      widthFactor: value,
                      child: child,
                    ),
                    child: Container(
                      height: 8,
                      margin: const EdgeInsets.only(top: 1),
                      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                  if (tick != null)
                    Positioned(
                      left: (width * tick.clamp(0.0, 1.0)) - 1,
                      top: 0,
                      child: Container(width: 2, height: 10, color: VizChrome.muted),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
