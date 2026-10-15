import 'package:flutter/material.dart';

import '../viz/status_palette.dart';

/// The app's brand colours, promoted from the sign-in screen so the rest of
/// the app can share the one identity instead of each screen inventing its
/// own. `auth_scaffold.dart` consumes these rather than defining them.
class BrandPalette {
  BrandPalette._();

  /// The immersive dark ground, used behind sign-in, splash and nav chrome —
  /// never behind a table, where it would cost readability.
  ///
  /// Deliberately a deep indigo rather than a near-black: this is the tone the
  /// sidebar carried for months, and dropping below it drains the colour out
  /// and just reads as black. [groundLift] is the same hue brought up, so a
  /// gradient between them stays indigo the whole way down.
  static const ground = Color(0xFF201C4A);
  static const groundLift = Color(0xFF2E2872);

  /// The brand hue. Also the app's default accent.
  static const indigo = VizChrome.sidebarActive;
  static const teal = Color(0xFF17A99A);
  static const plum = Color(0xFF8E5FB8);

  /// The sharp plane that sits in front of everything else.
  static const card = Color(0xFFFBF9F4);
  static const ink = VizChrome.sidebarDark;
  static const inkSoft = Color(0xFF5A5775);

  /// The brand gradient, for the logo mark, nav chrome and hero bands.
  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [indigo, plum],
  );
}

/// One type scale, replacing the 17 distinct hardcoded `fontSize` values that
/// had accumulated across the screens.
///
/// Sizes are chosen to read correctly through the app's text-scale setting
/// (88% by default — see `UserPreferences.textScale`), so they look larger
/// here than they render.
class AppType {
  AppType._();

  /// Hero figures on a dashboard. One per screen at most.
  static const display = TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.1);

  /// A screen or major section title.
  static const titleL = TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.2, height: 1.2);

  /// A card heading.
  static const titleM = TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.25);

  /// A sub-heading inside a card, and table column headers.
  static const titleS = TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.3);

  /// Default reading size — table cells, field values, paragraphs.
  static const body = TextStyle(fontSize: 13.5, height: 1.45);

  /// Secondary text: captions under a value, helper lines.
  static const bodyS = TextStyle(fontSize: 12.5, height: 1.4);

  /// Field labels and chips — short, emphasised, never a sentence.
  static const label = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.3);

  /// The smallest readable size. Timestamps, footnotes, units.
  static const caption = TextStyle(fontSize: 11, height: 1.35);

  /// Money and quantities. Tabular figures keep columns aligned as values
  /// change — which matters once numbers animate.
  static const numeric = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w700,
    height: 1.3,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// A large animated figure on a metric tile.
  static const numericLarge = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w800,
    height: 1.1,
    letterSpacing: -0.4,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

/// Four corner radii, replacing the ten that had accumulated.
class AppRadius {
  AppRadius._();

  /// Chips, badges, small inline markers.
  static const double sm = 6;

  /// Inputs, buttons, table cells — the default.
  static const double md = 10;

  /// Cards and sheets.
  static const double lg = 14;

  /// Fully rounded: avatars, pills, nav indicators.
  static const double pill = 999;

  static const rSm = BorderRadius.all(Radius.circular(sm));
  static const rMd = BorderRadius.all(Radius.circular(md));
  static const rLg = BorderRadius.all(Radius.circular(lg));
  static const rPill = BorderRadius.all(Radius.circular(pill));
}

/// The spacing step. Everything is a multiple of 4 so rhythm stays consistent
/// whichever screen you are on.
class AppSpace {
  AppSpace._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  static const gapXs = SizedBox(height: xs, width: xs);
  static const gapSm = SizedBox(height: sm, width: sm);
  static const gapMd = SizedBox(height: md, width: md);
  static const gapLg = SizedBox(height: lg, width: lg);
  static const gapXl = SizedBox(height: xl, width: xl);
}

/// Every duration and curve in the app, in one place, so motion feels like it
/// came from one hand rather than from whoever wrote each screen.
class AppMotion {
  AppMotion._();

  /// Hover, press, colour changes — fast enough to feel instant.
  static const fast = Duration(milliseconds: 140);

  /// The default: entrances, cross-fades, expanding panels.
  static const normal = Duration(milliseconds: 260);

  /// Page transitions and anything crossing a large distance.
  static const slow = Duration(milliseconds: 380);

  /// Counting figures and charts drawing themselves — long enough to read as
  /// deliberate, short enough not to delay the number you came for.
  static const count = Duration(milliseconds: 850);

  /// One shimmer sweep across a skeleton.
  static const shimmer = Duration(milliseconds: 1250);

  /// The gap between one staggered child and the next.
  static const stagger = Duration(milliseconds: 45);

  /// Decelerating — things arriving on screen.
  static const enter = Curves.easeOutCubic;

  /// Accelerating — things leaving.
  static const exit = Curves.easeInCubic;

  /// Symmetrical — things changing in place.
  static const standard = Curves.easeInOut;

  /// A little overshoot, for the one element that should feel lively.
  static const emphasised = Curves.easeOutBack;

  /// How many items may stagger individually before a list animates as one
  /// unit instead. Above this, per-child animation costs more than it adds —
  /// the catalog screens render well over a hundred rows.
  static const int staggerLimit = 20;
}

/// The elevation recipe, lifted from the sign-in card so every raised surface
/// in the app casts the same shadow: one tight contact shadow directly under
/// the object, and one soft ambient shadow further out.
class AppElevation {
  AppElevation._();

  /// Resting card.
  static List<BoxShadow> card(BuildContext context) => _shadow(context, contact: 0.10, ambient: 0.06, y: 2, blur: 10);

  /// A card under the pointer.
  static List<BoxShadow> hover(BuildContext context) => _shadow(context, contact: 0.16, ambient: 0.10, y: 6, blur: 18);

  /// Dialogs, menus, and the sign-in card — clearly in front of everything.
  static List<BoxShadow> lifted(BuildContext context) => _shadow(context, contact: 0.24, ambient: 0.16, y: 14, blur: 34);

  static List<BoxShadow> _shadow(
    BuildContext context, {
    required double contact,
    required double ambient,
    required double y,
    required double blur,
  }) {
    // Shadows have to be heavier on a dark ground to register at all.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scale = isDark ? 1.9 : 1.0;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: (contact * scale).clamp(0.0, 1.0)),
        blurRadius: blur,
        spreadRadius: -blur / 5,
        offset: Offset(0, y),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: (ambient * scale).clamp(0.0, 1.0)),
        blurRadius: blur / 2.5,
        spreadRadius: -blur / 8,
        offset: Offset(0, y / 3),
      ),
    ];
  }
}
