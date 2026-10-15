import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/design/design_tokens.dart';
import '../../core/viz/status_palette.dart';

/// The shared look for every screen you see before signing in.
///
/// Built to fix what a flat form does wrong: it sits on stark white, every
/// element is lit the same, and nothing casts a shadow, so the whole thing
/// reads as cutouts rather than a scene. What follows builds real layers —
/// a graded ground, soft out-of-focus shapes behind, one ribbon sweeping
/// through to tie the composition together, and a sharp card in front that
/// casts a proper contact shadow onto all of it.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    this.footer,
    super.key,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The ground is painted below, so the Scaffold must not paint over it.
      backgroundColor: AuthPalette.ground,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // --- far: graded ground, out-of-focus shapes, ribbon, rays -------
          const RepaintBoundary(child: _Backdrop()),

          // --- near: the form itself, sharp and raised --------------------
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Brand(title: title, subtitle: subtitle, icon: icon),
                      const SizedBox(height: 26),
                      _Card(child: child),
                      if (footer case final footer?) ...[
                        const SizedBox(height: 18),
                        footer,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One palette for the whole scene, so nothing looks separately lit. Built
/// from the app's own indigo chrome rather than a second unrelated identity.
class AuthPalette {
  AuthPalette._();

  // These now come from BrandPalette so the sign-in screen, the splash and
  // the nav chrome cannot drift apart — there is one set of brand colours,
  // and changing it changes all three.
  static const ground = BrandPalette.ground;
  static const groundLift = BrandPalette.groundLift;
  static const indigo = BrandPalette.indigo;
  static const teal = BrandPalette.teal;
  static const plum = BrandPalette.plum;
  static const card = BrandPalette.card;
  static const ink = BrandPalette.ink;
  static const inkSoft = BrandPalette.inkSoft;
}

/// The logo mark and wordmark. The mark sits on a soft disc with a single
/// consistent shadow so it reads as a deliberate node, not a pasted glyph.
class _Brand extends StatelessWidget {
  const _Brand({required this.title, required this.subtitle, required this.icon});

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 78,
          height: 78,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AuthPalette.indigo, AuthPalette.plum],
            ),
            boxShadow: [
              // Contact shadow: tight and dark, sitting directly under it.
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 22,
                spreadRadius: -4,
                offset: const Offset(0, 12),
              ),
              // Ambient glow, so the mark belongs to the light in the scene.
              BoxShadow(
                color: AuthPalette.indigo.withValues(alpha: 0.40),
                blurRadius: 40,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Icon(icon, size: 36, color: Colors.white),
        ),
        const SizedBox(height: 18),
        // One type scale: a bold name, then a lighter descriptor at a fixed
        // smaller size. Nothing else competes.
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 27,
            height: 1.15,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13.5,
            height: 1.4,
            fontWeight: FontWeight.w500,
            color: Colors.white.withValues(alpha: 0.66),
          ),
        ),
      ],
    );
  }
}

/// The sharp plane. Everything behind it is soft; this is the only thing in
/// focus, which is what puts it in front.
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 26),
      decoration: BoxDecoration(
        color: AuthPalette.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.42),
            blurRadius: 46,
            spreadRadius: -8,
            offset: const Offset(0, 24),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 12,
            spreadRadius: -4,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _BackdropPainter(), size: Size.infinite);
  }
}

