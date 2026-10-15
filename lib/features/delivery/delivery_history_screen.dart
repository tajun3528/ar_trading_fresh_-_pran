import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auto_refresh_mixin.dart';
import '../../core/providers.dart';
import '../../core/viz/status_palette.dart';
import '../../models/delivery.dart';
import 'delivery_approval_screen.dart';
import '../../core/design/design_tokens.dart';
import '../../core/motion/skeleton.dart';

final _money = NumberFormat('#,##0.00');

class _Row {
  _Row({
    required this.delivery,
    required this.salesman,
    required this.route,
    required this.deliveryDate,
    required this.orderTotal,
  });

  final Delivery delivery;
  final String salesman;
  final String route;
  final DateTime? deliveryDate;
  final double orderTotal;

  /// Where this round has got to, in the deliveryman's own terms.
  String get stage {
    if (delivery.approvalStatus == DeliveryApprovalStatus.approved) return 'Approved';
    if (delivery.approvalStatus == DeliveryApprovalStatus.rejected) return 'Rejected';
    return delivery.isOutForDelivery ? 'Out for delivery' : 'Awaiting approval';
  }

  Color get stageColor {
    switch (delivery.approvalStatus) {
      case DeliveryApprovalStatus.approved:
        return StatusLevel.good.color;
      case DeliveryApprovalStatus.rejected:
        return StatusLevel.critical.color;
      case DeliveryApprovalStatus.pending:
        return delivery.isOutForDelivery ? VizChrome.info : StatusLevel.warning.color;
    }
  }
}

/// Every delivery round, laid out like the Stock page: one wide table, sorted
/// most recent first, with the rounds still needing the Owner's approval
/// called out at the top.
class DeliveryHistoryScreen extends ConsumerStatefulWidget {
  const DeliveryHistoryScreen({required this.ownerView, super.key});

  final bool ownerView;

  @override
  ConsumerState<DeliveryHistoryScreen> createState() => _DeliveryHistoryScreenState();
}

class _DeliveryHistoryScreenState extends ConsumerState<DeliveryHistoryScreen>
    with AutoRefreshMixin<DeliveryHistoryScreen> {
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

  Future<List<_Row>> _load() async {
    final client = ref.read(insforgeClientProvider);
    final deliveryRows =
        await client.from('deliveries').select().order('delivery_datetime', ascending: false).limit(100).get();
    final deliveries = deliveryRows.map(Delivery.fromJson).toList();
    if (deliveries.isEmpty) return [];

    final summaryIds = deliveries.map((d) => d.summaryId).toSet().toList();
    final summaryRows = await client
        .from('daily_summaries')
        .select('id,salesman_id,route_id,delivery_date,total_amount')
        .inList('id', summaryIds)
        .get();
    final summaryById = {for (final s in summaryRows) s['id'] as String: s};

    final salesmanIds = summaryRows.map((s) => s['salesman_id'] as String).toSet().toList();
    final names = <String, String>{};
    if (salesmanIds.isNotEmpty) {
      final profileRows = await client.from('profiles').select('user_id,name').inList('user_id', salesmanIds).get();
      names.addAll({for (final p in profileRows) p['user_id'] as String: p['name'] as String});
    }

    final routeRows = await client.from('routes').select('id,name').get();
    final routeNames = {for (final r in routeRows) r['id'] as String: r['name'] as String};

    return [
      for (final delivery in deliveries)
        if (summaryById[delivery.summaryId] case final summary?)
          _Row(
            delivery: delivery,
            salesman: names[summary['salesman_id'] as String] ?? 'Salesman',
            route: routeNames[summary['route_id'] as String? ?? ''] ?? '—',
            deliveryDate: summary['delivery_date'] == null
                ? null
                : DateTime.parse(summary['delivery_date'] as String),
            orderTotal: (summary['total_amount'] as num).toDouble(),
          ),
    ];
  }

  Future<void> _open(_Row row) async {
    if (!widget.ownerView) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DeliveryApprovalScreen(deliveryId: row.delivery.id)),
    );
    setState(() { _future = _load(); });
  }

  Widget _buildTable(BuildContext context, List<_Row> rows, double minWidth) {
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
              DataColumn(label: Text('Cash to hand over')),
              DataColumn(label: Text('Stage')),
              DataColumn(label: Text('Reported')),
              DataColumn(label: Text('')),
            ],
            rows: [
              for (final row in rows)
                DataRow(
                  onSelectChanged: widget.ownerView ? (_) => _open(row) : null,
                  color: row.delivery.approvalStatus == DeliveryApprovalStatus.pending &&
                          !row.delivery.isOutForDelivery
                      ? WidgetStateProperty.all(StatusLevel.warning.color.withValues(alpha: 0.07))
                      : null,
                  cells: [
                    DataCell(Text(
                      row.deliveryDate == null ? '—' : DateFormat.yMMMd().format(row.deliveryDate!),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    )),
                    DataCell(Text(row.salesman)),
                    DataCell(Text(row.route)),
                    DataCell(Text('৳${_money.format(row.orderTotal)}')),
                    DataCell(Text(
                      row.delivery.paymentAmount == null
                          ? '—'
                          : '৳${_money.format(row.delivery.paymentAmount!)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    )),
                    DataCell(Text(
                      row.stage,
                      style: TextStyle(fontWeight: FontWeight.w700, color: row.stageColor),
                    )),
                    DataCell(Text(DateFormat.MMMd().add_jm().format(row.delivery.deliveryDatetime))),
                    DataCell(widget.ownerView
                        ? IconButton(
                            icon: const Icon(Icons.chevron_right, size: 18),
                            tooltip: 'Open',
                            onPressed: () => _open(row),
                          )
                        : const SizedBox.shrink()),
                  ],
                ),
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
                  return const Center(child: Text('No deliveries recorded yet.'));
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

                // Rounds already reported and sitting on the Owner's desk come
                // first — everything else is history they can scroll to.
                final waiting = rows
                    .where((r) =>
                        r.delivery.approvalStatus == DeliveryApprovalStatus.pending &&
                        !r.delivery.isOutForDelivery)
                    .toList();
                final rest = rows.where((r) => !waiting.contains(r)).toList();

                return LayoutBuilder(
                  builder: (context, constraints) => ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      if (widget.ownerView && waiting.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                          child: Text(
                            'Waiting for your approval (${waiting.length})',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        _buildTable(context, waiting, constraints.maxWidth - 24),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                          child: Text('Earlier rounds', style: Theme.of(context).textTheme.titleMedium),
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
