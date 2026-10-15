import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/motion/motion.dart';
import 'core/preferences/preferences_controller.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: ArTradingApp()));
}

class ArTradingApp extends ConsumerWidget {
  const ArTradingApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    // Each person's own appearance settings, falling back to the house style
    // while they load so the first frame is never unstyled.
    final prefs = ref.watch(effectivePreferencesProvider);

    return MaterialApp.router(
      title: 'AR-Trading',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(accent: prefs.accent, density: prefs.density),
      darkTheme: AppTheme.dark(accent: prefs.accent, density: prefs.density),
      themeMode: prefs.themeMode,
      routerConfig: router,
      // Scales every label, including the many hardcoded font sizes across the
      // screens, so a person can fit more on screen or make it readable.
      // Clamped both ways: the app's dense tables assume a known scale, and
      // an OS-level setting on top of this one would overflow them.
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: prefs.textScale,
        maxScaleFactor: prefs.textScale,
        // Wraps the whole app, so "Reduce motion" switches off Flutter's own
        // route and widget animations too — not just this app's.
        child: MotionPreference(reduceMotion: prefs.reduceMotion, child: child!),
      ),
    );
  }
}
