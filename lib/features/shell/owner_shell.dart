import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/design/design_tokens.dart';
import '../../core/motion/motion.dart';
import '../../core/motion/page_transition.dart';
import '../../core/viz/status_palette.dart';
import '../notifications/notification_bell.dart';

class OwnerShell extends ConsumerWidget {
  const OwnerShell({required this.child, super.key});

  final Widget child;

  /// Grouped rather than one flat run: seventeen equal-weight items read as
  /// an undifferentiated list, and nothing tells you that Stock and Products
  /// belong together while Profit and ETP belong elsewhere.
  static const _groups = <(String, List<(String, IconData, String)>)>[
    ('', [
      ('/owner/dashboard', Icons.dashboard, 'Dashboard'),
    ]),
    ('Catalog', [
      ('/owner/products', Icons.inventory_2, 'Products & Prices'),
      ('/owner/categories', Icons.category, 'Categories'),
      ('/owner/stock', Icons.warehouse, 'Stock'),
      ('/owner/expiry', Icons.event_busy, 'Expiry Watch'),
    ]),
    ('Operations', [
      ('/owner/new-order', Icons.add_shopping_cart, 'Book an Order'),
      ('/owner/summaries', Icons.receipt_long, 'Daily Summaries'),
      ('/owner/deliveries', Icons.local_shipping, 'Deliveries'),
      ('/owner/returns', Icons.undo, 'Returns & Damage'),
      ('/owner/routes', Icons.alt_route, 'Routes'),
    ]),
    ('Money', [
      ('/owner/profit', Icons.savings, 'Profit & Targets'),
      ('/owner/etp', Icons.price_change, 'ETP Prices'),
      ('/owner/product-sales', Icons.leaderboard, 'Sales by Product'),
      ('/owner/performance', Icons.groups, 'Salesmen & Routes'),
      ('/owner/reports', Icons.bar_chart, 'Reports'),
    ]),
    ('System', [
      ('/owner/users', Icons.people, 'Users'),
      ('/owner/audit', Icons.history_edu, 'Audit Log'),
      ('/owner/profile', Icons.person_outline, 'Profile'),
    ]),
  ];

  /// Flat view of the same items, for resolving the current page title.
  static List<(String, IconData, String)> get _destinations =>
      [for (final g in _groups) ...g.$2];

  // Below this, a permanent sidebar would crowd out the content — fall back
  // to the familiar app bar + drawer instead.
  static const _wideBreakpoint = 900.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final current = _destinations.firstWhere(
      (d) => location.startsWith(d.$1),
      orElse: () => _destinations.first,
    );
    final name = ref.watch(authControllerProvider).valueOrNull?.name ?? 'Owner';
    void signOut() => ref.read(authControllerProvider.notifier).signOut();

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _wideBreakpoint) {
          return Scaffold(
            body: Row(
              children: [
                _OwnerSidebar(location: location, name: name, onSignOut: signOut, onNavigate: context.go),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 12, 12, 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                current.$3,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            const NotificationBell(),
                          ],
                        ),
                      ),
                      Expanded(child: AnimatedShellBody(routeKey: location, child: child)),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            backgroundColor: VizChrome.sidebarDark,
            foregroundColor: Colors.white,
            title: Text(current.$3),
            actions: [
              const NotificationBell(color: Colors.white),
              IconButton(icon: const Icon(Icons.logout), tooltip: 'Sign out', onPressed: signOut),
            ],
          ),
          drawer: Drawer(
            child: _OwnerSidebar(
              location: location,
              name: name,
              onSignOut: signOut,
              onNavigate: (path) {
                Navigator.of(context).pop();
                context.go(path);
              },
            ),
          ),
          body: AnimatedShellBody(routeKey: location, child: child),
        );
      },
    );
  }
}

class _OwnerSidebar extends StatelessWidget {
  const _OwnerSidebar({required this.location, required this.name, required this.onSignOut, required this.onNavigate});

  final String location;
  final String name;
  final VoidCallback onSignOut;
  final void Function(String path) onNavigate;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 248,
      // The same ground the sign-in screen uses, so the chrome and the front
      // door belong to one identity.
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [BrandPalette.groundLift, BrandPalette.ground],
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: VizChrome.sidebarActive, borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.storefront, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'AR-Trading',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final group in OwnerShell._groups) ...[
                    if (group.$1.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, AppSpace.lg, 12, AppSpace.sm),
                        child: Text(
                          group.$1.toUpperCase(),
                          style: AppType.caption.copyWith(
                            color: Colors.white.withValues(alpha: 0.42),
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                    for (final d in group.$2)
                      _NavItem(
                        path: d.$1,
                        icon: d.$2,
                        label: d.$3,
                        selected: location.startsWith(d.$1),
                        onTap: () => onNavigate(d.$1),
                      ),
                  ],
                  const SizedBox(height: AppSpace.lg),
                ],
              ),
            ),
            const Divider(color: Colors.white24, height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: VizChrome.sidebarActive,
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout, color: Colors.white70),
                    tooltip: 'Sign out',
                    onPressed: onSignOut,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// One sidebar row. The selected state used to be an instant colour swap;
/// now the highlight and its leading accent bar grow in, so moving through
/// the nav reads as continuous rather than as a series of jumps.
class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.path,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String path;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final reduce = reduceMotionOf(context);
    final duration = reduce ? Duration.zero : AppMotion.fast;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: duration,
            curve: AppMotion.standard,
            decoration: BoxDecoration(
              color: selected
                  ? VizChrome.sidebarActive
                  : _hovered
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.transparent,
              borderRadius: AppRadius.rMd,
            ),
            child: Row(
              children: [
                // A short accent bar that grows on the selected item — the
                // clearest "you are here" signal at a glance down the rail.
                AnimatedContainer(
                  duration: duration,
                  curve: AppMotion.enter,
                  width: 3,
                  height: selected ? 22 : 0,
                  margin: const EdgeInsets.only(right: 9),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.horizontal(right: Radius.circular(3)),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(left: selected ? 0 : 12),
                  child: Icon(
                    widget.icon,
                    color: Colors.white.withValues(alpha: selected ? 1 : 0.72),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      widget.label,
                      style: AppType.label.copyWith(
                        color: Colors.white.withValues(alpha: selected ? 1 : 0.78),
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
