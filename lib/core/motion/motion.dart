import 'package:flutter/material.dart';

import '../design/design_tokens.dart';

/// Whether animation should be suppressed for this viewer.
///
/// Respects both the person's own "Reduce motion" setting in Profile and the
/// operating system's accessibility switch. Every widget in this library goes
/// through here, so turning it off genuinely turns everything off rather than
/// leaving stray animations behind.
bool reduceMotionOf(BuildContext context) {
  return MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

/// Marks a subtree as motion-free. Placed at the app root from the person's
/// preferences, it also switches off Flutter's own route and widget
/// animations, not just this library's.
class MotionPreference extends StatelessWidget {
  const MotionPreference({required this.reduceMotion, required this.child, super.key});

  final bool reduceMotion;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (!reduceMotion && !media.disableAnimations) return child;
    return MediaQuery(
      data: media.copyWith(disableAnimations: true),
      child: child,
    );
  }
}

/// A fade-and-rise entrance, played once when the widget first appears.
///
/// [delay] is what makes a group feel choreographed rather than simultaneous —
/// see [RevealGroup], which fills it in automatically.
class Reveal extends StatefulWidget {
  const Reveal({
    required this.child,
    this.delay = Duration.zero,
    this.duration = AppMotion.normal,
    this.offset = 14,
    super.key,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

  /// How far it rises, in logical pixels. Keep it small — a long travel
  /// reads as sluggish on a screen someone opens dozens of times a day.
  final double offset;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _curve = CurvedAnimation(parent: _controller, curve: AppMotion.enter);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (reduceMotionOf(context)) {
      _controller.value = 1;
    } else if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) => Opacity(
        opacity: _curve.value,
        child: Transform.translate(
          offset: Offset(0, widget.offset * (1 - _curve.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Reveals children one after another.
///
/// Above [AppMotion.staggerLimit] children the stagger is dropped and the
/// whole group animates as one — the catalog screens render well over a
/// hundred rows, where per-child animation costs far more than it adds and
/// makes the reader wait for choreography before they can scan.
class RevealGroup extends StatelessWidget {
  const RevealGroup({
    required this.children,
    this.interval = AppMotion.stagger,
    this.delay = Duration.zero,
    super.key,
  });

  final List<Widget> children;
  final Duration interval;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    if (children.length > AppMotion.staggerLimit) {
      return Reveal(delay: delay, child: Column(mainAxisSize: MainAxisSize.min, children: children));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, child) in children.indexed)
          Reveal(delay: delay + interval * i, child: child),
      ],
    );
  }

  /// The same stagger for callers that lay their own children out — a grid or
  /// a wrap — rather than stacking them in a column.
  static List<Widget> wrap(
    List<Widget> children, {
    Duration interval = AppMotion.stagger,
    Duration delay = Duration.zero,
  }) {
    if (children.length > AppMotion.staggerLimit) return children;
    return [
      for (final (i, child) in children.indexed) Reveal(delay: delay + interval * i, child: child),
    ];
  }
}

/// A number that counts up to its value, and re-counts from wherever it was
/// whenever the value changes.
///
/// [format] receives the interpolated value, so the caller keeps control of
/// currency symbols, decimals and thousands separators.
class CountUp extends StatelessWidget {
  const CountUp({
    required this.value,
    required this.format,
    this.style,
    this.duration = AppMotion.count,
    super.key,
  });

  final double value;
  final String Function(double value) format;
  final TextStyle? style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (reduceMotionOf(context)) {
      return Text(format(value), style: style);
    }
    return TweenAnimationBuilder<double>(
      // No `begin`, so on a value change it tweens from the previous value
      // rather than snapping back to zero.
      tween: Tween(end: value),
      duration: duration,
      curve: AppMotion.enter,
      builder: (context, v, _) => Text(format(v), style: style),
    );
  }
}

/// Raises and slightly scales its child while the pointer is over it, and
/// shows a clickable cursor.
///
/// The app is used on desktop where nothing currently responds to hover —
/// a table row gives no signal it is clickable until you click it.
class HoverLift extends StatefulWidget {
  const HoverLift({
    required this.child,
    this.onTap,
    this.scale = 1.015,
    this.borderRadius = AppRadius.rLg,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final BorderRadius borderRadius;

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final reduce = reduceMotionOf(context);
    final lifted = _hovered && !reduce;

    return MouseRegion(
      cursor: widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: lifted ? widget.scale : 1,
        duration: AppMotion.fast,
        curve: AppMotion.standard,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.standard,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            boxShadow: _hovered ? AppElevation.hover(context) : AppElevation.card(context),
          ),
          child: widget.onTap == null
              ? widget.child
              : GestureDetector(onTap: widget.onTap, child: widget.child),
        ),
      ),
    );
  }
}
