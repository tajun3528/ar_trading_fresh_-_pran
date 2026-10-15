import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/auto_refresh_mixin.dart';
import '../../core/providers.dart';
import '../../models/company.dart';
import 'report_data.dart';
import '../../core/design/design_tokens.dart';
import '../../core/motion/skeleton.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> with AutoRefreshMixin<ReportsScreen> {
  DateTimeRange _range = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 30)),
    end: DateTime.now(),
  );
  String? _companyId;
  late Future<ReportData> _future;

  @override
  void refreshData() => setState(() { _future = _load(); });

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<ReportData> _load() {
    final client = ref.read(insforgeClientProvider);
    return ReportData.load(client, _range.start, _range.end, companyId: _companyId);
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

  Future<void> _exportCsv(String title, List<List<Object>> rows) async {
    final csv = const ListToCsvConverter().convert(rows);
    await Share.share(
      csv,
      subject: '$title (${DateFormat.yMd().format(_range.start)} - ${DateFormat.yMd().format(_range.end)})',
    );
  }

  @override
  Widget build(BuildContext context) {
    final companies = ref.watch(companiesProvider).valueOrNull ?? const <Company>[];
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            // Wrap (not Row) so the date range keeps the left edge and the
            // controls the right on a wide screen, but drop onto their own
            // line instead of overflowing once the window narrows.
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.date_range, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('${DateFormat.yMMMd().format(_range.start)} — ${DateFormat.yMMMd().format(_range.end)}'),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: DropdownButton<String?>(
                        value: _companyId,
                        isExpanded: true,
                        hint: const Text('All companies', overflow: TextOverflow.ellipsis),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('All companies')),
                          for (final c in companies)
                            DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (id) => setState(() {
                          _companyId = id;
                          _future = _load();
                        }),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(onPressed: _pickRange, child: const Text('Change range')),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<ReportData>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return Padding(padding: const EdgeInsets.all(AppSpace.md), child: const SkeletonTable());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Failed to load report: ${snapshot.error}'));
                }
                final data = snapshot.data!;
                return DefaultTabController(
                  length: 3,
                  child: Column(
                    children: [
                      const TabBar(
                        isScrollable: true,
                        tabs: [
                          Tab(text: 'By Product'),
                          Tab(text: 'By Salesman'),
                          Tab(text: 'Stock'),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text('Total revenue: ৳${data.totalRevenue.toStringAsFixed(2)}',
                            style: Theme.of(context).textTheme.titleMedium),
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _ReportTable(
                              rows: data.byProduct,
                              onExport: () => _exportCsv('Sales by product', [
                                ['Product', 'Quantity', 'Revenue'],
                                for (final r in data.byProduct) [r.name, r.quantity, r.revenue],
                              ]),
                            ),
                            _ReportTable(
                              rows: data.bySalesman,
                              onExport: () => _exportCsv('Sales by salesman', [
                                ['Salesman', 'Quantity', 'Revenue'],
                                for (final r in data.bySalesman) [r.name, r.quantity, r.revenue],
                              ]),
                            ),
                            _StockTable(
                              rows: data.stockMovement,
                              onExport: () => _exportCsv('Stock movement', [
                                ['Product', 'Unit', 'Stock In', 'Returned Good', 'Damaged', 'Available', 'Damaged Stock'],
                                for (final r in data.stockMovement)
                                  [
                                    r.productName,
                                    r.unitType.label,
                                    r.stockIn,
                                    r.returnedGood,
                                    r.damaged,
                                    r.closingAvailable,
                                    r.closingDamaged,
                                  ],
                              ]),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportTable extends StatelessWidget {
  const _ReportTable({required this.rows, required this.onExport});

  final List<ReportRow> rows;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(onPressed: onExport, icon: const Icon(Icons.ios_share), label: const Text('Export CSV')),
        ),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('No data for this range.'))
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final r = rows[index];
                    return ListTile(
                      title: Text(r.name),
                      subtitle: Text('Qty: ${r.quantity}'),
                      trailing: Text('৳${r.revenue.toStringAsFixed(2)}'),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _StockTable extends StatelessWidget {
  const _StockTable({required this.rows, required this.onExport});

  final List<StockMovementRow> rows;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(onPressed: onExport, icon: const Icon(Icons.ios_share), label: const Text('Export CSV')),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final r = rows[index];
              return ListTile(
                title: Text('${r.productName} (${r.unitType.label})'),
                subtitle: Text('In: ${r.stockIn} • Returned: ${r.returnedGood} • Damaged: ${r.damaged}'),
                trailing: Text('${r.closingAvailable} available'),
              );
            },
          ),
        ),
      ],
    );
  }
}
