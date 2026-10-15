import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auto_refresh_mixin.dart';
import '../../core/providers.dart';
import '../../core/viz/bold_stat_card.dart';
import '../../core/viz/data_table_card.dart';
import '../../core/viz/status_breakdown_bar.dart';
import '../../core/viz/status_donut_chart.dart';
import '../../core/design/design_tokens.dart';
import '../../core/viz/status_palette.dart';
import '../../core/viz/trend_charts.dart';
import '../../models/company.dart';
import '../../models/daily_summary.dart';
import '../../models/product.dart';
import '../../models/unit_type.dart';
import '../summaries/summary_status_chip.dart';
import 'stat_tile.dart';
import '../../core/motion/skeleton.dart';

class OwnerDashboardScreen extends ConsumerStatefulWidget {
  const OwnerDashboardScreen({super.key});

  @override
  ConsumerState<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends ConsumerState<OwnerDashboardScreen>
    with AutoRefreshMixin<OwnerDashboardScreen> {
  late Future<_OwnerStats> _future;
  String? _companyId;

  @override
  void refreshData() => setState(() { _future = _load(); });

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_OwnerStats> _load() async {
    final client = ref.read(insforgeClientProvider);
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final companyId = _companyId;

    var todaysSummariesQuery = client.from('daily_summaries').select('id,status').eq('submission_date', today);
    if (companyId != null) todaysSummariesQuery = todaysSummariesQuery.eq('company_id', companyId);
    final todaysSummaries = await todaysSummariesQuery.get();

    // deliveries isn't itself company-scoped (it hangs off summary_id) — when
    // a company filter is active, narrow it down via that company's own
    // summary ids.
    final todaysDeliveriesRows =
        await client.from('deliveries').select('id,summary_id').gte('delivery_datetime', today).get();
    List<dynamic> todaysDeliveries = todaysDeliveriesRows;
    if (companyId != null) {
      final companySummaryIds =
          (await client.from('daily_summaries').select('id').eq('company_id', companyId).get())
              .map((r) => r['id'] as String)
              .toSet();
      todaysDeliveries =
          todaysDeliveriesRows.where((r) => companySummaryIds.contains(r['summary_id'] as String)).toList();
    }

    // Cash actually received: the payment each approved round handed over,
    // which is delivered goods less the salesman's commission and any damage
    // refunded to shops. Summing the order total instead counted goods that
    // came back unsold as though they had been sold.
    final approvedDeliveryRows =
        await client.from('deliveries').select('summary_id,payment_amount').eq('approval_status', 'approved').get();
    final paidSummaryIds = approvedDeliveryRows.map((d) => d['summary_id'] as String).toSet().toList();
    var companySummaryIds = <String>{};
    if (paidSummaryIds.isNotEmpty) {
      var scopeQuery = client.from('daily_summaries').select('id').inList('id', paidSummaryIds);
      if (companyId != null) scopeQuery = scopeQuery.eq('company_id', companyId);
      companySummaryIds = (await scopeQuery.get()).map((s) => s['id'] as String).toSet();
    }
    final totalSales = approvedDeliveryRows
        .where((d) => companySummaryIds.contains(d['summary_id'] as String))
        .fold<double>(0, (s, d) => s + ((d['payment_amount'] as num?)?.toDouble() ?? 0));

    final allStockRows = await client.from('product_stock_view').select().get();
    final stockRows =
        companyId == null ? allStockRows : allStockRows.where((r) => r['company_id'] == companyId).toList();
    // is_low_stock is per unit row, and loose pieces sit at zero by design
    // once they roll up into a carton — so a product only counts as low when
    // every one of its units is down, not just one of them.
    final lowStockProductIds = <String>{};
    final notLowProductIds = <String>{};
    for (final row in stockRows) {
      final productId = row['product_id'] as String;
      if (row['is_low_stock'] as bool) {
        lowStockProductIds.add(productId);
      } else {
        notLowProductIds.add(productId);
      }
    }
    lowStockProductIds.removeAll(notLowProductIds);
    final lowStockCount = lowStockProductIds.length;
    // Pieces, jars, and cartons aren't fungible, so this counts how many
    // product+unit lines have damage — not a summed quantity across units.
    final damagedLines = stockRows.where((r) => (r['damaged_qty'] as int) > 0).length;

    // Stock/product_units aren't company-scoped columns themselves — filter
    // the same way every other screen does, via this company's product ids.
    final stockedProductIds = stockRows.map((r) => r['product_id'] as String).toSet();
    final allUnitRows = await client.from('product_units').select().get();
    final unitPrices = <String, Map<UnitType, double>>{};
    for (final row in allUnitRows) {
      final productId = row['product_id'] as String;
      if (!stockedProductIds.contains(productId)) continue;
      final unit = ProductUnit.fromJson(row);
      unitPrices.putIfAbsent(productId, () => {})[unit.unitType] = unit.price;
    }
    var totalStockValue = 0.0;
    var totalDamageValue = 0.0;
    for (final row in stockRows) {
      final productId = row['product_id'] as String;
      final unit = UnitType.parse(row['unit_type'] as String);
      final price = unitPrices[productId]?[unit];
      if (price == null) continue;
      totalStockValue += (row['available_qty'] as int) * price;
      totalDamageValue += (row['damaged_qty'] as int) * price;
    }

    // One row per product (Carton/Jar/Pcs as columns), matching the Stock
    // page — grouping by unit here made the same product show up as 2-3
    // separate rows whenever more than one of its units was low.
    // Only genuinely low products, and showing every unit of them — listing
    // just the zeroed unit hid the cartons still on the shelf.
    final restockByProduct = <String, _RestockRow>{};
    for (final row in stockRows) {
      final productId = row['product_id'] as String;
      if (!lowStockProductIds.contains(productId)) continue;
      final entry = restockByProduct.putIfAbsent(
        productId,
        () => _RestockRow(name: row['name'] as String, threshold: row['low_stock_threshold'] as int),
      );
      entry.quantities[UnitType.parse(row['unit_type'] as String)] = row['available_qty'] as int;
    }
    final restockLines = restockByProduct.values.toList()..sort((a, b) => a.name.compareTo(b.name));

    var recentQuery = client.from('daily_summaries').select();
    if (companyId != null) recentQuery = recentQuery.eq('company_id', companyId);
    final recentRows = await recentQuery.order('submission_date', ascending: false).limit(6).get();
    final recentSummaries = recentRows.map(DailySummary.fromJson).toList();
    final profileRows = await client.from('profiles').select('user_id,name').get();
    final salesmanNames = {for (final p in profileRows) p['user_id'] as String: p['name'] as String};

    final statusCounts = <SummaryStatus, int>{};
    for (final row in todaysSummaries) {
      final status = SummaryStatus.parse(row['status'] as String);
      statusCounts[status] = (statusCounts[status] ?? 0) + 1;
    }

    // 14-day trend: bucketed by submission_date so both charts share the
    // same x-axis. The cash line uses the same basis as the tile above —
    // what an approved round actually handed over — so the chart and the
    // headline figure can't disagree.
    final windowStart = DateTime.now().subtract(const Duration(days: 13));
    final windowStartStr = windowStart.toIso8601String().substring(0, 10);
    var trendQuery =
        client.from('daily_summaries').select('id,submission_date').gte('submission_date', windowStartStr);
    if (companyId != null) trendQuery = trendQuery.eq('company_id', companyId);
    final trendRows = await trendQuery.get();

    final paymentBySummary = <String, double>{
      for (final d in approvedDeliveryRows)
        d['summary_id'] as String: (d['payment_amount'] as num?)?.toDouble() ?? 0,
    };

    final salesByDay = <String, double>{};
    final countByDay = <String, int>{};
    for (final row in trendRows) {
      final day = row['submission_date'] as String;
      countByDay[day] = (countByDay[day] ?? 0) + 1;
      final payment = paymentBySummary[row['id'] as String];
      if (payment != null) {
        salesByDay[day] = (salesByDay[day] ?? 0) + payment;
      }
    }

    final salesTrend = <TrendPoint>[];
    final summariesTrend = <TrendPoint>[];
    for (var i = 0; i < 14; i++) {
      final day = windowStart.add(Duration(days: i));
      final key = day.toIso8601String().substring(0, 10);
      final label = DateFormat('M/d').format(day);
      salesTrend.add(TrendPoint(label, salesByDay[key] ?? 0));
      summariesTrend.add(TrendPoint(label, (countByDay[key] ?? 0).toDouble()));
    }

    // Week-over-week change, from the same 14-day window: last 7 days vs.
    // the 7 before it — shown as a small delta badge next to the sales
    // chart's headline number.
    final priorWeekSales = salesTrend.take(7).fold<double>(0, (s, p) => s + p.value);
    final recentWeekSales = salesTrend.skip(7).fold<double>(0, (s, p) => s + p.value);
    final salesWeekOverWeekDelta =
        priorWeekSales > 0 ? ((recentWeekSales - priorWeekSales) / priorWeekSales) * 100 : null;

    // Profit per month, summed across companies when no company is selected.
    var profitQuery = client.from('monthly_profit_history').select();
    if (companyId != null) profitQuery = profitQuery.eq('company_id', companyId);
    final profitRows = await profitQuery.order('month', ascending: false).get();
    final byMonth = <String, _MonthProfit>{};
    for (final row in profitRows) {
      final key = row['month'] as String;
      final entry = byMonth.putIfAbsent(key, () => _MonthProfit(month: DateTime.parse(key)));
      entry.revenue += (row['revenue'] as num).toDouble();
      entry.profit1 += (row['profit1'] as num).toDouble();
      entry.profit2 += (row['profit2'] as num).toDouble();
      entry.commission += (row['commission_total'] as num).toDouble();
      entry.bonus += (row['bonus_amount'] as num).toDouble();
      entry.netProfit += (row['net_profit'] as num).toDouble();
      entry.orders += (row['orders'] as num).toInt();
    }
    final monthlyProfit = byMonth.values.toList()..sort((a, b) => b.month.compareTo(a.month));

    return _OwnerStats(
      monthlyProfit: monthlyProfit,
      todaysSummaries: todaysSummaries.length,
      todaysDeliveries: todaysDeliveries.length,
      totalSales: totalSales,
      lowStockCount: lowStockCount,
      damagedLines: damagedLines,
      statusCounts: statusCounts,
      restockLines: restockLines,
      recentSummaries: recentSummaries,
      salesmanNames: salesmanNames,
      salesTrend: salesTrend,
      summariesTrend: summariesTrend,
      salesWeekOverWeekDelta: salesWeekOverWeekDelta,
      totalStockValue: totalStockValue,
      totalDamageValue: totalDamageValue,
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(authControllerProvider).valueOrNull?.name ?? 'Owner';
    return RefreshIndicator(
      onRefresh: () async => setState(() { _future = _load(); }),
      child: FutureBuilder<_OwnerStats>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Padding(padding: const EdgeInsets.all(AppSpace.md), child: const SkeletonDashboard());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Failed to load dashboard: ${snapshot.error}'));
          }
          final s = snapshot.data!;
          final companies = ref.watch(companiesProvider).valueOrNull ?? const <Company>[];
          return LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 900;
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _GreetingHeader(
                    name: name,
                    companies: companies,
                    selectedCompanyId: _companyId,
                    onCompanyChanged: (id) => setState(() {
                      _companyId = id;
                      _future = _load();
                    }),
                  ),
                  const SizedBox(height: 20),
                  // Each figure opens the page it was calculated from, so a
                  // number that looks wrong can be traced to its rows.
                  StatGrid(tiles: [
                    BoldStatCard(
                      label: "Today's summaries",
                      value: '${s.todaysSummaries}',
                      countTo: s.todaysSummaries.toDouble(),
                      format: (v) => v.round().toString(),
                      delay: AppMotion.stagger * 0,
                      icon: Icons.receipt_long,
                      color: VizChrome.accentIndigo,
                      tooltip: 'Open Daily Summaries',
                      onTap: () => context.go('/owner/summaries'),
                    ),
                    BoldStatCard(
                      label: "Today's deliveries",
                      value: '${s.todaysDeliveries}',
                      countTo: s.todaysDeliveries.toDouble(),
                      format: (v) => v.round().toString(),
                      delay: AppMotion.stagger * 1,
                      icon: Icons.local_shipping,
                      color: VizChrome.accentTeal,
                      tooltip: 'Open Deliveries',
                      onTap: () => context.go('/owner/deliveries'),
                    ),
                    BoldStatCard(
                      label: 'Cash received',
                      value: '৳${s.totalSales.toStringAsFixed(0)}',
                      countTo: s.totalSales,
                      format: (v) => '৳${v.toStringAsFixed(0)}',
                      delay: AppMotion.stagger * 2,
                      icon: Icons.trending_up,
                      color: VizChrome.accentPlum,
                      tooltip: 'Open Deliveries — each round shows the cash handed over',
                      onTap: () => context.go('/owner/deliveries'),
                    ),
                    BoldStatCard(
                      label: 'Total stock value',
                      value: '৳${s.totalStockValue.toStringAsFixed(0)}',
                      countTo: s.totalStockValue,
                      format: (v) => '৳${v.toStringAsFixed(0)}',
                      delay: AppMotion.stagger * 3,
                      icon: Icons.inventory_2,
                      color: VizChrome.accentSlate,
                      tooltip: 'Open Stock',
                      onTap: () => context.go('/owner/stock'),
                    ),
                    BoldStatCard(
                      label: 'Low-stock products',
                      value: '${s.lowStockCount}',
                      countTo: s.lowStockCount.toDouble(),
                      format: (v) => v.round().toString(),
                      delay: AppMotion.stagger * 4,
                      icon: Icons.warning_amber,
                      color: s.lowStockCount > 0 ? StatusLevel.warning.color : StatusLevel.good.color,
                      tooltip: 'Open Stock',
                      onTap: () => context.go('/owner/stock'),
                    ),
                    BoldStatCard(
                      label: 'Products with damage',
                      value: '${s.damagedLines}',
                      countTo: s.damagedLines.toDouble(),
                      format: (v) => v.round().toString(),
                      delay: AppMotion.stagger * 5,
                      icon: Icons.broken_image,
                      color: s.damagedLines > 0 ? StatusLevel.serious.color : StatusLevel.good.color,
                      tooltip: 'Open Returns & Damage',
                      onTap: () => context.go('/owner/returns'),
                    ),
                    BoldStatCard(
                      label: 'Total damage value',
                      value: '৳${s.totalDamageValue.toStringAsFixed(0)}',
                      countTo: s.totalDamageValue,
                      format: (v) => '৳${v.toStringAsFixed(0)}',
                      delay: AppMotion.stagger * 6,
                      icon: Icons.report_problem,
                      color: s.totalDamageValue > 0 ? StatusLevel.serious.color : StatusLevel.good.color,
                      tooltip: 'Open Returns & Damage',
                      onTap: () => context.go('/owner/returns'),
                    ),
                  ]),
                  const SizedBox(height: 20),
                  _MonthlyProfitCard(months: s.monthlyProfit),
                  const SizedBox(height: 20),
                  _CriticalAlertsCard(restockLines: s.restockLines, damagedLines: s.damagedLines),
                  const SizedBox(height: 20),
                  _ChartRow(isWide: isWide, s: s),
                  const SizedBox(height: 20),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Summaries submitted — last 14 days', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 12),
                          TrendBarChart(points: s.summariesTrend, color: VizChrome.sequentialOrange),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _TablesRow(isWide: isWide, s: s),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _GreetingHeader extends StatelessWidget {
  const _GreetingHeader({
    required this.name,
    required this.companies,
    required this.selectedCompanyId,
    required this.onCompanyChanged,
  });

  final String name;
  final List<Company> companies;
  final String? selectedCompanyId;
  final ValueChanged<String?> onCompanyChanged;

  @override
  Widget build(BuildContext context) {
    final greeting = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'Hello, $name ',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const TextSpan(text: '👋', style: TextStyle(fontSize: 22)),
        ],
      ),
    );
    final date = Text(
      DateFormat.yMMMEd().format(DateTime.now()),
      style: const TextStyle(color: VizChrome.secondaryInk),
      overflow: TextOverflow.ellipsis,
    );
    Widget companyPicker({required bool expand}) => DropdownButton<String?>(
          value: selectedCompanyId,
          isExpanded: expand,
          hint: const Text('All companies', overflow: TextOverflow.ellipsis),
          items: [
            const DropdownMenuItem(value: null, child: Text('All companies')),
            for (final c in companies)
              DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: onCompanyChanged,
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Greeting, date and company picker only coexist on one line on a
        // tablet or wider — below that the date alone eats the whole row.
        if (constraints.maxWidth < 640) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              greeting,
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: date),
                  const SizedBox(width: 12),
                  Flexible(child: companyPicker(expand: true)),
                ],
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: greeting),
            Flexible(child: date),
            const SizedBox(width: 16),
            companyPicker(expand: false),
          ],
        );
      },
    );
  }
}

