import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../design/design_tokens.dart';

/// The app's page transition.
///
/// Every route used a plain `builder:`, so moving between the Owner's 17
/// pages hard-cut with no transition at all — and on the salesman and
/// delivery shells the navigation bar's indicator slid while the page under
/// it snapped, which is what made the app feel cheap.
///
/// A short fade with a small rise: enough to connect one page to the next,
/// never enough to delay someone who navigates all day. It reads as motion
/// without becoming a wait.
CustomTransitionPage<T> appPage<T>({
  required Widget child,
  required GoRouterState state,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: AppMotion.normal,
    reverseTransitionDuration: AppMotion.fast,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      // Honours both the person's "Reduce motion" setting and the OS switch —
      // MotionPreference forces disableAnimations, which zeroes the duration.
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;

      final curved = CurvedAnimation(parent: animation, curve: AppMotion.enter);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.012),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Cross-fades whatever is handed to it whenever the content changes.
///
/// Used for the Owner shell, whose `ShellRoute` swaps its `child` in place and
/// therefore never gets a page transition of its own, and for the two
/// `StatefulShellRoute.indexedStack` shells, where `IndexedStack` shows and
/// hides branches with no transition.
class AnimatedShellBody extends StatelessWidget {
  const AnimatedShellBody({required this.child, required this.routeKey, super.key});

  final Widget child;

  /// Changes when the visible page changes — the signal to cross-fade.
  final String routeKey;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    return AnimatedSwitcher(
      duration: AppMotion.normal,
      switchInCurve: AppMotion.enter,
      switchOutCurve: AppMotion.exit,
      // The default layout builder stacks outgoing and incoming children
      // centred, which makes a full page jump while it crossfades. Keeping
      // them top-left aligned and filling keeps the page still.
      layoutBuilder: (currentChild, previousChildren) => Stack(
        fit: StackFit.expand,
        alignment: Alignment.topLeft,
        children: [...previousChildren, ?currentChild],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.008), end: Offset.zero).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(routeKey), child: child),
    );
  }
}
