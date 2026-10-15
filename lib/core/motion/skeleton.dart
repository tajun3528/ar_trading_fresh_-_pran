import 'package:flutter/material.dart';

import '../design/design_tokens.dart';
import 'motion.dart';

/// A shimmering placeholder shaped like the thing that is loading.
///
/// Replaces the spinner: a spinner says "wait", a skeleton says "here is what
/// is coming and roughly how much of it", which reads as faster even when it
/// is not. One [AnimationController] drives every descendant via
/// [_ShimmerDrive], so a screen full of skeletons still costs a single ticker.
class Skeleton extends StatelessWidget {
  const Skeleton({this.width, this.height = 12, this.radius = AppRadius.sm, super.key});

  /// Null stretches to the available width.
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final drive = _ShimmerDrive.maybeOf(context);
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.onSurface.withValues(alpha: 0.07);
    final highlight = scheme.onSurface.withValues(alpha: 0.14);

    final box = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(radius)),
    );

    if (drive == null) return box;

    return AnimatedBuilder(
      animation: drive,
      builder: (context, _) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [base, highlight, base],
          stops: const [0.0, 0.5, 1.0],
          // Sweeps a highlight band across, well past both edges so the
          // shimmer enters and leaves rather than popping.
          transform: _SweepTransform(drive.value),
        ).createShader(bounds),
        child: box,
      ),
    );
  }
}

/// Slides the shimmer gradient horizontally.
class _SweepTransform extends GradientTransform {
  const _SweepTransform(this.progress);

  final double progress;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    // -1 → 1 maps to fully off the left edge → fully off the right.
    return Matrix4.translationValues(bounds.width * (progress * 2 - 1), 0, 0);
  }
}

/// Owns the one ticker that every [Skeleton] beneath it shares.
class _ShimmerDrive extends InheritedNotifier<Animation<double>> {
  const _ShimmerDrive({required Animation<double> super.notifier, required super.child});

  static Animation<double>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ShimmerDrive>()?.notifier;
}

/// Wraps a loading placeholder so its [Skeleton]s shimmer together.
///
/// When motion is reduced the shimmer is dropped and the bars simply sit
/// there — still a useful shape-of-what-is-coming, just still.
class SkeletonSheet extends StatefulWidget {
  const SkeletonSheet({required this.child, super.key});

  final Widget child;

  @override
  State<SkeletonSheet> createState() => _SkeletonSheetState();
}

class _SkeletonSheetState extends State<SkeletonSheet> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: AppMotion.shimmer);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (reduceMotionOf(context)) {
      if (_controller.isAnimating) _controller.stop();
      return widget.child;
    }
    if (!_controller.isAnimating) _controller.repeat();
    return _ShimmerDrive(notifier: _controller, child: widget.child);
  }
}

/// A ready-made placeholder shaped like one of the app's data tables:
/// a header strip and a run of rows.
class SkeletonTable extends StatelessWidget {
  const SkeletonTable({this.rows = 6, this.columns = 5, super.key});

  final int rows;
  final int columns;

  @override
  Widget build(BuildContext context) {
    return SkeletonSheet(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Skeleton(width: 150, height: 15),
              const SizedBox(height: AppSpace.lg),
              for (var r = 0; r < rows; r++) ...[
                Row(
                  children: [
                    for (var c = 0; c < columns; c++) ...[
                      // The first column is the name and gets the most room;
                      // the rest are figures.
                      Expanded(flex: c == 0 ? 3 : 1, child: Skeleton(height: 11)),
                      if (c != columns - 1) const SizedBox(width: AppSpace.md),
                    ],
                  ],
                ),
                if (r != rows - 1) const SizedBox(height: AppSpace.lg),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A placeholder shaped like a row of metric tiles above a table — the shape
/// of most screens in this app.
class SkeletonDashboard extends StatelessWidget {
  const SkeletonDashboard({this.tiles = 4, super.key});

  final int tiles;

  @override
  Widget build(BuildContext context) {
    return SkeletonSheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              // Match the tile grid's own wrapping so the placeholder lands
              // where the real tiles will.
              final perRow = constraints.maxWidth >= 900
                  ? 4
                  : constraints.maxWidth >= 560
                      ? 2
                      : 1;
              final width = (constraints.maxWidth - (perRow - 1) * AppSpace.md) / perRow;
              return Wrap(
                spacing: AppSpace.md,
                runSpacing: AppSpace.md,
                children: [
                  for (var i = 0; i < tiles; i++)
                    Skeleton(width: width, height: 84, radius: AppRadius.lg),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpace.lg),
          const SkeletonTable(),
        ],
      ),
    );
  }
}
