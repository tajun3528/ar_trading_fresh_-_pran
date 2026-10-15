import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/motion/page_transition.dart';
import '../notifications/notification_bell.dart';

class SalesmanShell extends ConsumerWidget {
  const SalesmanShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AR-Trading'),
        actions: [
          const NotificationBell(),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      // IndexedStack swaps branches instantly, which left the navigation
      // bar's indicator sliding while the page under it snapped.
      body: AnimatedShellBody(routeKey: '${shell.currentIndex}', child: shell),
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (index) => shell.goBranch(index, initialLocation: index == shell.currentIndex),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.add_shopping_cart), label: 'New Summary'),
          NavigationDestination(icon: Icon(Icons.receipt_long), label: 'Summaries'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Sales'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'Stock'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}