/// Colored, severity-ordered call-outs for what needs the Owner's attention
/// right now — the same low-stock/damage facts already on the KPI cards
/// above, surfaced as actionable rows instead of just a count.
/// Profit month by month: the margin over cost, the company's commission on
/// it, less what the salesmen took, plus any target bonus earned.
class _MonthlyProfitCard extends StatelessWidget {
  const _MonthlyProfitCard({required this.months});

  final List<_MonthProfit> months;

  @override
  Widget build(BuildContext context) {
    if (months.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text('No profit yet — it appears once a delivery is approved.'),
          ),
        ),
      );
    }

    final money = NumberFormat('#,##0.00');
    final total = months.fold<double>(0, (sum, m) => sum + m.netProfit);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('Profit by month',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                ),
                Text(
                  '৳${money.format(total)} all time',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: total >= 0 ? StatusLevel.good.color : StatusLevel.critical.color,
                  ),
                ),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
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
                  columnSpacing: 18,
                  columns: const [
                    DataColumn(label: Text('Month')),
                    DataColumn(label: Text('Orders')),
                    DataColumn(label: Text('Sales')),
                    DataColumn(label: Text('Margin')),
                    DataColumn(label: Text('Company 6%')),
                    DataColumn(label: Text('Commission')),
                    DataColumn(label: Text('Bonus')),
                    DataColumn(label: Text('Net profit')),
                  ],
                  rows: [
                    for (final m in months)
                      DataRow(
                        cells: [
                          DataCell(Text(DateFormat.yMMM().format(m.month),
                              style: const TextStyle(fontWeight: FontWeight.w600))),
                          DataCell(Text('${m.orders}')),
                          DataCell(Text('৳${money.format(m.revenue)}')),
                          DataCell(Text('৳${money.format(m.profit1)}')),
                          DataCell(Text('৳${money.format(m.profit2)}')),
                          DataCell(Text(
                            m.commission > 0 ? '−৳${money.format(m.commission)}' : '—',
                            style: TextStyle(color: m.commission > 0 ? StatusLevel.serious.color : null),
                          )),
                          DataCell(Text(
                            m.bonus > 0 ? '৳${money.format(m.bonus)}' : '—',
                            style: TextStyle(color: m.bonus > 0 ? StatusLevel.good.color : null),
                          )),
                          DataCell(Text(
                            '৳${money.format(m.netProfit)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: m.netProfit >= 0 ? StatusLevel.good.color : StatusLevel.critical.color,
                            ),
                          )),
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
  }
}

