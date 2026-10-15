import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/insforge/insforge_exception.dart';
import '../../core/providers.dart';
import '../../core/viz/status_palette.dart';
import '../../models/daily_summary.dart';
import '../../models/delivery.dart';
import '../../models/unit_type.dart';
import '../../core/design/design_tokens.dart';
import '../../core/motion/skeleton.dart';

final _money = NumberFormat('#,##0.00');

class _ApprovalLine {
  _ApprovalLine({
    required this.productName,
    required this.unitLabel,
    required this.requested,
    required this.loaded,
    required this.delivered,
    required this.returned,
    required this.damaged,
    required this.unitPrice,
  });

  final String productName;
  final String unitLabel;
  final int requested;
  final int loaded;
  final int delivered;
  final int returned;
  final int damaged;
  final double unitPrice;

  double get deliveredValue => delivered * unitPrice;
  double get damagedValue => damaged * unitPrice;
}

/// Damaged or expired stock collected back from shops during the round —
/// any catalog product, so it stands apart from the order's own lines.
class _DamageLine {
  _DamageLine({
    required this.productName,
    required this.unitLabel,
    required this.quantity,
    required this.lineTotal,
  });

  final String productName;
  final String unitLabel;
  final int quantity;
  final double lineTotal;
}

class _ApprovalData {
  _ApprovalData({
    required this.delivery,
    required this.summary,
    required this.salesmanName,
    required this.lines,
    required this.damages,
  });

  final Delivery delivery;
  final DailySummary summary;
  final String salesmanName;
  final List<_ApprovalLine> lines;
  final List<_DamageLine> damages;

  double get deliveredValue => lines.fold(0, (sum, l) => sum + l.deliveredValue);
  double get damagedValue => damages.fold(0, (sum, d) => sum + d.lineTotal);
  int get damagedUnits => damages.fold(0, (sum, d) => sum + d.quantity);
  int get returnedUnits => lines.fold(0, (sum, l) => sum + l.returned);

  /// One entry per product with its units beside it, matching the order and
  /// stock pages rather than a row per unit.
  List<String> get productNames {
    final seen = <String>[];
    for (final line in lines) {
      if (!seen.contains(line.productName)) seen.add(line.productName);
    }
    seen.sort();
    return seen;
  }

  List<String> get unitLabels {
    final seen = <String>[];
    for (final label in const ['Carton', 'Box', 'Poli', 'Jar', 'Piece']) {
      if (lines.any((l) => l.unitLabel == label)) seen.add(label);
    }
    return seen;
  }

  _ApprovalLine? lineFor(String productName, String unitLabel) {
    for (final line in lines) {
      if (line.productName == productName && line.unitLabel == unitLabel) return line;
    }
    return null;
  }
}

/// The Owner's review of a deliveryman's claim — approving is what actually
/// decrements stock and turns the summary into a counted sale.
class DeliveryApprovalScreen extends ConsumerStatefulWidget {
  const DeliveryApprovalScreen({required this.deliveryId, super.key});

  final String deliveryId;

  @override
  ConsumerState<DeliveryApprovalScreen> createState() => _DeliveryApprovalScreenState();
}

