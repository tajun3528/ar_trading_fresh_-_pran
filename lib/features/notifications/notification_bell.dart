import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auto_refresh_mixin.dart';
import '../../core/preferences/preferences_controller.dart';
import '../../core/providers.dart';
import '../../core/viz/status_palette.dart';
import '../../models/notification.dart';
import '../../core/design/design_tokens.dart';
import '../../core/motion/skeleton.dart';

Future<List<AppNotification>> _loadNotifications(WidgetRef ref) async {
  final client = ref.read(insforgeClientProvider);
  final rows =
      await client.from('notifications').select().order('created_at', ascending: false).limit(50).get();
  // Anything this person has switched off in Profile never reaches the bell.
  // Filtered on the way in rather than at the database, so turning a kind
  // back on shows the ones raised while it was off.
  final prefs = ref.read(effectivePreferencesProvider);
  return rows.map(AppNotification.fromJson).where((n) => prefs.allows(n.kind)).toList();
}

/// An app-bar bell carrying its own unread count. Lives in all three shells,
/// because all three roles are waiting on something someone else does.
class NotificationBell extends ConsumerStatefulWidget {
  const NotificationBell({this.color, super.key});

  final Color? color;

  @override
  ConsumerState<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends ConsumerState<NotificationBell>
    with AutoRefreshMixin<NotificationBell> {
  late Future<List<AppNotification>> _future;

  @override
  void refreshData() => setState(() { _future = _loadNotifications(ref); });

  @override
  void initState() {
    super.initState();
    _future = _loadNotifications(ref);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AppNotification>>(
      future: _future,
      builder: (context, snapshot) {
        final unread = snapshot.data?.where((n) => n.isUnread).length ?? 0;
        return IconButton(
          tooltip: unread == 0 ? 'Notifications' : '$unread unread',
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            constraints: const BoxConstraints(maxWidth: 520),
            builder: (_) => const NotificationSheet(),
          ),
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                unread > 0 ? Icons.notifications_active : Icons.notifications_none,
                color: widget.color,
              ),
              if (unread > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    constraints: const BoxConstraints(minWidth: 16),
                    decoration: BoxDecoration(
                      color: StatusLevel.critical.color,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 1.5),
                    ),
                    child: Text(
                      unread > 9 ? '9+' : '$unread',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The list behind the bell. Opens as a sheet rather than a page so you never
/// lose the screen you were working on to check a notification.
class NotificationSheet extends ConsumerStatefulWidget {
  const NotificationSheet({super.key});

  @override
  ConsumerState<NotificationSheet> createState() => _NotificationSheetState();
}

class _NotificationSheetState extends ConsumerState<NotificationSheet>
    with AutoRefreshMixin<NotificationSheet> {
  late Future<List<AppNotification>> _future;

  @override
  void refreshData() {
    if (mounted) setState(() { _future = _loadNotifications(ref); });
  }

  @override
  void initState() {
    super.initState();
    _future = _loadNotifications(ref);
  }

  Future<void> _markAllRead() async {
    await ref.read(insforgeClientProvider).rpc('mark_notifications_read', <String, dynamic>{});
    refreshData();
  }

  Future<void> _openItem(AppNotification item) async {
    if (item.isUnread) {
      await ref.read(insforgeClientProvider).rpc('mark_notifications_read', {
        'p_ids': [item.id],
      });
    }
    if (!mounted) return;
    final link = item.link;
    Navigator.of(context).pop();
    if (link != null) context.go(link);
  }

  static IconData _iconFor(String kind) {
    switch (kind) {
      case 'delivery_awaiting_approval':
        return Icons.pending_actions;
      case 'delivery_rejected':
        return Icons.report_problem;
      case 'delivery_approved':
        return Icons.check_circle;
      case 'order_changed':
        return Icons.edit_note;
      default:
        return Icons.notifications;
    }
  }

  static Color _colorFor(String kind) {
    switch (kind) {
      case 'delivery_awaiting_approval':
        return VizChrome.info;
      case 'delivery_rejected':
        return StatusLevel.critical.color;
      case 'delivery_approved':
        return StatusLevel.good.color;
      case 'order_changed':
        return VizChrome.accentIndigo;
      default:
        return VizChrome.secondaryInk;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        child: FutureBuilder<List<AppNotification>>(
          future: _future,
          builder: (context, snapshot) {
            final items = snapshot.data;
            final hasUnread = items?.any((n) => n.isUnread) ?? false;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
                  child: Row(
                    children: [
                      Expanded(child: Text('Notifications', style: Theme.of(context).textTheme.titleMedium)),
                      if (hasUnread) TextButton(onPressed: _markAllRead, child: const Text('Mark all read')),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(child: _body(snapshot)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _body(AsyncSnapshot<List<AppNotification>> snapshot) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const Padding(padding: EdgeInsets.all(AppSpace.lg), child: SkeletonTable(rows: 4, columns: 2));
    }
    if (snapshot.hasError) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Could not load notifications: ${snapshot.error}'),
      );
    }
    final items = snapshot.data ?? const <AppNotification>[];
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_off_outlined, size: 34, color: VizChrome.secondaryInk),
            SizedBox(height: 10),
            Text('Nothing to report.', style: TextStyle(fontWeight: FontWeight.w600)),
            SizedBox(height: 4),
            Text(
              "You'll be told here when a round needs approving, or when a report is sent back.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: VizChrome.secondaryInk),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final item = items[i];
        return ListTile(
          onTap: () => _openItem(item),
          leading: Icon(_iconFor(item.kind), color: _colorFor(item.kind)),
          title: Text(
            item.title,
            style: TextStyle(fontWeight: item.isUnread ? FontWeight.w700 : FontWeight.w500, fontSize: 14),
          ),
          subtitle: item.body == null ? null : Text(item.body!, style: const TextStyle(fontSize: 12.5)),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(item.age, style: const TextStyle(fontSize: 11, color: VizChrome.secondaryInk)),
              if (item.isUnread) ...[
                const SizedBox(height: 4),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: _colorFor(item.kind), shape: BoxShape.circle),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
