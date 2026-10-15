import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// One person's own settings. Stored per user in the database rather than in
/// the browser, so they follow whoever signs in rather than whichever machine
/// they happen to be at.
class UserPreferences {
  const UserPreferences({
    this.themeMode = ThemeMode.light,
    this.textScale = AppTheme.textScale,
    this.density = AppDensity.compact,
    this.accent = AppAccent.indigo,
    this.reduceMotion = false,
    this.landingRoute,
    this.notifyAwaitingApproval = true,
    this.notifyRejected = true,
    this.notifyApproved = true,
    this.notifyOrderChanges = true,
  });

  /// What a person sees before they have changed anything — the app's
  /// original house style.
  static const defaults = UserPreferences();

  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    return UserPreferences(
      themeMode: switch (json['theme_mode'] as String?) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      textScale: (json['text_scale'] as num?)?.toDouble() ?? AppTheme.textScale,
      density: AppDensity.parse(json['density'] as String?),
      accent: AppAccent.parse(json['accent'] as String?),
      reduceMotion: json['reduce_motion'] as bool? ?? false,
      landingRoute: json['landing_route'] as String?,
      notifyAwaitingApproval: json['notify_awaiting_approval'] as bool? ?? true,
      notifyRejected: json['notify_rejected'] as bool? ?? true,
      notifyApproved: json['notify_approved'] as bool? ?? true,
      notifyOrderChanges: json['notify_order_changes'] as bool? ?? true,
    );
  }

  final ThemeMode themeMode;
  final double textScale;
  final AppDensity density;
  final AppAccent accent;

  /// Suppresses every animation in the app. On by choice for anyone who finds
  /// motion distracting, or whose phone struggles with it.
  final bool reduceMotion;

  /// Where signing in lands. Null keeps the role's own home page.
  final String? landingRoute;

  final bool notifyAwaitingApproval;
  final bool notifyRejected;
  final bool notifyApproved;

  /// Orders being booked, changed or cancelled — by a salesman, or by a
  /// delivery man adding to a round in the field.
  final bool notifyOrderChanges;

  String get themeModeId => switch (themeMode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

  /// Whether a notification of [kind] should reach this person's bell.
  bool allows(String kind) {
    switch (kind) {
      case 'delivery_awaiting_approval':
        return notifyAwaitingApproval;
      case 'delivery_rejected':
        return notifyRejected;
      case 'delivery_approved':
        return notifyApproved;
      case 'order_changed':
        return notifyOrderChanges;
      default:
        return true;
    }
  }

  UserPreferences copyWith({
    ThemeMode? themeMode,
    double? textScale,
    AppDensity? density,
    AppAccent? accent,
    bool? reduceMotion,
    Object? landingRoute = _unset,
    bool? notifyAwaitingApproval,
    bool? notifyRejected,
    bool? notifyApproved,
    bool? notifyOrderChanges,
  }) {
    return UserPreferences(
      themeMode: themeMode ?? this.themeMode,
      textScale: textScale ?? this.textScale,
      density: density ?? this.density,
      accent: accent ?? this.accent,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      landingRoute: identical(landingRoute, _unset) ? this.landingRoute : landingRoute as String?,
      notifyAwaitingApproval: notifyAwaitingApproval ?? this.notifyAwaitingApproval,
      notifyRejected: notifyRejected ?? this.notifyRejected,
      notifyApproved: notifyApproved ?? this.notifyApproved,
      notifyOrderChanges: notifyOrderChanges ?? this.notifyOrderChanges,
    );
  }

  static const _unset = Object();
}