class _DeliveryApprovalScreenState extends ConsumerState<DeliveryApprovalScreen> {
  late Future<_ApprovalData> _future;
  bool _acting = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ApprovalData> _load() async {
    final client = ref.read(insforgeClientProvider);
    final delivery = Delivery.fromJson(await client.from('deliveries').select().eq('id', widget.deliveryId).single());
    final summary =
        DailySummary.fromJson(await client.from('daily_summaries').select().eq('id', delivery.summaryId).single());
    final profileRow =
        await client.from('profiles').select('name').eq('user_id', summary.salesmanId).maybeSingle();
    final salesmanName = profileRow?['name'] as String? ?? 'Salesman';

    final deliveryItemRows = await client.from('delivery_items').select().eq('delivery_id', widget.deliveryId).get();
    final summaryItemRows = await client.from('daily_summary_items').select().eq('summary_id', delivery.summaryId).get();
    final summaryItemsById = {for (final row in summaryItemRows) row['id'] as String: DailySummaryItem.fromJson(row)};
    final productRows = await client.from('products').select('id,name').get();
    final productNames = {for (final p in productRows) p['id'] as String: p['name'] as String};

    final lines = [
      for (final row in deliveryItemRows)
        if (summaryItemsById[row['summary_item_id'] as String] case final summaryItem?)
          _ApprovalLine(
            productName: productNames[summaryItem.productId] ?? 'Product',
            unitLabel: summaryItem.unitType.label,
            requested: summaryItem.quantity,
            loaded: (row['loaded_quantity'] as int?) ?? 0,
            delivered: row['delivered_quantity'] as int,
            returned: (row['returned_quantity'] as int?) ?? 0,
            damaged: (row['damaged_quantity'] as int?) ?? 0,
            unitPrice: summaryItem.unitPrice,
          ),
    ];

    final damageRows = await client.from('delivery_damages').select().eq('delivery_id', widget.deliveryId).get();
    final damages = [
      for (final row in damageRows)
        _DamageLine(
          productName: productNames[row['product_id'] as String] ?? 'Product',
          unitLabel: UnitType.parse(row['unit_type'] as String).label,
          quantity: row['quantity'] as int,
          lineTotal: (row['line_total'] as num).toDouble(),
        ),
    ]..sort((a, b) => a.productName.compareTo(b.productName));

    return _ApprovalData(
      delivery: delivery,
      summary: summary,
      salesmanName: salesmanName,
      lines: lines,
      damages: damages,
    );
  }

