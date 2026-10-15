import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auto_refresh_mixin.dart';
import '../../core/providers.dart';
import '../../core/viz/status_palette.dart';
import '../../models/daily_summary.dart';
import '../../core/design/design_tokens.dart';
import '../../core/motion/skeleton.dart';

final _money = NumberFormat('#,##0.00');

class _Row {
  _Row({required this.summary, required this.salesman, required this.route, required this.stage});

  final DailySummary summary;
  final String salesman;
  final String route;

  /// Where this order stands for the deliveryman: nothing started, out on the
  /// road with returns still to record, or filed and waiting on the Owner.
  final String stage;

  Color get stageColor {
    switch (stage) {
      case 'Out for delivery':
        return StatusLevel.warning.color;
      case 'Awaiting approval':
        return VizChrome.info;
      default:
        return StatusLevel.good.color;
    }
  }
}

/// The deliveryman's round list, laid out like every other table in the app.
class DeliveryListScreen extends ConsumerStatefulWidget {
  const DeliveryListScreen({super.key});

  @override
  ConsumerState<DeliveryListScreen> createState() => _DeliveryListScreenState();
}

class _DeliveryListScreenState extends ConsumerState<DeliveryListScreen>
    with AutoRefreshMixin<DeliveryListScreen> {
  late Future<List<_Row>> _future;
  final _searchController = TextEditingController();
  String _search = '';

  @override
  void refreshData() => setState(() { _future = _load(); });

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // No delivery_date filter: an order appears the instant the salesman submits
  // it, sorted soonest-due first, which also surfaces anything overdue.
  Future<List<_Row>> _load() async {
    final client = ref.read(insforgeClientProvider);
    final rows = await client
        .from('daily_summaries')
        .select()
        .inList('status', ['booked', 'partially_delivered'])
        .order('delivery_date')
        .get();
    final summaries = rows.map(DailySummary.fromJson).toList();

    final profileRows = await client.from('profiles').select('user_id,name').get();
    final salesmanNames = {for (final p in profileRows) p['user_id'] as String: p['name'] as String};

    final routeRows = await client.from('routes').select('id,name').get();
    final routeNames = {for (final r in routeRows) r['id'] as String: r['name'] as String};

    // A pending delivery means one of two very different things: still out on
    // the road with returns to record, or finished and sitting with the Owner.
    final pendingRows = await client
        .from('deliveries')
        .select('summary_id,returns_recorded_at')
        .eq('approval_status', 'pending')
        .get();
    final awaitingApproval = {
      for (final row in pendingRows)
        if (row['returns_recorded_at'] != null) row['summary_id'] as String,
    };
    final outForDelivery = {
      for (final row in pendingRows)
        if (row['returns_recorded_at'] == null) row['summary_id'] as String,
    };

    return [
      for (final summary in summaries)
        _Row(
          summary: summary,
          salesman: salesmanNames[summary.salesmanId] ?? 'Salesman',
          route: routeNames[summary.routeId ?? ''] ?? '—',
          stage: outForDelivery.contains(summary.id)
              ? 'Out for delivery'
              : awaitingApproval.contains(summary.id)
                  ? 'Awaiting approval'
                  : 'Ready to load',
        ),
    ];
  }

  Widget _buildTable(BuildContext context, List<_Row> rows, double minWidth) {
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: minWidth),
          child: DataTable(
            showCheckboxColumn: false,
            headingTextStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: VizChrome.secondaryInk,
            ),
            dataTextStyle: const TextStyle(fontSize: 13),
            columnSpacing: 18,
            columns: const [
              DataColumn(label: Text('Delivery day')),
              DataColumn(label: Text('Salesman')),
              DataColumn(label: Text('Route')),
              DataColumn(label: Text('Order total')),
              DataColumn(label: Text('Stage')),
              DataColumn(label: Text('')),
            ],
            rows: [
              for (final row in rows)
                () {
                  final isOverdue = row.summary.deliveryDate.isBefore(todayOnly);
                  final isToday = row.summary.deliveryDate.isAtSameMomentAs(todayOnly);
                  return DataRow(
                    onSelectChanged: (_) => context.go('/delivery/deliveries/${row.summary.id}'),
                    color: isOverdue
                        ? WidgetStateProperty.all(StatusLevel.critical.color.withValues(alpha: 0.06))
                        : null,
                    cells: [
                      DataCell(Text(
                        isToday ? 'Today' : DateFormat.yMMMd().format(row.summary.deliveryDate),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isOverdue ? StatusLevel.critical.color : null,
                        ),
                      )),
                      DataCell(Text(row.salesman)),
                      DataCell(Text(row.route)),
                      DataCell(Text('৳${_money.format(row.summary.totalAmount)}')),
                      DataCell(Text(
                        row.stage,
                        style: TextStyle(fontWeight: FontWeight.w700, color: row.stageColor),
                      )),
                      DataCell(IconButton(
                        icon: const Icon(Icons.chevron_right, size: 18),
                        tooltip: 'Open round',
                        onPressed: () => context.go('/delivery/deliveries/${row.summary.id}'),
                      )),
                    ],
                  );
                }(),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search by salesman or route',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: _search.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() {
                        _searchController.clear();
                        _search = '';
                      }),
                    ),
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => setState(() { _future = _load(); }),
            child: FutureBuilder<List<_Row>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return Padding(padding: const EdgeInsets.all(AppSpace.md), child: const SkeletonTable());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Failed to load deliveries: ${snapshot.error}'));
                }
                final all = snapshot.data!;
                if (all.isEmpty) {
                  return const Center(child: Text('No pending deliveries.'));
                }
                final query = _search.trim().toLowerCase();
                final rows = query.isEmpty
                    ? all
                    : all
                        .where((r) =>
                            r.salesman.toLowerCase().contains(query) || r.route.toLowerCase().contains(query))
                        .toList();
                if (rows.isEmpty) {
                  return Center(child: Text('No deliveries match "${_search.trim()}".'));
                }

                // Rounds already on the road come first — that's the work in
                // hand, and it's the only state with something half-finished.
                final active = rows.where((r) => r.stage == 'Out for delivery').toList();
                final rest = rows.where((r) => r.stage != 'Out for delivery').toList();

                return LayoutBuilder(
                  builder: (context, constraints) => ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      if (active.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                          child: Text('On the road now', style: Theme.of(context).textTheme.titleMedium),
                        ),
                        _buildTable(context, active, constraints.maxWidth - 24),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                          child: Text('To deliver', style: Theme.of(context).textTheme.titleMedium),
                        ),
                      ],
                      if (rest.isNotEmpty) _buildTable(context, rest, constraints.maxWidth - 24),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
