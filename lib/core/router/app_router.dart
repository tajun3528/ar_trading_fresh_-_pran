import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/pending_screen.dart';
import '../../features/auth/sign_in_screen.dart';
import '../../features/auth/sign_up_screen.dart';
import '../../features/audit/audit_log_screen.dart';
import '../../features/catalog/categories_screen.dart';
import '../../features/catalog/products_screen.dart';
import '../../features/dashboard/delivery_dashboard_screen.dart';
import '../../features/dashboard/owner_dashboard_screen.dart';
import '../../features/dashboard/salesman_dashboard_screen.dart';
import '../../features/pricing/etp_prices_screen.dart';
import '../../features/pricing/monthly_prices_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/profit/monthly_profit_screen.dart';
import '../../features/profit/performance_screen.dart';
import '../../features/delivery/delivery_round_screen.dart';
import '../../features/delivery/delivery_history_screen.dart';
import '../../features/delivery/delivery_list_screen.dart';
import '../../features/reports/product_sales_screen.dart';
import '../../features/reports/reports_screen.dart';
import '../../features/reports/salesman_sales_screen.dart';
import '../../features/returns/owner_returns_screen.dart';
import '../../features/routes/routes_screen.dart';
import '../../features/shell/delivery_shell.dart';
import '../../features/shell/owner_shell.dart';
import '../../features/shell/salesman_shell.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/stock/salesman_stock_screen.dart';
import '../../features/stock/expiry_screen.dart';
import '../../features/stock/stock_screen.dart';
import '../../features/summaries/new_order_choice_screen.dart';
import '../../features/summaries/owner_summaries_screen.dart';
import '../../features/summaries/quick_order_screen.dart';
import '../../features/summaries/salesman_summaries_screen.dart';
import '../../features/summaries/submit_summary_screen.dart';
import '../../features/summaries/summary_detail_screen.dart';
import '../../features/users/users_screen.dart';
import '../../models/profile.dart';
import '../auth/auth_controller.dart';
import '../motion/page_transition.dart';
import '../preferences/preferences_controller.dart';

class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(this.ref) {
    ref.listen(authControllerProvider, (previous, next) => notifyListeners());
  }

  final Ref ref;
}

final _routerRefreshProvider = Provider((ref) => _RouterRefreshNotifier(ref));

/// Where signing in lands. A person can pick their own opening page in
/// Profile; anything they have not chosen falls back to their role's home.
String _landingFor(UserRole role, String? preferred) {
  if (preferred == null || preferred.isEmpty) return _homeFor(role);
  // Never honour a page this role would just be bounced out of.
  final prefix = '/${role == UserRole.deliveryman ? 'delivery' : role.name}';
  return preferred.startsWith(prefix) ? preferred : _homeFor(role);
}