  /// The two things approval actually commits: the cash the deliveryman owes,
  /// and the stock that is about to move. Worth seeing before deciding.
  Widget _buildMoneyCard(BuildContext context, _ApprovalData data) {
    final commission = data.summary.commissionAmount;
    Widget line(String label, double value, {bool negative = false, bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: TextStyle(fontSize: bold ? 14 : 13, fontWeight: bold ? FontWeight.w800 : null)),
              ),
              Text(
                '${negative ? '−' : ''}৳${_money.format(value.abs())}',
                style: TextStyle(
                  fontSize: bold ? 15 : 13,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  color: negative ? StatusLevel.serious.color : (bold ? StatusLevel.good.color : null),
                ),
              ),
            ],
          ),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cash and stock', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            line('Ordered', data.summary.totalAmount),
            line('Delivered goods', data.deliveredValue),
            if (commission > 0) line("Salesman's commission", commission, negative: true),
            if (data.damagedValue > 0) line('Broken goods', data.damagedValue, negative: true),
            const Divider(height: 16),
            line('Cash to hand over', data.delivery.paymentAmount ?? 0, bold: true),
            if (data.damagedUnits > 0 || data.returnedUnits > 0) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: StatusLevel.warning.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  [
                    if (data.damagedUnits > 0)
                      'Approving moves ${data.damagedUnits} broken unit(s) out of sellable stock '
                          'and into your damage count.',
                    if (data.returnedUnits > 0)
                      '${data.returnedUnits} unit(s) came back unsold and stay in stock.',
                  ].join('\n'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: StatusLevel.warning.color,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _decide({required bool approve, String? reason}) async {
    setState(() => _acting = true);
    final client = ref.read(insforgeClientProvider);
    try {
      if (approve) {
        await client.rpc('approve_delivery', {'p_delivery_id': widget.deliveryId});
      } else {
        await client.rpc('reject_delivery', {'p_delivery_id': widget.deliveryId, 'p_reason': reason});
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(approve ? 'Delivery approved — stock and sales updated' : 'Delivery rejected')),
        );
        context.pop();
      }
    } on InsforgeException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  /// One of the round's three views — out, back or sold — one row per product
  /// with its units beside each other. [quantityOf] picks the figure shown.
  Widget _buildRoundTable(
    BuildContext context,
    _ApprovalData data,
    int Function(_ApprovalLine line) quantityOf, {
    bool showValue = false,
    bool hideEmptyRows = false,
  }) {
    var names = data.productNames;
    // The "back" table is usually mostly zeroes — listing every product would
    // bury the few that actually came back.
    if (hideEmptyRows) {
      names = names
          .where((n) => data.lines.any((l) => l.productName == n && quantityOf(l) > 0))
          .toList();
    }

    if (names.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(hideEmptyRows ? 'Nothing came back on this round.' : 'Nothing went out on this round.'),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) => Card(
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
                headingTextStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: VizChrome.secondaryInk,
              ),
              dataTextStyle: const TextStyle(fontSize: 13),
              columnSpacing: 16,
              columns: [
                const DataColumn(label: Text('Product')),
                for (final u in data.unitLabels) DataColumn(label: Text(u)),
                if (showValue) const DataColumn(label: Text('Value')),
              ],
              rows: [
                for (final name in names)
                  DataRow(
                    cells: [
                      DataCell(Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
                      for (final u in data.unitLabels)
                        DataCell(Builder(builder: (context) {
                          final line = data.lineFor(name, u);
                          if (line == null) {
                            return const Text('—', style: TextStyle(color: VizChrome.muted));
                          }
                          final qty = quantityOf(line);
                          if (qty <= 0) {
                            return const Text('—', style: TextStyle(color: VizChrome.muted));
                          }
                          return Text(
                            '$qty',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              // On the sold table, short-delivered lines are
                              // the ones worth a second look before approving.
                              color: !showValue
                                  ? null
                                  : line.delivered < line.requested
                                      ? StatusLevel.warning.color
                                      : StatusLevel.good.color,
                            ),
                          );
                        })),
                      if (showValue)
                        DataCell(Text(
                          '৳${_money.format(data.lines.where((l) => l.productName == name).fold<double>(0, (s, l) => s + quantityOf(l) * l.unitPrice))}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        )),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmReject() async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject this delivery report?'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(labelText: 'Reason (optional)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reject')),
        ],
      ),
    );
    if (confirmed == true) {
      _decide(approve: false, reason: reasonController.text.trim().isEmpty ? null : reasonController.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Review delivery')),
      body: FutureBuilder<_ApprovalData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Padding(padding: const EdgeInsets.all(AppSpace.md), child: const SkeletonTable());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Failed to load: ${snapshot.error}'));
          }
          final data = snapshot.data!;
          final delivery = data.delivery;
          final isPending = delivery.approvalStatus == DeliveryApprovalStatus.pending;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('From ${data.salesmanName}', style: Theme.of(context).textTheme.titleLarge),
                  ApprovalStatusChip(status: delivery.approvalStatus),
                ],
              ),
              Text(
                DateFormat.yMMMd().add_jm().format(delivery.deliveryDatetime),
                style: const TextStyle(color: VizChrome.secondaryInk),
              ),
              if (delivery.rejectionReason != null) ...[
                const SizedBox(height: 8),
                Text('Rejected: ${delivery.rejectionReason}', style: TextStyle(color: StatusLevel.critical.color)),
              ],
              const Divider(height: 32),
              _buildMoneyCard(context, data),
              const SizedBox(height: 16),
              // Three tables rather than one: interleaving out/back/sold
              // across five units ran to fifteen quantity columns and could
              // not be read across.
              Text('Product out', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              _buildRoundTable(context, data, (l) => l.loaded),
              const SizedBox(height: 16),
              Text('Product back', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              _buildRoundTable(context, data, (l) => l.returned, hideEmptyRows: true),
              const SizedBox(height: 16),
              Text('Product sold', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              _buildRoundTable(context, data, (l) => l.delivered, showValue: true),
              if (data.damages.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Damaged / expired collected from shops',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (final damage in data.damages)
                        ListTile(
                          dense: true,
                          title: Text('${damage.productName} · ${damage.unitLabel}'),
                          subtitle: Text('${damage.quantity} collected back'),
                          trailing: Text(
                            '−৳${_money.format(damage.lineTotal)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: StatusLevel.serious.color,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              if (isPending) ...[
                const Divider(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _acting ? null : _confirmReject,
                        child: const Text('Reject'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _acting ? null : () => _decide(approve: true),
                        child: _acting
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Approve'),
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

class ApprovalStatusChip extends StatelessWidget {
  const ApprovalStatusChip({required this.status, super.key});

  final DeliveryApprovalStatus status;

  (Color, IconData) get _visual {
    switch (status) {
      case DeliveryApprovalStatus.pending:
        return (VizChrome.info, Icons.schedule);
      case DeliveryApprovalStatus.approved:
        return (StatusLevel.good.color, StatusLevel.good.icon);
      case DeliveryApprovalStatus.rejected:
        return (StatusLevel.critical.color, StatusLevel.critical.icon);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (color, icon) = _visual;
    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(status.label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );
  }
}
