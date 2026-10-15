import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auto_refresh_mixin.dart';
import '../../core/company_selector.dart';
import '../../core/providers.dart';
import '../../core/viz/status_palette.dart';
import '../../models/company.dart';
import '../../models/performance.dart';
import '../../core/design/design_tokens.dart';
import '../../core/motion/skeleton.dart';

final _money = NumberFormat('#,##0.00');

class _PerformanceData {
  _PerformanceData({required this.salesmen, required this.routes});

  final List<PerformanceRow> salesmen;
  final List<PerformanceRow> routes;

  bool get isEmpty => salesmen.isEmpty && routes.isEmpty;
}

/// Who earned it, and where. The company's month tells you the total; this
/// tells you which salesman carried it and which route paid for the fuel.
class PerformanceScreen extends ConsumerStatefulWidget {
  const PerformanceScreen({super.key});

  @override
  ConsumerState<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends ConsumerState<PerformanceScreen>
    with AutoRefreshMixin<PerformanceScreen> {
  Company? _company;
  Future<_PerformanceData>? _future;
  late DateTime _month;

  @override
  void refreshData() => _reload();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  String get _basis => (_company?.costBasis ?? CompanyCostBasis.dp).label;
  String get _monthParam => DateFormat('yyyy-MM-01').format(_month);

  Future<_PerformanceData> _load(String companyId) async {
    final client = ref.read(insforgeClientProvider);

    final salesmanRows = await client
        .from('monthly_salesman_profit')
        .select()
        .eq('company_id', companyId)
        .eq('month', _monthParam)
        .get();
    final routeRows = await client
        .from('monthly_route_profit')
        .select()
        .eq('company_id', companyId)
        .eq('month', _monthParam)
        .get();

    // Names live on other tables; fetch only the ones actually referenced.
    final salesmanIds = salesmanRows.map((r) => r['salesman_id'] as String).toSet().toList();
    final routeIds = routeRows.map((r) => r['route_id'] as String).toSet().toList();

    final names = <String, String>{};
    if (salesmanIds.isNotEmpty) {
      final rows = await client.from('profiles').select('user_id,name').inList('user_id', salesmanIds).get();
      for (final r in rows) {
        names[r['user_id'] as String] = (r['name'] as String?) ?? 'Salesman';
      }
    }
    if (routeIds.isNotEmpty) {
      final rows = await client.from('routes').select('id,name').inList('id', routeIds).get();
      for (final r in rows) {
        names[r['id'] as String] = (r['name'] as String?) ?? 'Route';
      }
    }

    final salesmen = salesmanRows
        .map((r) => PerformanceRow.fromJson(r,
            idField: 'salesman_id', name: names[r['salesman_id']] ?? 'Salesman'))
        .toList()
      ..sort((a, b) => b.ordersProfit.compareTo(a.ordersProfit));

    final routes = routeRows
        .map((r) => PerformanceRow.fromJson(r, idField: 'route_id', name: names[r['route_id']] ?? 'Route'))
        .toList()
      ..sort((a, b) => b.ordersProfit.compareTo(a.ordersProfit));

    return _PerformanceData(salesmen: salesmen, routes: routes);
  }

  void _reload() {
    final company = _company;
    if (company != null) setState(() { _future = _load(company.id); });
  }

  void _onCompanyChanged(Company company) {
    setState(() {
      _company = company;
      _future = _load(company.id);
    });
  }

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _reload();
  }

