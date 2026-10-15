import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/user_preferences.dart';
import '../auth/auth_controller.dart';
import '../providers.dart';
import '../theme/app_theme.dart';

/// The signed-in person's settings, driving the theme at the app root.
///
/// Applied optimistically: a change shows immediately and is written behind
/// it, because waiting on a round trip to see a colour change makes the
/// setting feel broken. A failed write reverts and says so.
class PreferencesController extends AsyncNotifier<UserPreferences> {
  @override
  Future<UserPreferences> build() async {
    // Rebuilds on sign-in and sign-out, so one person's settings never carry
    // over to the next person at the same machine.
    final profile = await ref.watch(authControllerProvider.future);
    if (profile == null) return UserPreferences.defaults;

    try {
      final rows = await ref
          .read(insforgeClientProvider)
          .from('user_preferences')
          .select()
          .eq('user_id', profile.userId)
          .get();
      if (rows.isEmpty) return UserPreferences.defaults;
      return UserPreferences.fromJson(rows.first);
    } catch (_) {
      // Settings are a convenience — never block the app on them.
      return UserPreferences.defaults;
    }
  }

  /// Saves a patch of changed fields. [optimistic] is what the UI should show
  /// straight away.
  Future<void> _save(Map<String, dynamic> patch, UserPreferences optimistic) async {
    final previous = state.valueOrNull ?? UserPreferences.defaults;
    state = AsyncData(optimistic);
    try {
      await ref.read(insforgeClientProvider).rpc('save_my_preferences', {'p_patch': patch});
    } catch (e) {
      state = AsyncData(previous);
      rethrow;
    }
  }

  UserPreferences get _current => state.valueOrNull ?? UserPreferences.defaults;

  Future<void> setThemeMode(ThemeMode mode) {
    final next = _current.copyWith(themeMode: mode);
    return _save({'theme_mode': next.themeModeId}, next);
  }

  Future<void> setTextScale(double scale) {
    final next = _current.copyWith(textScale: scale);
    return _save({'text_scale': scale}, next);
  }

  Future<void> setDensity(AppDensity density) {
    final next = _current.copyWith(density: density);
    return _save({'density': density.id}, next);
  }

  Future<void> setAccent(AppAccent accent) {
    final next = _current.copyWith(accent: accent);
    return _save({'accent': accent.id}, next);
  }

  Future<void> setReduceMotion(bool value) {
    final next = _current.copyWith(reduceMotion: value);
    return _save({'reduce_motion': value}, next);
  }

  Future<void> setLandingRoute(String? route) {
    final next = _current.copyWith(landingRoute: route);
    return _save({'landing_route': route}, next);
  }

  Future<void> setNotify({bool? awaitingApproval, bool? rejected, bool? approved, bool? orderChanges}) {
    final next = _current.copyWith(
      notifyAwaitingApproval: awaitingApproval,
      notifyRejected: rejected,
      notifyApproved: approved,
      notifyOrderChanges: orderChanges,
    );
    return _save({
      'notify_awaiting_approval': ?awaitingApproval,
      'notify_rejected': ?rejected,
      'notify_approved': ?approved,
      'notify_order_changes': ?orderChanges,
    }, next);
  }

  /// Back to the app's house style, in one action.
  Future<void> resetAppearance() {
    const d = UserPreferences.defaults;
    final next = _current.copyWith(
      themeMode: d.themeMode,
      textScale: d.textScale,
      density: d.density,
      accent: d.accent,
    );
    return _save({
      'theme_mode': d.themeModeId,
      'text_scale': d.textScale,
      'density': d.density.id,
      'accent': d.accent.id,
    }, next);
  }
}

final preferencesProvider =
    AsyncNotifierProvider<PreferencesController, UserPreferences>(PreferencesController.new);

/// The settings to render with right now. Falls back to the house style while
/// they load, so the first frame is never unstyled.
final effectivePreferencesProvider = Provider<UserPreferences>((ref) {
  return ref.watch(preferencesProvider).valueOrNull ?? UserPreferences.defaults;
});
