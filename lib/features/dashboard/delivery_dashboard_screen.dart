import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auto_refresh_mixin.dart';
import '../../core/providers.dart';
import '../../core/viz/bold_stat_card.dart';
import '../../core/viz/data_table_card.dart';
import '../../core/viz/ratio_meter.dart';
import '../../core/viz/status_palette.dart';
import '../../models/daily_summary.dart';
import '../summaries/summary_status_chip.dart';
import 'stat_tile.dart';
import '../../core/design/design_tokens.dart';
import '../../core/motion/skeleton.dart';

class DeliveryDashboardScreen extends ConsumerStatefulWidget {
  const DeliveryDashboardScreen({super.key});

  @override
  ConsumerState<DeliveryDashboardScreen> createState() => _DeliveryDashboardScreenState();
}

class _DeliveryDashboardScreenState extends ConsumerState<DeliveryDashboardScreen>
    with AutoRefreshMixin<DeliveryDashboardScreen> {
  late Future<_DeliveryStats> _future;

  @override
  void refreshData() => setState(() { _future = _load(); });

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DeliveryStats> _load() async {
    final client = ref.read(insforgeClientProvider);
    final today = DateTime.now().toIso8601String().substring(0, 10);

    final scheduledRows = await client.from('daily_summaries').select().eq('delivery_date', today).get();
    final scheduledToday = scheduledRows.map(DailySummary.fromJson).toList();
    final pending = scheduledRows.where((o) => o['status'] == 'booked').length;
    final deliveredToday = await client.from('deliveries').select('id').gte('delivery_datetime', today).get();
    // Damage now comes back through the round itself (delivery_damages), not
    // the old standalone returns table, which nothing writes to any more.
    final todaysDeliveryIds = deliveredToday.map((d) => d['id'] as String).toList();
    final damageRows = todaysDeliveryIds.isEmpty
        ? <Map<String, dynamic>>[]
        : await client.from('delivery_damages').select('id').inList('delivery_id', todaysDeliveryIds).get();
    final damagedToday = damageRows.length;

    // "Returns" are now the unsold goods that came back in the van, which
    // live on the round's own lines.
    final returnLineRows = todaysDeliveryIds.isEmpty
        ? <Map<String, dynamic>>[]
        : await client
            .from('delivery_items')
            .select('id,returned_quantity')
            .inList('delivery_id', todaysDeliveryIds)
            .get();
    final returnsToday = returnLineRows.where((r) => ((r['returned_quantity'] as int?) ?? 0) > 0).length;

    final profileRows = await client.from('profiles').select('user_id,name').get();
    final salesmanNames = {for (final p in profileRows) p['user_id'] as String: p['name'] as String};

    return _DeliveryStats(
      totalScheduled: scheduledToday.length,
      pending: pending,
      deliveredToday: deliveredToday.length,
      returnsToday: returnsToday,
      damagedToday: damagedToday,
      scheduledToday: scheduledToday,
      salesmanNames: salesmanNames,
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => setState(() { _future = _load(); }),
      child: FutureBuilder<_DeliveryStats>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Padding(padding: const EdgeInsets.all(AppSpace.md), child: const SkeletonDashboard());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Failed to load dashboard: ${snapshot.error}'));
          }
          final s = snapshot.data!;
          final completionRatio = s.totalScheduled == 0 ? 0.0 : (s.totalScheduled - s.pending) / s.totalScheduled;
          final completionLevel = s.totalScheduled == 0
              ? null
              : (s.pending == 0
                  ? StatusLevel.good
                  : (s.pending < s.totalScheduled ? StatusLevel.warning : StatusLevel.serious));
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              StatGrid(tiles: [
                BoldStatCard(
                  label: "Today's deliveries",
                  value: '${s.totalScheduled}',
                  countTo: s.totalScheduled.toDouble(),
                  format: (v) => v.round().toString(),
                  delay: AppMotion.stagger * 0,
                  icon: Icons.local_shipping,
                  color: VizChrome.accentIndigo,
                ),
                BoldStatCard(
                  label: 'Pending',
                  value: '${s.pending}',
                  countTo: s.pending.toDouble(),
                  format: (v) => v.round().toString(),
                  delay: AppMotion.stagger * 1,
                  icon: Icons.pending_actions,
                  color: s.pending > 0 ? StatusLevel.warning.color : StatusLevel.good.color,
                ),
                BoldStatCard(
                  label: 'Delivered today',
                  value: '${s.deliveredToday}',
                  countTo: s.deliveredToday.toDouble(),
                  format: (v) => v.round().toString(),
                  delay: AppMotion.stagger * 2,
                  icon: Icons.check_circle,
                  color: VizChrome.accentTeal,
                ),
                BoldStatCard(
                  label: 'Returns today',
                  value: '${s.returnsToday}',
                  countTo: s.returnsToday.toDouble(),
                  format: (v) => v.round().toString(),
                  delay: AppMotion.stagger * 3,
                  icon: Icons.undo,
                  color: VizChrome.accentPlum,
                ),
                BoldStatCard(
                  label: 'Damaged today',
                  value: '${s.damagedToday}',
                  countTo: s.damagedToday.toDouble(),
                  format: (v) => v.round().toString(),
                  delay: AppMotion.stagger * 4,
                  icon: Icons.broken_image,
                  color: s.damagedToday > 0 ? StatusLevel.serious.color : StatusLevel.good.color,
                ),
              ]),
              if (completionLevel != null) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: RatioMeter(
                      ratio: completionRatio,
                      color: completionLevel.color,
                      label: "Today's route progress",
                      trailing: '${s.totalScheduled - s.pending} of ${s.totalScheduled} confirmed',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              DataTableCard(
                title: "Today's route",
                emptyLabel: 'Nothing scheduled for delivery today.',
                columns: const ['Salesman', 'Total', 'Status'],
                rows: [
                  for (final summary in s.scheduledToday)
                    [
                      Text(s.salesmanNames[summary.salesmanId] ?? 'Salesman'),
                      Text('৳${summary.totalAmount.toStringAsFixed(0)}'),
                      SummaryStatusChip(status: summary.status),
                    ],
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DeliveryStats {
  _DeliveryStats({
    required this.totalScheduled,
    required this.pending,
    required this.deliveredToday,
    required this.returnsToday,
    required this.damagedToday,
    required this.scheduledToday,
    required this.salesmanNames,
  });

  final int totalScheduled;
  final int pending;
  final int deliveredToday;
  final int returnsToday;
  final int damagedToday;
  final List<DailySummary> scheduledToday;
  final Map<String, String> salesmanNames;
}