  /// A bar behind the name, scaled to the best performer, so the gap between
  /// first and last reads without comparing numbers.
  Widget _nameWithBar(PerformanceRow row, double best, Color color) {
    final fraction = best <= 0 ? 0.0 : (row.ordersProfit / best).clamp(0.0, 1.0).toDouble();
    return SizedBox(
      width: 168,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  row.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (row.linesMissingBasis > 0 || row.linesMissingPrice > 0) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: [
                    if (row.linesMissingBasis > 0) '${row.linesMissingBasis} line(s) missing $_basis',
                    if (row.linesMissingPrice > 0) '${row.linesMissingPrice} line(s) missing a selling price',
                  ].join('\n'),
                  child: Icon(Icons.warning_amber, size: 13, color: StatusLevel.warning.color),
                ),
              ],
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 4,
              backgroundColor: VizChrome.muted.withValues(alpha: 0.25),
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _marginCell(double? percent) {
    if (percent == null) return const Text('—', style: TextStyle(color: VizChrome.muted));
    final level = percent <= 0
        ? StatusLevel.critical
        : percent < 4
            ? StatusLevel.serious
            : percent < 6
                ? StatusLevel.warning
                : StatusLevel.good;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: level.color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        '${percent.toStringAsFixed(2)}%',
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: level.color),
      ),
    );
  }

  Widget _table({
    required List<PerformanceRow> rows,
    required Color color,
    required double minWidth,
    bool isRoute = false,
  }) {
    final best = rows.isEmpty ? 0.0 : rows.map((r) => r.ordersProfit).reduce((a, b) => a > b ? a : b);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: minWidth),
          child: DataTable(
            dataRowMinHeight: 46,
            dataRowMaxHeight: 46,
            headingRowHeight: 40,
            headingTextStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: VizChrome.secondaryInk,
            ),
            dataTextStyle: const TextStyle(fontSize: 13),
            columnSpacing: 18,
            columns: [
              const DataColumn(label: Text('#')),
              DataColumn(label: Text(isRoute ? 'Route' : 'Salesman')),
              const DataColumn(label: Text('Orders'), numeric: true),
              if (isRoute) const DataColumn(label: Text('Salesmen'), numeric: true),
              const DataColumn(label: Text('Sales'), numeric: true),
              DataColumn(label: Text('$_basis cost'), numeric: true),
              const DataColumn(label: Text('Commission'), numeric: true),
              const DataColumn(label: Text('Profit'), numeric: true),
              const DataColumn(label: Text('Margin')),
              if (isRoute) const DataColumn(label: Text('Avg order'), numeric: true),
            ],
            rows: [
              for (final (index, row) in rows.indexed)
                DataRow(
                  cells: [
                    DataCell(Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: index == 0 ? color : VizChrome.secondaryInk,
                      ),
                    )),
                    DataCell(_nameWithBar(row, best, color)),
                    DataCell(Text('${row.orders}')),
                    if (isRoute) DataCell(Text('${row.salesmen ?? 0}')),
                    DataCell(Text('৳${_money.format(row.revenue)}')),
                    DataCell(Text('৳${_money.format(row.basisValue)}')),
                    DataCell(Text(
                      row.commissionTotal > 0 ? '−৳${_money.format(row.commissionTotal)}' : '—',
                      style: TextStyle(
                        color: row.commissionTotal > 0 ? StatusLevel.serious.color : VizChrome.muted,
                      ),
                    )),
                    DataCell(Text(
                      '৳${_money.format(row.ordersProfit)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: row.ordersProfit < 0 ? StatusLevel.critical.color : null,
                      ),
                    )),
                    DataCell(_marginCell(row.profitMarginPercent)),
                    if (isRoute)
                      DataCell(Text(
                        row.avgOrderValue == null ? '—' : '৳${_money.format(row.avgOrderValue!)}',
                      )),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, String subtitle, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color)),
                Text(subtitle, style: const TextStyle(fontSize: 11, color: VizChrome.secondaryInk)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CompanySelector(selectedId: _company?.id, onChanged: _onCompanyChanged),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Previous month',
                onPressed: () => _changeMonth(-1),
              ),
              Text(DateFormat.yMMMM().format(_month),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Next month',
                onPressed: () => _changeMonth(1),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _future == null
              ? const SizedBox.shrink()
              : FutureBuilder<_PerformanceData>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return Padding(padding: const EdgeInsets.all(AppSpace.md), child: const SkeletonDashboard());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('Failed to load performance: ${snapshot.error}'));
                    }
                    final data = snapshot.data!;
                    if (data.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.inbox, size: 40, color: VizChrome.secondaryInk),
                              const SizedBox(height: 12),
                              Text(
                                'No approved deliveries in ${DateFormat.yMMMM().format(_month)}.',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'A round only counts here once you have approved it.',
                                style: TextStyle(fontSize: 12.5, color: VizChrome.secondaryInk),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final minWidth = constraints.maxWidth - 24;
                        return ListView(
                          padding: const EdgeInsets.all(12),
                          children: [
                            Card(
                              color: VizChrome.info.withValues(alpha: 0.08),
                              child: const Padding(
                                padding: EdgeInsets.all(12),
                                child: Text(
                                  'Profit here is after salesman commission, so it is what you actually '
                                  'keep. Margin is that profit as a share of sales — the number that '
                                  'separates a big seller from a profitable one.',
                                  style: TextStyle(fontSize: 12, color: VizChrome.secondaryInk),
                                ),
                              ),
                            ),
                            _sectionTitle(
                              'Salesmen',
                              'Ranked by what they brought in after their own commission.',
                              Icons.person,
                              VizChrome.accentTeal,
                            ),
                            if (data.salesmen.isEmpty)
                              const Card(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Text('No salesman activity this month.',
                                      style: TextStyle(fontSize: 12.5, color: VizChrome.secondaryInk)),
                                ),
                              )
                            else
                              _table(
                                rows: data.salesmen,
                                color: VizChrome.accentTeal,
                                minWidth: minWidth,
                              ),
                            _sectionTitle(
                              'Routes',
                              'Which areas are worth the van, and how big a drop each one takes.',
                              Icons.alt_route,
                              VizChrome.accentPlum,
                            ),
                            if (data.routes.isEmpty)
                              const Card(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Text('No route activity this month.',
                                      style: TextStyle(fontSize: 12.5, color: VizChrome.secondaryInk)),
                                ),
                              )
                            else
                              _table(
                                rows: data.routes,
                                color: VizChrome.accentPlum,
                                minWidth: minWidth,
                                isRoute: true,
                              ),
                            const SizedBox(height: 24),
                          ],
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}
