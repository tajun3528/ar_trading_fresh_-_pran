import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auto_refresh_mixin.dart';
import '../../core/providers.dart';
import '../../models/daily_summary.dart';
import '../summaries/summary_status_chip.dart';
import '../../core/design/design_tokens.dart';
import '../../core/motion/skeleton.dart';

class SalesmanSalesScreen extends ConsumerStatefulWidget {
  const SalesmanSalesScreen({super.key});

  @override
  ConsumerState<SalesmanSalesScreen> createState() => _SalesmanSalesScreenState();
}

class _SalesmanSalesScreenState extends ConsumerState<SalesmanSalesScreen>
    with AutoRefreshMixin<SalesmanSalesScreen> {
  DateTimeRange _range = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 30)),
    end: DateTime.now(),
  );
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
    String fmt(DateTime d) => d.toIso8601String().substring(0, 10);
    final rows = await client
        .from('daily_summaries')
        .select()
        .gte('submission_date', fmt(_range.start))
        .lte('submission_date', fmt(_range.end))
        .order('submission_date', ascending: false)
        .get();
    return rows.map(DailySummary.fromJson).toList();
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _range,
    );
    if (picked != null) {
      setState(() {
        _range = picked;
        _future = _load();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text('${DateFormat.yMMMd().format(_range.start)} — ${DateFormat.yMMMd().format(_range.end)}'),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () => context.go('/salesman/sales/prices'),
                    icon: const Icon(Icons.sell_outlined, size: 16),
                    label: const Text('Monthly prices'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: _pickRange, child: const Text('Change range')),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<DailySummary>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return Padding(padding: const EdgeInsets.all(AppSpace.md), child: const SkeletonTable());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Failed to load sales: ${snapshot.error}'));
              }
              final summaries = snapshot.data!;
              final total = summaries.fold<double>(0, (s, o) => s + o.totalAmount);
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${summaries.length} summaries'),
                        Text('Total: ৳${total.toStringAsFixed(2)}',
                            style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                  ),
                  Expanded(
                    child: summaries.isEmpty
                        ? const Center(child: Text('No summaries in this range.'))
                        : ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: summaries.length,
                            itemBuilder: (context, index) {
                              final summary = summaries[index];
                              return Card(
                                child: ListTile(
                                  title: Text(DateFormat.yMMMd().format(summary.submissionDate)),
                                  subtitle: Text(
                                      'Delivery: ${DateFormat.yMMMd().format(summary.deliveryDate)}'),
                                  // A ListTile caps how tall `trailing` may be,
                                  // and the amount plus the status chip sit a
                                  // couple of pixels over it. Let the column
                                  // shrink to the space rather than overflow.
                                  trailing: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text('৳${summary.totalAmount.toStringAsFixed(2)}'),
                                        SummaryStatusChip(status: summary.status),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
