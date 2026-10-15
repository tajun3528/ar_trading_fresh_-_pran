import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auto_refresh_mixin.dart';
import '../../core/providers.dart';
import '../../core/viz/status_breakdown_bar.dart';
import '../../core/viz/status_palette.dart';
import '../../models/daily_summary.dart';
import 'summary_list_tile.dart';
import 'summary_status_chip.dart';
import '../../core/design/design_tokens.dart';
import '../../core/motion/skeleton.dart';

class SalesmanSummariesScreen extends ConsumerStatefulWidget {
  const SalesmanSummariesScreen({super.key});

  @override
  ConsumerState<SalesmanSummariesScreen> createState() => _SalesmanSummariesScreenState();
}

class _SalesmanSummariesScreenState extends ConsumerState<SalesmanSummariesScreen>
    with AutoRefreshMixin<SalesmanSummariesScreen> {
  late Future<List<DailySummary>> _future;

  @override
  void refreshData() => setState(() { _future = _load(); });

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<DailySummary>> _load() async {
    final client = ref.read(insforgeClientProvider);
    final rows = await client.from('daily_summaries').select().order('submission_date', ascending: false).get();
    return rows.map(DailySummary.fromJson).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async => setState(() { _future = _load(); }),
        child: FutureBuilder<List<DailySummary>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return Padding(padding: const EdgeInsets.all(AppSpace.md), child: const SkeletonTable());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Failed to load summaries: ${snapshot.error}'));
            }
            final summaries = snapshot.data!;
            if (summaries.isEmpty) {
              return const Center(child: Text('No daily summaries submitted yet. Tap + to add one.'));
            }

            final statusCounts = <SummaryStatus, int>{};
            for (final s in summaries) {
              statusCounts[s.status] = (statusCounts[s.status] ?? 0) + 1;
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                // stretch (not start) so the cards fill the full page width
                // instead of shrinking to the table's own content width.
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Your summaries by status', style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 12),
                          StatusBreakdownBar(counts: [
                            StatusCount(
                              label: 'Submitted',
                              count: statusCounts[SummaryStatus.booked] ?? 0,
                              color: summaryStatusColor(SummaryStatus.booked),
                            ),
                            StatusCount(
                              label: 'Delivered',
                              count: statusCounts[SummaryStatus.delivered] ?? 0,
                              color: summaryStatusColor(SummaryStatus.delivered),
                            ),
                            StatusCount(
                              label: 'Partially delivered',
                              count: statusCounts[SummaryStatus.partiallyDelivered] ?? 0,
                              color: summaryStatusColor(SummaryStatus.partiallyDelivered),
                            ),
                            StatusCount(
                              label: 'Cancelled',
                              count: statusCounts[SummaryStatus.cancelled] ?? 0,
                              color: summaryStatusColor(SummaryStatus.cancelled),
                            ),
                          ]),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 24),
                        child: DataTable(
                          showCheckboxColumn: false,
                                        headingTextStyle: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: VizChrome.secondaryInk,
                          ),
                          dataTextStyle: const TextStyle(fontSize: 13),
                          columnSpacing: 24,
                          columns: const [
                            DataColumn(label: Text('Submitted')),
                            DataColumn(label: Text('Delivery')),
                            DataColumn(label: Text('Total')),
                            DataColumn(label: Text('Commission')),
                            DataColumn(label: Text('Net')),
                            DataColumn(label: Text('Status')),
                          ],
                          rows: [
                            for (final summary in summaries)
                              DataRow(
                                onSelectChanged: (_) => context.go('/salesman/summaries/${summary.id}'),
                                cells: [
                                  DataCell(Text(DateFormat.yMMMd().format(summary.submissionDate))),
                                  DataCell(Text(DateFormat.yMMMd().format(summary.deliveryDate))),
                                  DataCell(Text(
                                    '৳${summary.totalAmount.toStringAsFixed(2)}',
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  )),
                                  DataCell(Text(summary.commissionAmount > 0
                                      ? '৳${summary.commissionAmount.toStringAsFixed(2)}'
                                      : '—')),
                                  DataCell(Text('৳${summary.netAmount.toStringAsFixed(2)}')),
                                  DataCell(SummaryStatusChip(status: summary.status)),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/salesman/new-summary'),
        child: const Icon(Icons.add),
      ),
    );
  }
}