class _CriticalAlertsCard extends StatelessWidget {
  const _CriticalAlertsCard({required this.restockLines, required this.damagedLines});

  final List<_RestockRow> restockLines;
  final int damagedLines;

  @override
  Widget build(BuildContext context) {
    final alerts = <(StatusLevel, String, String)>[];
    for (final row in restockLines) {
      final minQty = row.quantities.values.isEmpty
          ? 0
          : row.quantities.values.reduce((a, b) => a < b ? a : b);
      final severity = minQty <= 0 ? StatusLevel.critical : StatusLevel.warning;
      final detail = minQty <= 0 ? 'Out of stock' : 'Low stock — $minQty left (threshold ${row.threshold})';
      alerts.add((severity, row.name, detail));
    }
    if (damagedLines > 0) {
      alerts.add((
        StatusLevel.serious,
        'Damaged stock',
        '$damagedLines product line${damagedLines == 1 ? '' : 's'} reported damage',
      ));
    }
    // Worst first: critical, then serious, then warning.
    alerts.sort((a, b) => a.$1.index.compareTo(b.$1.index));
    final shown = alerts.take(5).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.notifications_active_outlined, size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('Critical alerts', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 12),
            if (shown.isEmpty)
              _alertRow(StatusLevel.good, 'All clear', 'No low stock or damage reported.')
            else ...[
              for (final a in shown) _alertRow(a.$1, a.$2, a.$3),
              if (alerts.length > shown.length)
                Text('+${alerts.length - shown.length} more', style: const TextStyle(fontSize: 12, color: VizChrome.secondaryInk)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _alertRow(StatusLevel level, String title, String subtitle) {
    final color = level.color;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Row(
        children: [
          Icon(level.icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: VizChrome.secondaryInk)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sales trend (left, wider) beside today's status breakdown (right) — side
/// by side once there's room, stacked on a narrow viewport.
class _ChartRow extends StatelessWidget {
  const _ChartRow({required this.isWide, required this.s});

  final bool isWide;
  final _OwnerStats s;

  @override
  Widget build(BuildContext context) {
    final lineCard = Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cash received — last 14 days', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('৳${s.totalSales.toStringAsFixed(0)}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                if (s.salesWeekOverWeekDelta != null) ...[
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _DeltaBadge(delta: s.salesWeekOverWeekDelta!),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            TrendLineChart(
              points: s.salesTrend,
              color: VizChrome.sequentialBlue,
              valueFormatter: (v) => '৳${v.toStringAsFixed(0)}',
            ),
          ],
        ),
      ),
    );

    final donutCard = Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Today's summaries by status", style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            StatusDonutChart(
              centerLabel: 'Summaries',
              counts: [
                StatusCount(label: 'Submitted', count: s.statusCounts[SummaryStatus.booked] ?? 0, color: VizChrome.info),
                StatusCount(label: 'Delivered', count: s.statusCounts[SummaryStatus.delivered] ?? 0, color: StatusLevel.good.color),
                StatusCount(
                  label: 'Partial',
                  count: s.statusCounts[SummaryStatus.partiallyDelivered] ?? 0,
                  color: StatusLevel.warning.color,
                ),
                StatusCount(label: 'Cancelled', count: s.statusCounts[SummaryStatus.cancelled] ?? 0, color: StatusLevel.critical.color),
              ],
            ),
          ],
        ),
      ),
    );

