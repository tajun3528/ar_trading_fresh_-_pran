import 'package:flutter/material.dart';

import '../design/design_tokens.dart';
import '../motion/motion.dart';
import '../motion/skeleton.dart';
import 'status_palette.dart';

/// One loading / error / empty treatment for the whole app.
///
/// Every screen used to hand-roll `Center(child: CircularProgressIndicator())`
/// and its own error and empty text, so all three states looked different
/// depending on where you were. This also swaps the spinner for a skeleton
/// shaped like the content that is coming, and cross-fades into the real
/// content rather than snapping.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    required this.future,
    required this.builder,
    this.skeleton,
    this.errorLabel = 'Could not load this',
    this.isEmpty,
    this.emptyTitle = 'Nothing here yet',
    this.emptyMessage,
    this.emptyIcon = Icons.inbox_outlined,
    this.emptyAction,
    super.key,
  });

  final Future<T>? future;
  final Widget Function(BuildContext context, T data) builder;

  /// The placeholder shown while loading. Shape it like the content — a
  /// [SkeletonTable] for a table screen, a [SkeletonDashboard] for a
  /// dashboard — so the page does not jump when the real thing arrives.
  final Widget? skeleton;

  final String errorLabel;

  /// Lets the caller decide what "no data" means for its own type.
  final bool Function(T data)? isEmpty;
  final String emptyTitle;
  final String? emptyMessage;
  final IconData emptyIcon;
  final Widget? emptyAction;

  @override
  Widget build(BuildContext context) {
    final reduce = reduceMotionOf(context);

    return FutureBuilder<T>(
      future: future,
      builder: (context, snapshot) {
        final Widget child;

        if (future == null || snapshot.connectionState != ConnectionState.done) {
          child = KeyedSubtree(
            key: const ValueKey('loading'),
            child: skeleton ?? const Padding(padding: EdgeInsets.all(AppSpace.md), child: SkeletonTable()),
          );
        } else if (snapshot.hasError) {
          child = KeyedSubtree(
            key: const ValueKey('error'),
            child: _ErrorState(label: errorLabel, error: snapshot.error!),
          );
        } else {
          final data = snapshot.data as T;
          if (isEmpty?.call(data) ?? false) {
            child = KeyedSubtree(
              key: const ValueKey('empty'),
              child: EmptyState(
                icon: emptyIcon,
                title: emptyTitle,
                message: emptyMessage,
                action: emptyAction,
              ),
            );
          } else {
            child = KeyedSubtree(key: const ValueKey('data'), child: builder(context, data));
          }
        }

        if (reduce) return child;
        return AnimatedSwitcher(
          duration: AppMotion.normal,
          switchInCurve: AppMotion.enter,
          switchOutCurve: AppMotion.exit,
          layoutBuilder: (currentChild, previousChildren) => Stack(
            fit: StackFit.expand,
            alignment: Alignment.topLeft,
            children: [...previousChildren, ?currentChild],
          ),
          child: child,
        );
      },
    );
  }
}

/// The app's empty state — an illustrated pause rather than a bare sentence,
/// because an empty screen is where someone most needs telling what to do.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    this.message,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Reveal(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      scheme.primary.withValues(alpha: 0.16),
                      scheme.primary.withValues(alpha: 0.04),
                    ],
                  ),
                ),
                child: Icon(icon, size: 30, color: scheme.primary),
              ),
              const SizedBox(height: AppSpace.lg),
              Text(title, textAlign: TextAlign.center, style: AppType.titleM.copyWith(color: scheme.onSurface)),
              if (message != null) ...[
                const SizedBox(height: AppSpace.xs),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: AppType.bodyS.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
              if (action != null) ...[const SizedBox(height: AppSpace.lg), action!],
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.label, required this.error});

  final String label;
  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 34, color: StatusLevel.critical.color),
            const SizedBox(height: AppSpace.md),
            Text(label, textAlign: TextAlign.center, style: AppType.titleM),
            const SizedBox(height: AppSpace.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Text(
                '$error',
                textAlign: TextAlign.center,
                style: AppType.caption.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
