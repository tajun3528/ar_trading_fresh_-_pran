import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auto_refresh_mixin.dart';
import '../../core/providers.dart';
import '../../core/viz/status_breakdown_bar.dart';
import '../../core/viz/status_palette.dart';
import '../../models/company.dart';
import '../../models/daily_summary.dart';
import 'summary_list_tile.dart';
import 'summary_status_chip.dart';
import '../../core/design/design_tokens.dart';
import '../../core/motion/skeleton.dart';

class OwnerSummariesScreen extends ConsumerStatefulWidget {
  const OwnerSummariesScreen({super.key});

  @override
  ConsumerState<OwnerSummariesScreen> createState() => _OwnerSummariesScreenState();
}

class _OwnerSummariesScreenState extends ConsumerState<OwnerSummariesScreen>
    with AutoRefreshMixin<OwnerSummariesScreen> {
  late Future<(List<DailySummary>, Map<String, String>)> _future;
  String? _companyId;

  @override
  void refreshData() => setState(() { _future = _load(); });

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  /// How many summaries to pull at a time. The table grows forever, so it is
  /// read a page at a time — a flat cap would silently stop showing older
  /// orders with nothing on screen to say so.
  static const _pageSize = 200;

  /// Whether the last fetch filled a whole page, i.e. there is probably more
  /// behind it.
  bool _hasMore = false;
  int _pages = 1;

  Future<(List<DailySummary>, Map<String, String>)> _load() async {
    final client = ref.read(insforgeClientProvider);
    var query = client.from('daily_summaries').select();
    final companyId = _companyId;
    if (companyId != null) query = query.eq('company_id', companyId);
    final wanted = _pageSize * _pages;
    final rows = await query.order('submission_date', ascending: false).limit(wanted).get();
    final summaries = rows.map(DailySummary.fromJson).toList();
    _hasMore = summaries.length == wanted;
    final profileRows = await client.from('profiles').select('user_id,name').get();
    final salesmanNames = {for (final p in profileRows) p['user_id'] as String: p['name'] as String};
    return (summaries, salesmanNames);
  }

  @override
  Widget build(BuildContext context) {
    final companies = ref.watch(companiesProvider).valueOrNull ?? const <Company>[];
    final companyNames = {for (final c in companies) c.id: c.name};
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              const Spacer(),
              DropdownButton<String?>(
                value: _companyId,
                hint: const Text('All companies'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All companies')),
                  for (final c in companies) DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (id) => setState(() {
                  _companyId = id;
                  _pages = 1;
                  _future = _load();
                }),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => setState(() { _future = _load(); }),
            child: FutureBuilder<(List<DailySummary>, Map<String, String>)>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return Padding(padding: const EdgeInsets.all(AppSpace.md), child: const SkeletonTable());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Failed to load summaries: ${snapshot.error}'));
                }
                final (summaries, salesmanNames) = snapshot.data!;
                if (summaries.isEmpty) {
                  return const Center(child: Text('No daily summaries submitted yet.'));
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
                        Text('Last ${summaries.length} summaries by status',
                            style: Theme.of(context).textTheme.titleSmall),
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
                        columns: [
                          const DataColumn(label: Text('Submitted')),
                          const DataColumn(label: Text('Salesman')),
                          if (_companyId == null) const DataColumn(label: Text('Company')),
                          const DataColumn(label: Text('Delivery')),
                          const DataColumn(label: Text('Total')),
                          const DataColumn(label: Text('Commission')),
                          const DataColumn(label: Text('Net')),
                          const DataColumn(label: Text('Status')),
                        ],
                        rows: [
                          for (final summary in summaries)
                            DataRow(
                              onSelectChanged: (_) => context.go('/owner/summaries/${summary.id}'),
                              cells: [
                                DataCell(Text(DateFormat.yMMMd().format(summary.submissionDate))),
                                DataCell(Text(
                                  salesmanNames[summary.salesmanId] ?? 'Salesman',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                )),
                                if (_companyId == null)
                                  DataCell(Text(companyNames[summary.companyId] ?? '—')),
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                  child: Column(
                    children: [
                      Text(
                        _hasMore
                            ? 'Showing the ${summaries.length} most recent orders.'
                            : 'That is all ${summaries.length} order${summaries.length == 1 ? '' : 's'}.',
                        style: const TextStyle(fontSize: 12, color: VizChrome.secondaryInk),
                        textAlign: TextAlign.center,
                      ),
                      if (_hasMore) ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () => setState(() {
                            _pages += 1;
                            _future = _load();
                          }),
                          icon: const Icon(Icons.expand_more, size: 16),
                          label: const Text('Load older'),
                        ),
                      ],
                    ],
                  ),
                ),
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
