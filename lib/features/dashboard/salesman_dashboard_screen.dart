import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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

class SalesmanDashboardScreen extends ConsumerStatefulWidget {
  const SalesmanDashboardScreen({super.key});

  @override
  ConsumerState<SalesmanDashboardScreen> createState() => _SalesmanDashboardScreenState();
}

class _SalesmanDashboardScreenState extends ConsumerState<SalesmanDashboardScreen>
    with AutoRefreshMixin<SalesmanDashboardScreen> {
  late Future<_SalesmanStats> _future;

  @override
  void refreshData() => setState(() { _future = _load(); });

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_SalesmanStats> _load() async {
    final client = ref.read(insforgeClientProvider);
    final today = DateTime.now().toIso8601String().substring(0, 10);

    final bookedToday = await client.from('daily_summaries').select('id').eq('submission_date', today).get();
    // Compared against each other for the progress meter below, so this must
    // be the same cohort as deliveredToday: everything scheduled for today's
    // delivery date, not what was submitted today (that's for tomorrow).
    final scheduledForToday = await client.from('daily_summaries').select('id,status').eq('delivery_date', today).get();
    final deliveredToday =
        scheduledForToday.where((r) => ['delivered', 'partially_delivered'].contains(r['status'])).length;

    final monthStart = DateTime(DateTime.now().year, DateTime.now().month, 1).toIso8601String().substring(0, 10);
    // Same definition as everywhere else "sales" is counted: only summaries
    // an Owner has approved delivery on. A booked-but-not-yet-approved order
    // isn't a sale yet.
    final monthSummaries = await client
        .from('daily_summaries')
        .select('total_amount')
        .gte('submission_date', monthStart)
        .inList('status', ['delivered', 'partially_delivered']).get();
    final monthTotal = monthSummaries.fold<double>(0, (s, o) => s + (o['total_amount'] as num).toDouble());

    final recentRows =
        await client.from('daily_summaries').select().order('submission_date', ascending: false).limit(6).get();
    final recentSummaries = recentRows.map(DailySummary.fromJson).toList();

    return _SalesmanStats(
      bookedToday: bookedToday.length,
      scheduledForToday: scheduledForToday.length,
      deliveredToday: deliveredToday,
      monthTotal: monthTotal,
      recentSummaries: recentSummaries,
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => setState(() { _future = _load(); }),
      child: FutureBuilder<_SalesmanStats>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Padding(padding: const EdgeInsets.all(AppSpace.md), child: const SkeletonDashboard());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Failed to load dashboard: ${snapshot.error}'));
          }
          final s = snapshot.data!;
          final completionRatio = s.scheduledForToday == 0 ? 0.0 : s.deliveredToday / s.scheduledForToday;
          final completionLevel = s.scheduledForToday == 0
              ? null
              : (s.deliveredToday >= s.scheduledForToday
                  ? StatusLevel.good
                  : (s.deliveredToday > 0 ? StatusLevel.warning : StatusLevel.serious));
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              StatGrid(tiles: [
                BoldStatCard(
                  label: "Tomorrow's summary",
                  value: '${s.bookedToday}',
                  countTo: s.bookedToday.toDouble(),
                  format: (v) => v.round().toString(),
                  delay: AppMotion.stagger * 0,
                  icon: Icons.add_shopping_cart,
                  color: VizChrome.accentIndigo,
                ),
                BoldStatCard(
                  label: "Today's delivered",
                  value: '${s.deliveredToday}',
                  countTo: s.deliveredToday.toDouble(),
                  format: (v) => v.round().toString(),
                  delay: AppMotion.stagger * 1,
                  icon: Icons.local_shipping,
                  color: VizChrome.accentTeal,
                ),
                BoldStatCard(
                  label: 'This month sales',
                  value: '৳${s.monthTotal.toStringAsFixed(0)}',
                  countTo: s.monthTotal,
                  format: (v) => '৳${v.toStringAsFixed(0)}',
                  delay: AppMotion.stagger * 2,
                  icon: Icons.trending_up,
                  color: VizChrome.accentPlum,
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
                      label: "Today's delivery progress",
                      trailing: '${s.deliveredToday} of ${s.scheduledForToday} delivered',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              DataTableCard(
                title: 'Recent summaries',
                emptyLabel: 'No summaries submitted yet.',
                columns: const ['Submitted', 'Delivery', 'Total', 'Status'],
                rows: [
                  for (final summary in s.recentSummaries)
                    [
                      Text(DateFormat.yMMMd().format(summary.submissionDate)),
                      Text(DateFormat.yMMMd().format(summary.deliveryDate)),
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

class _SalesmanStats {
  _SalesmanStats({
    required this.bookedToday,
    required this.scheduledForToday,
    required this.deliveredToday,
    required this.monthTotal,
    required this.recentSummaries,
  });

  final int bookedToday;
  final int scheduledForToday;
  final int deliveredToday;
  final double monthTotal;
  final List<DailySummary> recentSummaries;
}