    if (!isWide) {
      return Column(children: [lineCard, const SizedBox(height: 20), donutCard]);
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 3, child: lineCard),
          const SizedBox(width: 20),
          Expanded(flex: 2, child: donutCard),
        ],
      ),
    );
  }
}

class _DeltaBadge extends StatelessWidget {
  const _DeltaBadge({required this.delta});

  final double delta;

  @override
  Widget build(BuildContext context) {
    final isUp = delta >= 0;
    final color = isUp ? StatusLevel.good.color : StatusLevel.critical.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isUp ? Icons.arrow_upward : Icons.arrow_downward, size: 12, color: color),
          const SizedBox(width: 2),
          Text('${delta.abs().toStringAsFixed(1)}%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

/// Recent daily summaries (left, wider) beside products needing restock
/// (right) — side by side once there's room, stacked on a narrow viewport.
class _TablesRow extends StatelessWidget {
  const _TablesRow({required this.isWide, required this.s});

  final bool isWide;
  final _OwnerStats s;

  @override
  Widget build(BuildContext context) {
    final summariesTable = DataTableCard(
      title: 'Recent daily summaries',
      emptyLabel: 'No summaries submitted yet.',
      columns: const ['Submitted', 'Salesman', 'Delivery', 'Total', 'Status'],
      rows: [
        for (final summary in s.recentSummaries)
          [
            Text(DateFormat.yMMMd().format(summary.submissionDate)),
            Text(s.salesmanNames[summary.salesmanId] ?? 'Salesman'),
            Text(DateFormat.yMMMd().format(summary.deliveryDate)),
            Text('৳${summary.totalAmount.toStringAsFixed(0)}'),
            SummaryStatusChip(status: summary.status),
          ],
      ],
    );

    final restockTable = DataTableCard(
      title: 'Products needing restock',
      emptyLabel: 'Nothing is low or out of stock.',
      columns: const ['Product', 'Carton', 'Jar', 'Pcs', 'Threshold'],
      rows: [
        for (final row in s.restockLines)
          [
            Text(row.name),
            for (final unit in [UnitType.carton, UnitType.jar, UnitType.pcs]) _RestockQtyCell(qty: row.quantities[unit]),
            Text('${row.threshold}'),
          ],
      ],
    );

    if (!isWide) {
      return Column(children: [summariesTable, const SizedBox(height: 20), restockTable]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: summariesTable),
        const SizedBox(width: 20),
        Expanded(flex: 2, child: restockTable),
      ],
    );
  }
}

/// One month's profit, summed across whichever companies are in view.
class _MonthProfit {
  _MonthProfit({required this.month});

