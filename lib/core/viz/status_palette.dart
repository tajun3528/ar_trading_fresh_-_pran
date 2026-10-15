import 'package:flutter/material.dart';

/// Fixed status colors — never themed, never reused as a categorical series
/// color. Always paired with an icon + label wherever shown (warning and
/// serious both sit under 3:1 contrast on a light surface, so color alone
/// isn't a safe signal on its own).
enum StatusLevel { good, warning, serious, critical }

extension StatusLevelVisual on StatusLevel {
  Color get color {
    switch (this) {
      case StatusLevel.good:
        return const Color(0xFF0CA30C);
      case StatusLevel.warning:
        return const Color(0xFFFAB219);
      case StatusLevel.serious:
        return const Color(0xFFEC835A);
      case StatusLevel.critical:
        return const Color(0xFFD03B3B);
    }
  }

  IconData get icon {
    switch (this) {
      case StatusLevel.good:
        return Icons.check_circle;
      case StatusLevel.warning:
        return Icons.warning_amber_rounded;
      case StatusLevel.serious:
        return Icons.error_outline;
      case StatusLevel.critical:
        return Icons.cancel;
    }
  }
}

/// Chart chrome shared by every viz widget in the app — hairline gridline,
/// muted ink, and the one informational (non-status) accent used for
/// "in progress" states like a freshly-booked summary.
class VizChrome {
  VizChrome._();

  static const track = Color(0xFFE1E0D9);
  static const muted = Color(0xFF898781);
  static const secondaryInk = Color(0xFF52514E);
  static const info = Color(0xFF2A78D6);

  /// Warm tint for table header rows.
  static const tableHeader = Color(0xFFF3EEDD);

  /// Fixed, deterministic per-metric colors for bold KPI cards whose number
  /// carries no health meaning (a plain count or total) — distinct from the
  /// status palette so they never get confused with good/warning/critical.
  static const accentIndigo = Color(0xFF4C4A9E);
  static const accentTeal = Color(0xFF0E8F82);
  static const accentPlum = Color(0xFF7A4FA0);
  static const accentSlate = Color(0xFF3D5A73);

  /// Sequential (magnitude-over-time) hues. Blue is the default single hue;
  /// when a second trend appears alongside it, it takes the next categorical
  /// slot's hue (orange) rather than a second arbitrary color.
  static const sequentialBlue = Color(0xFF2A78D6);
  static const sequentialOrange = Color(0xFFEB6834);

  /// Chrome for a shell that uses a persistent dark nav rail (Owner) — same
  /// indigo family as [accentIndigo], darkened for a background and
  /// brightened for the active/selected item against it.
  static const sidebarDark = Color(0xFF201C4A);
  static const sidebarActive = Color(0xFF5B57C9);
}