/// Paints the scene behind the card, back to front.
///
/// Soft shapes are drawn as radial gradients rather than blurred sprites:
/// the falloff reads as out-of-focus at a fraction of the cost, which matters
/// because this is the first screen to render on the web.
class _BackdropPainter extends CustomPainter {
  /// Out-of-focus shapes, deliberately irregular — staggered positions,
  /// different sizes and hues. An even row of identical circles is what makes
  /// a composition look pasted together.
  static const _orbs = <({double dx, double dy, double r, Color color, double opacity})>[
    (dx: 0.14, dy: 0.14, r: 0.40, color: AuthPalette.indigo, opacity: 0.38),
    (dx: 0.88, dy: 0.06, r: 0.30, color: AuthPalette.plum, opacity: 0.30),
    (dx: 0.78, dy: 0.46, r: 0.46, color: AuthPalette.teal, opacity: 0.17),
    (dx: 0.05, dy: 0.62, r: 0.34, color: AuthPalette.plum, opacity: 0.22),
    (dx: 0.52, dy: 0.93, r: 0.38, color: AuthPalette.indigo, opacity: 0.26),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shortest = size.shortestSide;

    // ---------------------------------------------------------- the ground
    // Never flat: a radial lift behind where the card lands, so the centre
    // of the screen is where the light is.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.1, -0.35),
          radius: 1.15,
          colors: [AuthPalette.groundLift, AuthPalette.ground],
          stops: [0.0, 1.0],
        ).createShader(rect),
    );

    // ------------------------------------------------- depth-of-field orbs
    for (final orb in _orbs) {
      final center = Offset(size.width * orb.dx, size.height * orb.dy);
      final radius = shortest * orb.r;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              orb.color.withValues(alpha: orb.opacity),
              orb.color.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 1.0],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    _paintRays(canvas, size);
    _paintRibbon(canvas, size);
    _paintForeground(canvas, size);

    // ----------------------------------------------------- the colour grade
    // One pass over everything so no layer looks separately lit.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AuthPalette.ground.withValues(alpha: 0.10),
            AuthPalette.ground.withValues(alpha: 0.42),
          ],
        ).createShader(rect),
    );
  }

  /// Faint light coming in from the top-left, as through a roof. Angled and
  /// unevenly spaced — parallel identical beams look like wallpaper.
  void _paintRays(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    const beams = <({double x, double width, double opacity})>[
      (x: 0.08, width: 0.10, opacity: 0.055),
      (x: 0.26, width: 0.05, opacity: 0.035),
      (x: 0.40, width: 0.14, opacity: 0.045),
      (x: 0.66, width: 0.06, opacity: 0.028),
    ];

    for (final beam in beams) {
      final left = size.width * beam.x;
      final width = size.width * beam.width;
      // Leaning beams, widening as they fall.
      final path = Path()
        ..moveTo(left, -size.height * 0.05)
        ..lineTo(left + width, -size.height * 0.05)
        ..lineTo(left + width + size.width * 0.22, size.height * 1.05)
        ..lineTo(left + size.width * 0.16, size.height * 1.05)
        ..close();

      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: beam.opacity),
              Colors.white.withValues(alpha: 0.0),
            ],
          ).createShader(Offset.zero & size),
      );
    }
    canvas.restore();
  }

  /// One ribbon sweeping the full width behind the card. This is the piece
  /// that ties the composition together — without it the shapes above are
  /// just scattered blobs.
  void _paintRibbon(Canvas canvas, Size size) {
    // A Paint's `color` is ignored once a shader is set, so each pass has to
    // carry its own opacity in the gradient itself.
    Shader gradientAt(double alpha) => LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            AuthPalette.teal.withValues(alpha: 0.0),
            AuthPalette.teal.withValues(alpha: 0.55 * alpha),
            AuthPalette.indigo.withValues(alpha: 0.60 * alpha),
            AuthPalette.plum.withValues(alpha: 0.45 * alpha),
            AuthPalette.plum.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.26, 0.55, 0.80, 1.0],
        ).createShader(Offset.zero & size);

    // Two passes of the same curve: a wide soft one reading as the ribbon's
    // body, a narrow bright one as its lit edge.
    for (final pass in const [(width: 34.0, alpha: 0.5), (width: 5.0, alpha: 1.0)]) {
      final path = Path()
        ..moveTo(-size.width * 0.05, size.height * 0.70)
        ..cubicTo(
          size.width * 0.22, size.height * 0.52,
          size.width * 0.34, size.height * 0.24,
          size.width * 0.56, size.height * 0.30,
        )
        ..cubicTo(
          size.width * 0.76, size.height * 0.35,
          size.width * 0.82, size.height * 0.62,
          size.width * 1.05, size.height * 0.50,
        );

      canvas.drawPath(
        path,
        Paint()
          ..shader = gradientAt(pass.alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = pass.width
          ..strokeCap = StrokeCap.round
          ..maskFilter = pass.width > 10
              ? const MaskFilter.blur(BlurStyle.normal, 18)
              : const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
  }

  /// A large shape half out of frame in the bottom corner. Nothing builds
  /// front-to-back layering faster than something the frame cuts off.
  void _paintForeground(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.04, size.height * 1.06);
    final radius = size.shortestSide * 0.52;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            AuthPalette.ground.withValues(alpha: 0.92),
            AuthPalette.ground.withValues(alpha: 0.55),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );

    // A lit rim along its upper edge, so it reads as a solid object in front
    // rather than a dark smudge.
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi * 1.08,
      math.pi * 0.62,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = AuthPalette.indigo.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter oldDelegate) => false;
}

/// Field styling shared by both forms, so a label, a border and a focus ring
/// are identical on every input on both screens.
InputDecoration authField(String label, {String? helper, Widget? suffix}) {
  OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: BorderSide(color: color, width: width),
      );

  return InputDecoration(
    labelText: label,
    helperText: helper,
    suffixIcon: suffix,
    filled: true,
    fillColor: Colors.white,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
    labelStyle: const TextStyle(color: AuthPalette.inkSoft, fontSize: 14),
    helperStyle: const TextStyle(fontSize: 11.5, color: AuthPalette.inkSoft),
    enabledBorder: border(const Color(0xFFD9D6E6), 1),
    border: border(const Color(0xFFD9D6E6), 1),
    focusedBorder: border(AuthPalette.indigo, 1.8),
  );
}

/// The one primary action on an auth screen. Raised, so it belongs to the
/// same light as the card it sits on.
class AuthSubmitButton extends StatelessWidget {
  const AuthSubmitButton({required this.label, required this.busy, required this.onPressed, super.key});

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        boxShadow: busy
            ? const []
            : [
                BoxShadow(
                  color: AuthPalette.indigo.withValues(alpha: 0.38),
                  blurRadius: 16,
                  offset: const Offset(0, 7),
                ),
              ],
      ),
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AuthPalette.indigo,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        child: busy
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Text(label),
      ),
    );
  }
}

/// The error banner, identical on both screens.
class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: StatusLevel.critical.color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: StatusLevel.critical.color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 17, color: StatusLevel.critical.color),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12.5, height: 1.35, color: StatusLevel.critical.color),
            ),
          ),
        ],
      ),
    );
  }
}

/// The link between the two screens — quiet, but readable on the dark ground.
class AuthFooterLink extends StatelessWidget {
  const AuthFooterLink({required this.prompt, required this.action, required this.onPressed, super.key});

  final String prompt;
  final String action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          prompt,
          style: TextStyle(fontSize: 13.5, color: Colors.white.withValues(alpha: 0.62)),
        ),
        TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            action,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