String _homeFor(UserRole role) {
  switch (role) {
    case UserRole.owner:
      return '/owner/dashboard';
    case UserRole.salesman:
      return '/salesman/dashboard';
    case UserRole.deliveryman:
      return '/delivery/dashboard';
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = ref.watch(_routerRefreshProvider);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final authState = ref.read(authControllerProvider);
      final loc = state.matchedLocation;

      if (authState.isLoading) {
        return loc == '/splash' ? null : '/splash';
      }

      final profile = authState.valueOrNull;
      final isAuthRoute = loc == '/login' || loc == '/signup';

      if (profile == null) {
        return isAuthRoute ? null : '/login';
      }

      if (!profile.isActive) {
        return loc == '/pending' ? null : '/pending';
      }

      if (isAuthRoute || loc == '/pending' || loc == '/splash') {
        final preferred = ref.read(preferencesProvider).valueOrNull?.landingRoute;
        return _landingFor(profile.role, preferred);
      }

      // Keep each role inside its own section of the app.
      final rolePrefix = '/${profile.role == UserRole.deliveryman ? 'delivery' : profile.role.name}';
      if (!loc.startsWith(rolePrefix)) {
        return _homeFor(profile.role);
      }

      return null;
    },
    routes: [
      GoRoute(path: '/splash', pageBuilder: (context, state) =>
                appPage(state: state, child: const SplashScreen())),
      GoRoute(path: '/login', pageBuilder: (context, state) =>
                appPage(state: state, child: const SignInScreen())),
      GoRoute(path: '/signup', pageBuilder: (context, state) =>
                appPage(state: state, child: const SignUpScreen())),
      GoRoute(path: '/pending', pageBuilder: (context, state) =>
                appPage(state: state, child: const PendingScreen())),

      ShellRoute(
        builder: (context, state, child) => OwnerShell(child: child),
        routes: [
          GoRoute(path: '/owner/dashboard', pageBuilder: (context, state) =>
                appPage(state: state, child: const OwnerDashboardScreen())),
          GoRoute(path: '/owner/users', pageBuilder: (context, state) =>
                appPage(state: state, child: const UsersScreen())),
          GoRoute(path: '/owner/categories', pageBuilder: (context, state) =>
                appPage(state: state, child: const CategoriesScreen())),
          GoRoute(path: '/owner/products', pageBuilder: (context, state) =>
                appPage(state: state, child: const ProductsScreen())),
          GoRoute(path: '/owner/stock', pageBuilder: (context, state) =>
                appPage(state: state, child: const StockScreen())),
          GoRoute(path: '/owner/routes', pageBuilder: (context, state) =>
                appPage(state: state, child: const RoutesScreen())),
          GoRoute(
            path: '/owner/summaries',
            pageBuilder: (context, state) =>
                appPage(state: state, child: const OwnerSummariesScreen()),
            routes: [
              GoRoute(
                path: ':id',
                pageBuilder: (context, state) =>
                appPage(state: state, child: SummaryDetailScreen(summaryId: state.pathParameters['id']!)),
              ),
            ],
          ),
          GoRoute(path: '/owner/deliveries', pageBuilder: (context, state) =>
                appPage(state: state, child: const DeliveryHistoryScreen(ownerView: true))),
          GoRoute(path: '/owner/returns', pageBuilder: (context, state) =>
                appPage(state: state, child: const OwnerReturnsScreen())),
          GoRoute(path: '/owner/profit', pageBuilder: (context, state) =>
                appPage(state: state, child: const MonthlyProfitScreen())),
          GoRoute(path: '/owner/etp', pageBuilder: (context, state) =>
                appPage(state: state, child: const EtpPricesScreen())),
          GoRoute(path: '/owner/product-sales', pageBuilder: (context, state) =>
                appPage(state: state, child: const ProductSalesScreen())),
          GoRoute(path: '/owner/performance', pageBuilder: (context, state) =>
                appPage(state: state, child: const PerformanceScreen())),
          GoRoute(path: '/owner/expiry', pageBuilder: (context, state) =>
                appPage(state: state, child: const ExpiryScreen())),
          GoRoute(path: '/owner/reports', pageBuilder: (context, state) =>
                appPage(state: state, child: const ReportsScreen())),
          GoRoute(path: '/owner/audit', pageBuilder: (context, state) =>
                appPage(state: state, child: const AuditLogScreen())),
          GoRoute(path: '/owner/profile', pageBuilder: (context, state) =>
                appPage(state: state, child: const ProfileScreen())),
          // The owner can stand in for either role: book an order when a
          // salesman is away, and run the round when the delivery man is.
          GoRoute(
            path: '/owner/new-order',
            pageBuilder: (context, state) =>
                appPage(state: state, child: const SubmitSummaryScreen()),
          ),
          GoRoute(
            path: '/owner/round/:summaryId',
            pageBuilder: (context, state) => appPage(
              state: state,
              child: DeliveryRoundScreen(summaryId: state.pathParameters['summaryId']!),
            ),
          ),
        ],
      ),

      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => SalesmanShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/salesman/dashboard', pageBuilder: (context, state) =>
                appPage(state: state, child: const SalesmanDashboardScreen())),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/salesman/new-summary',
              pageBuilder: (context, state) =>
                appPage(state: state, child: const NewOrderChoiceScreen()),
              routes: [
                GoRoute(path: 'full', pageBuilder: (context, state) =>
                appPage(state: state, child: const SubmitSummaryScreen())),
                GoRoute(path: 'quick', pageBuilder: (context, state) =>
                appPage(state: state, child: const QuickOrderScreen())),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/salesman/summaries',
              pageBuilder: (context, state) =>
                appPage(state: state, child: const SalesmanSummariesScreen()),
              routes: [
                GoRoute(
                  path: ':id',
                  pageBuilder: (context, state) =>
                appPage(state: state, child: SummaryDetailScreen(summaryId: state.pathParameters['id']!)),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/salesman/sales',
              pageBuilder: (context, state) =>
                appPage(state: state, child: const SalesmanSalesScreen()),
              routes: [
                GoRoute(path: 'prices', pageBuilder: (context, state) =>
                appPage(state: state, child: const MonthlyPricesScreen())),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/salesman/stock', pageBuilder: (context, state) =>
                appPage(state: state, child: const SalesmanStockScreen())),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/salesman/profile', pageBuilder: (context, state) =>
                appPage(state: state, child: const ProfileScreen())),
          ]),
        ],
      ),

      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => DeliveryShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/delivery/dashboard', pageBuilder: (context, state) =>
                appPage(state: state, child: const DeliveryDashboardScreen())),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/delivery/deliveries',
              pageBuilder: (context, state) =>
                appPage(state: state, child: const DeliveryListScreen()),
              routes: [
                GoRoute(
                  path: ':summaryId',
                  pageBuilder: (context, state) =>
                appPage(state: state, child: DeliveryRoundScreen(summaryId: state.pathParameters['summaryId']!)),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/delivery/history', pageBuilder: (context, state) =>
                appPage(state: state, child: const DeliveryHistoryScreen(ownerView: false))),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/delivery/profile', pageBuilder: (context, state) =>
                appPage(state: state, child: const ProfileScreen())),
          ]),
        ],
      ),
    ],
  );
});