  final DateTime month;
  double revenue = 0;
  double profit1 = 0;
  double profit2 = 0;
  double commission = 0;
  double bonus = 0;
  double netProfit = 0;
  int orders = 0;
}

class _OwnerStats {
  _OwnerStats({
    required this.monthlyProfit,
    required this.todaysSummaries,
    required this.todaysDeliveries,
    required this.totalSales,
    required this.lowStockCount,
    required this.damagedLines,
    required this.statusCounts,
    required this.restockLines,
    required this.recentSummaries,
    required this.salesmanNames,
    required this.salesTrend,
    required this.summariesTrend,
    required this.salesWeekOverWeekDelta,
    required this.totalStockValue,
    required this.totalDamageValue,
  });

  /// Newest month first.
  final List<_MonthProfit> monthlyProfit;
  final int todaysSummaries;
  final int todaysDeliveries;
  final double totalSales;
  final int lowStockCount;
  final List<TrendPoint> salesTrend;
  final List<TrendPoint> summariesTrend;
  final double? salesWeekOverWeekDelta;
  final int damagedLines;
  final Map<SummaryStatus, int> statusCounts;
  final List<_RestockRow> restockLines;
  final List<DailySummary> recentSummaries;
  final Map<String, String> salesmanNames;
  final double totalStockValue;
  final double totalDamageValue;
}

/// One product, Carton/Jar/Pcs quantities as columns — same shape as the
/// Stock page, so a product low on more than one unit is still one row.
class _RestockRow {
  _RestockRow({required this.name, required this.threshold});

  final String name;
  final int threshold;
  final Map<UnitType, int> quantities = {};
}

class _RestockQtyCell extends StatelessWidget {
  const _RestockQtyCell({required this.qty});

  final int? qty;

  @override
  Widget build(BuildContext context) {
    if (qty == null) return const Text('—');
    return Text(
      '$qty',
      style: TextStyle(
        fontWeight: FontWeight.w700,
        color: qty! <= 0 ? StatusLevel.critical.color : StatusLevel.warning.color,
      ),
    );
  }
}
