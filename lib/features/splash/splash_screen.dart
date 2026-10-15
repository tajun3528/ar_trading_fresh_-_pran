import 'package:flutter/material.dart';

import '../../core/design/design_tokens.dart';
import '../../core/motion/motion.dart';

/// The first thing every person sees, on every cold start — the router sends
/// all traffic through here while the session is restored. It used to be a
/// bare spinner on white, which set the tone for the whole app.
///
/// Now it is the brand mark breathing on the brand ground, so the wait reads
/// as the app arriving rather than as nothing happening.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    _pulse.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = reduceMotionOf(context);
    if (reduce && _pulse.isAnimating) _pulse.stop();

    return Scaffold(
      backgroundColor: BrandPalette.ground,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.1, -0.3),
            radius: 1.1,
            colors: [BrandPalette.groundLift, BrandPalette.ground],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, child) {
                  // A slow breath rather than a spin: it says "working" without
                  // the restlessness of a spinner.
                  final t = reduce ? 0.0 : Curves.easeInOut.transform(_pulse.value);
                  return Transform.scale(
                    scale: 1 + t * 0.06,
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: BrandPalette.gradient,
                        boxShadow: [
                          BoxShadow(
                            color: BrandPalette.indigo.withValues(alpha: 0.30 + t * 0.28),
                            blurRadius: 34 + t * 26,
                            spreadRadius: t * 6,
                          ),
                        ],
                      ),
                      child: child,
                    ),
                  );
                },
                child: const Icon(Icons.local_shipping, color: Colors.white, size: 38),
              ),
              const SizedBox(height: AppSpace.xl),
              Text(
                'AR-Trading',
                style: AppType.titleL.copyWith(color: Colors.white, letterSpacing: 0.2),
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                'Getting things ready…',
                style: AppType.bodyS.copyWith(color: Colors.white.withValues(alpha: 0.6)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
