import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auto_refresh_mixin.dart';
import '../../core/insforge/insforge_exception.dart';
import '../../core/providers.dart';
import '../../core/viz/status_palette.dart';
import '../../models/daily_summary.dart';
import '../../models/profile.dart';
import '../../models/profit.dart';
import '../../models/unit_type.dart';
import 'submit_summary_screen.dart';
import 'summary_status_chip.dart';
import '../../core/design/design_tokens.dart';
import '../../core/motion/skeleton.dart';

class SummaryDetailScreen extends ConsumerStatefulWidget {
  const SummaryDetailScreen({required this.summaryId, super.key});

  final String summaryId;

  @override
  ConsumerState<SummaryDetailScreen> createState() => _SummaryDetailScreenState();
}

class _SummaryDetailScreenState extends ConsumerState<SummaryDetailScreen>
    with AutoRefreshMixin<SummaryDetailScreen> {
  late Future<_SummaryDetailData> _future;

  @override
  void refreshData() => setState(() { _future = _load(); });

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_SummaryDetailData> _load() async {
    final client = ref.read(insforgeClientProvider);
    final summary =
        DailySummary.fromJson(await client.from('daily_summaries').select().eq('id', widget.summaryId).single());
    final itemRows = await client.from('daily_summary_items').select().eq('summary_id', widget.summaryId).get();
    final items = itemRows.map(DailySummaryItem.fromJson).toList();
    final productRows = await client.from('products').select('id,name').get();
    final productNames = {for (final p in productRows) p['id'] as String: p['name'] as String};

    // Empty until the delivery is approved — the view only covers approved
    // deliveries, so an un-delivered order simply has no profit row yet.
    final profitRows = await client.from('summary_profit').select().eq('summary_id', widget.summaryId).get();

    // A rejected report doesn't lock the order — the deliveryman has to file
    // a fresh one, and the salesman may well need to correct the order first.
    final deliveryRows =
        await client.from('deliveries').select('id,approval_status').eq('summary_id', widget.summaryId).get();
    final hasDelivery = deliveryRows.any((d) => d['approval_status'] != 'rejected');

    return _SummaryDetailData(
      summary,
      items,
      productNames,
      profitRows.isEmpty ? null : SummaryProfit.fromJson(profitRows.first),
      hasDelivery,
    );
  }

  Future<void> _cancel(DailySummary summary) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel summary?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes, cancel')),
        ],
      ),
    );
    if (confirmed != true) return;

    final client = ref.read(insforgeClientProvider);
    try {
      await client.rpc('cancel_daily_summary', {'p_summary_id': summary.id});
      setState(() { _future = _load(); });
    } on InsforgeException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authControllerProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Daily summary')),
      body: FutureBuilder<_SummaryDetailData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Padding(padding: const EdgeInsets.all(AppSpace.md), child: const SkeletonTable());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Failed to load summary: ${snapshot.error}'));
          }
          final data = snapshot.data!;
          final summary = data.summary;
          // The delivery date used to close this window, which locked a
          // same-day or back-dated order the moment it was entered. What
          // really matters is whether the van has been loaded off these lines.
          final canEdit = profile?.role == UserRole.salesman &&
              summary.salesmanId == profile?.userId &&
              summary.isEditable &&
              !data.hasDelivery;
          // The owner can run the round themselves when the delivery man is
          // away — the round is still recorded under that salesman's own
          // delivery man, so his history stays continuous.
          final canRunRound =
              profile?.role == UserRole.owner && summary.isEditable && !data.hasDelivery;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Delivery ${DateFormat.yMMMd().format(summary.deliveryDate)}',
                      style: Theme.of(context).textTheme.titleLarge),
                  SummaryStatusChip(status: summary.status),
                ],
              ),
              Text('Submitted: ${DateFormat.yMMMd().format(summary.submissionDate)}'),
              const Divider(height: 32),
              Text('Items', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Card(
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 32),
                    child: DataTable(
                                headingTextStyle: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: VizChrome.secondaryInk,
                      ),
                      dataTextStyle: const TextStyle(fontSize: 13),
                      columnSpacing: 18,
                      // One row per product with its units beside each other,
                      // the way the order and stock pages read — a product
                      // ordered in cartons and pieces is one line, not two.
                      columns: [
                        const DataColumn(label: Text('Product')),
                        for (final u in data.unitsUsed) DataColumn(label: Text(u.label)),
                        for (final u in data.unitsUsed) DataColumn(label: Text('${u.label} price')),
                        const DataColumn(label: Text('Line total')),
                      ],
                      rows: [
                        for (final productId in data.productIdsInOrder)
                          DataRow(cells: [
                            DataCell(Text(
                              data.productNames[productId] ?? 'Product',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            )),
                            for (final u in data.unitsUsed)
                              DataCell(Text(
                                data.itemFor(productId, u) == null
                                    ? '—'
                                    : '${data.itemFor(productId, u)!.quantity}',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              )),
                            for (final u in data.unitsUsed)
                              DataCell(Text(
                                data.itemFor(productId, u) == null
                                    ? '—'
                                    : '৳${data.itemFor(productId, u)!.unitPrice.toStringAsFixed(2)}',
                                style: const TextStyle(color: VizChrome.secondaryInk),
                              )),
                            DataCell(Text(
                              '৳${data.lineTotalFor(productId).toStringAsFixed(2)}',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            )),
                          ]),
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(height: 32),
              if (summary.commissionAmount > 0) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Order total'),
                    Text('৳${summary.totalAmount.toStringAsFixed(2)}'),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Commission'),
                    Text('−৳${summary.commissionAmount.toStringAsFixed(2)}'),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Net to Owner', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text('৳${summary.netAmount.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ] else
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text('৳${summary.totalAmount.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              if (data.profit case final profit?) ...[
                const SizedBox(height: 20),
                _ProfitCard(profit: profit),
              ],
              if (canRunRound) ...[
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => context.go('/owner/round/${summary.id}'),
                  icon: const Icon(Icons.local_shipping, size: 18),
                  label: const Text('Run this delivery myself'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                ),
                const SizedBox(height: 6),
                Text(
                  'Use this when the delivery man cannot. It is recorded under his name, '
                  'and the audit log notes that you ran it.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (canEdit) ...[
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          await Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => SubmitSummaryScreen(
                              existingSummary: summary,
                              existingItems: data.items,
                            ),
                          ));
                          setState(() { _future = _load(); });
                        },
                        child: const Text('Edit summary'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: () => _cancel(summary),
                        child: const Text('Cancel summary'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SummaryDetailData {
  _SummaryDetailData(this.summary, this.items, this.productNames, this.profit, this.hasDelivery);

  final DailySummary summary;
  final List<DailySummaryItem> items;
  final Map<String, String> productNames;

  /// Once the van has been loaded the delivery lines are built off these
  /// items, so the order can't be changed under them any more.
  final bool hasDelivery;

  /// Only the units this order actually uses, largest first — no empty
  /// columns for units nothing on the order is sold in.
  List<UnitType> get unitsUsed => const [UnitType.carton, UnitType.box, UnitType.poli, UnitType.jar, UnitType.pcs]
      .where((u) => items.any((i) => i.unitType == u))
      .toList();

  List<String> get productIdsInOrder {
    final ids = <String>[];
    for (final item in items) {
      if (!ids.contains(item.productId)) ids.add(item.productId);
    }
    ids.sort((a, b) => (productNames[a] ?? '').compareTo(productNames[b] ?? ''));
    return ids;
  }

  DailySummaryItem? itemFor(String productId, UnitType unit) {
    for (final item in items) {
      if (item.productId == productId && item.unitType == unit) return item;
    }
    return null;
  }

  double lineTotalFor(String productId) =>
      items.where((i) => i.productId == productId).fold(0, (sum, i) => sum + i.lineTotal);

  /// Only present once the delivery has been approved — until then there is
  /// no delivered quantity to work a profit out from.
  final SummaryProfit? profit;
}

/// What the order actually earned, shown once its delivery is approved.
class _ProfitCard extends StatelessWidget {
  const _ProfitCard({required this.profit});

  final SummaryProfit profit;

  @override
  Widget build(BuildContext context) {
    Widget line(String label, double value, {bool negative = false, bool bold = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
            Text(
              '${negative ? '−' : ''}৳${value.abs().toStringAsFixed(2)}',
              style: TextStyle(
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                color: bold
                    ? (profit.orderProfit >= 0 ? StatusLevel.good.color : StatusLevel.critical.color)
                    : negative
                        ? StatusLevel.serious.color
                        : null,
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Profit on this order', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            line('Delivered at selling prices', profit.revenue),
            line('Cost of goods (DP)', profit.dpValue, negative: true),
            const Divider(height: 16),
            line('Margin over DP', profit.profit1),
            line('Company commission on DP', profit.profit2),
            if (profit.commissionAmount > 0) line('Salesman commission', profit.commissionAmount, negative: true),
            const Divider(height: 16),
            line('Order profit', profit.orderProfit, bold: true),
            if (profit.hasGaps) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: StatusLevel.warning.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  [
                    if (profit.linesMissingPrice > 0)
                      '${profit.linesMissingPrice} line(s) have no selling price set for this month',
                    if (profit.linesMissingDp > 0)
                      '${profit.linesMissingDp} line(s) have no DP cost — set that unit\'s per-carton count',
                  ].join('\n'),
                  style: TextStyle(fontSize: 11, color: StatusLevel.warning.color, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
