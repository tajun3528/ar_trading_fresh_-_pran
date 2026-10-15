import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auto_refresh_mixin.dart';
import '../../core/company_selector.dart';
import '../../core/providers.dart';
import '../../core/viz/bold_stat_card.dart';
import '../../core/viz/status_palette.dart';
import '../../models/company.dart';
import '../../models/profit.dart';
import '../../models/unit_type.dart';
import '../dashboard/stat_tile.dart';
import '../../core/design/design_tokens.dart';
import '../../core/motion/skeleton.dart';

final _money = NumberFormat('#,##0.00');
final _qty = NumberFormat('#,##0');

const _displayUnits = [UnitType.carton, UnitType.box, UnitType.poli, UnitType.jar, UnitType.pcs];

/// One product's sales for the month, with its per-unit rows kept intact so a
/// row can show every unit side by side without losing which unit earned what.
class _ProductRow {
  _ProductRow(this.productId, this.productName);

  final String productId;
  final String productName;
  final Map<UnitType, ProductSales> byUnit = {};

  double get revenue => byUnit.values.fold(0.0, (sum, r) => sum + r.revenue);
  double get basisValue => byUnit.values.fold(0.0, (sum, r) => sum + r.basisValue);
  double get margin => byUnit.values.fold(0.0, (sum, r) => sum + r.margin);
  int get orders => byUnit.values.fold(0, (sum, r) => sum + r.orders);
  int get linesMissingBasis => byUnit.values.fold(0, (sum, r) => sum + r.linesMissingBasis);

  /// The units this row actually has sales in, in the app's usual order.
  List<UnitType> get units => [for (final u in _displayUnits) if (byUnit.containsKey(u)) u];
}

class _SalesData {
  _SalesData({required this.rows, required this.months});

  final List<ProductSales> rows;

  /// Every month this company has delivered sales in, newest first — so the
  /// month stepper can say when there is nothing more to step back to.
  final List<DateTime> months;

  double get revenue => rows.fold(0.0, (sum, r) => sum + r.revenue);
  int get productCount => rows.map((r) => r.productId).toSet().length;
  double get aboveTotal => rows.where((r) => r.isAboveBasis).fold(0.0, (sum, r) => sum + r.margin);
  double get belowTotal => rows.where((r) => r.isBelowBasis).fold(0.0, (sum, r) => sum + r.margin);
  int get belowCount => rows.where((r) => r.isBelowBasis).length;
  int get missingBasis => rows.fold(0, (sum, r) => sum + r.linesMissingBasis);

  /// Groups the per-unit rows into one entry per product, keeping only the
  /// units that pass [where] — so the above- and below-price tables each show
  /// a product's qualifying units and nothing else.
  List<_ProductRow> grouped({bool Function(ProductSales)? where}) {
    final grouped = <String, _ProductRow>{};
    for (final row in rows) {
      if (where != null && !where(row)) continue;
      grouped.putIfAbsent(row.productId, () => _ProductRow(row.productId, row.productName)).byUnit[row.unitType] = row;
    }
    return grouped.values.toList();
  }
}

/// What sold, and where the selling price sits against what the company
/// charges — the question the month's single profit number can't answer.
class ProductSalesScreen extends ConsumerStatefulWidget {
  const ProductSalesScreen({super.key});

  @override
  ConsumerState<ProductSalesScreen> createState() => _ProductSalesScreenState();
}

class _ProductSalesScreenState extends ConsumerState<ProductSalesScreen>
    with AutoRefreshMixin<ProductSalesScreen> {
  Company? _company;
  Future<_SalesData>? _future;
  late DateTime _month;
  final _searchController = TextEditingController();
  String _search = '';

  @override
  void refreshData() => _reload();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Each vendor measures against a different price — name the real one.
  String get _basis => (_company?.costBasis ?? CompanyCostBasis.dp).label;

  Future<_SalesData> _load(String companyId) async {
    final client = ref.read(insforgeClientProvider);
    final all = await client.from('monthly_product_sales').select().eq('company_id', companyId).get();
    final parsed = all.map(ProductSales.fromJson).toList();

    final months = parsed.map((r) => DateTime(r.month.year, r.month.month)).toSet().toList()
      ..sort((a, b) => b.compareTo(a));

    final rows = parsed.where((r) => r.month.year == _month.year && r.month.month == _month.month).toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));

    return _SalesData(rows: rows, months: months);
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

  List<_ProductRow> _visible(List<_ProductRow> rows) {
    final query = _search.trim().toLowerCase();
    if (query.isEmpty) return rows;
    return rows.where((r) => r.productName.toLowerCase().contains(query)).toList();
  }

  Widget _qtyCell(_ProductRow row, UnitType unit) {
    final sold = row.byUnit[unit];
    if (sold == null) return const Text('—', style: TextStyle(color: VizChrome.muted));
    return Text(_qty.format(sold.quantity), style: const TextStyle(fontWeight: FontWeight.w700));
  }

  /// The shared shape of all three tables: product, a column per unit sold,
  /// then whatever figures that table is about.
  Widget _table({
    required List<_ProductRow> rows,
    required List<UnitType> units,
    required List<DataColumn> trailingColumns,
    required List<DataCell> Function(_ProductRow row, int index) trailingCells,
    required double minWidth,
    bool ranked = false,
  }) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: minWidth),
          child: DataTable(
            dataRowMinHeight: 40,
            dataRowMaxHeight: 40,
            headingRowHeight: 40,
            headingTextStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: VizChrome.secondaryInk,
            ),
            dataTextStyle: const TextStyle(fontSize: 13),
            columnSpacing: 18,
            columns: [
              if (ranked) const DataColumn(label: Text('#')),
              const DataColumn(label: Text('Product')),
              for (final unit in units) DataColumn(label: Text(unit.label), numeric: true),
              ...trailingColumns,
            ],
            rows: [
              for (final (index, row) in rows.indexed)
                DataRow(
                  cells: [
                    if (ranked)
                      DataCell(Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: index < 3 ? VizChrome.accentTeal : VizChrome.secondaryInk,
                        ),
                      )),
                    DataCell(Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            row.productName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (row.linesMissingBasis > 0) ...[
                          const SizedBox(width: 4),
                          Tooltip(
                            message: '${row.linesMissingBasis} line(s) have no $_basis to compare against',
                            child: Icon(Icons.warning_amber, size: 14, color: StatusLevel.warning.color),
                          ),
                        ],
                      ],
                    )),
                    for (final unit in units) DataCell(_qtyCell(row, unit)),
                    ...trailingCells(row, index),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, String subtitle, {Color? color, IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Row(
        children: [
          if (icon != null) ...[Icon(icon, size: 18, color: color), const SizedBox(width: 8)],
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

  Widget _emptyNote(String text) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.check_circle, size: 18, color: StatusLevel.good.color),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: VizChrome.secondaryInk))),
          ],
        ),
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
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search products',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: _search.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(() {
                              _searchController.clear();
                              _search = '';
                            }),
                          ),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _future == null
              ? const SizedBox.shrink()
              : FutureBuilder<_SalesData>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return Padding(padding: const EdgeInsets.all(AppSpace.md), child: const SkeletonDashboard());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('Failed to load sales: ${snapshot.error}'));
                    }
                    final data = snapshot.data!;
                    if (data.rows.isEmpty) {
                      return _NoSalesForMonth(month: _month, months: data.months, onPick: (m) {
                        setState(() => _month = m);
                        _reload();
                      });
                    }
                    return LayoutBuilder(
                      builder: (context, constraints) => _buildReport(data, constraints.maxWidth - 24),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildReport(_SalesData data, double minWidth) {
    final top = _visible(data.grouped())..sort((a, b) => b.revenue.compareTo(a.revenue));
    final above = _visible(data.grouped(where: (r) => r.isAboveBasis))
      ..sort((a, b) => b.margin.compareTo(a.margin));
    final below = _visible(data.grouped(where: (r) => r.isBelowBasis))
      ..sort((a, b) => a.margin.compareTo(b.margin));

    final topUnits = _unitsIn(top);
    final aboveUnits = _unitsIn(above);
    final belowUnits = _unitsIn(below);
    final revenue = data.revenue;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        StatGrid(tiles: [
          BoldStatCard(
            label: 'Sales value',
            value: '৳${_money.format(revenue)}',
            icon: Icons.payments,
            color: VizChrome.accentTeal,
          ),
          BoldStatCard(
            label: 'Products sold',
            value: '${data.productCount}',
            icon: Icons.inventory_2,
            color: VizChrome.info,
          ),
          BoldStatCard(
            label: 'Above $_basis',
            value: '+৳${_money.format(data.aboveTotal)}',
            icon: Icons.trending_up,
            color: StatusLevel.good.color,
          ),
          BoldStatCard(
            label: 'Below $_basis',
            value: '−৳${_money.format(data.belowTotal.abs())}',
            icon: Icons.trending_down,
            color: data.belowTotal < 0 ? StatusLevel.serious.color : StatusLevel.good.color,
          ),
        ]),
        if (data.missingBasis > 0)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Card(
              color: StatusLevel.warning.color.withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '${data.missingBasis} delivered line(s) have no $_basis recorded, so their cost is missing '
                  'from these figures. Set their $_basis to see the real margin.',
                  style: const TextStyle(fontSize: 12, color: VizChrome.secondaryInk),
                ),
              ),
            ),
          ),

        _sectionTitle(
          'Best sellers',
          'Every product delivered in ${DateFormat.yMMMM().format(_month)}, biggest earner first.',
          icon: Icons.emoji_events,
          color: VizChrome.accentTeal,
        ),
        if (top.isEmpty)
          _emptyNote('No products match "${_search.trim()}".')
        else
          _table(
            rows: top,
            units: topUnits,
            ranked: true,
            minWidth: minWidth,
            trailingColumns: const [
              DataColumn(label: Text('Orders'), numeric: true),
              DataColumn(label: Text('Sales value'), numeric: true),
              DataColumn(label: Text('Share')),
            ],
            trailingCells: (row, _) => [
              DataCell(Text(_qty.format(row.orders))),
              DataCell(Text('৳${_money.format(row.revenue)}', style: const TextStyle(fontWeight: FontWeight.w700))),
              DataCell(_ShareBar(fraction: revenue <= 0 ? 0 : row.revenue / revenue)),
            ],
          ),

        _sectionTitle(
          'Selling above $_basis',
          'These earned more than the company charged — the margin is yours to keep.',
          icon: Icons.arrow_upward,
          color: StatusLevel.good.color,
        ),
        if (above.isEmpty)
          _emptyNote('Nothing sold above $_basis this month.')
        else
          _table(
            rows: above,
            units: aboveUnits,
            minWidth: minWidth,
            trailingColumns: [
              const DataColumn(label: Text('Sold for'), numeric: true),
              DataColumn(label: Text('$_basis value'), numeric: true),
              const DataColumn(label: Text('Gain'), numeric: true),
            ],
            trailingCells: (row, _) => [
              DataCell(Text('৳${_money.format(row.revenue)}')),
              DataCell(Text('৳${_money.format(row.basisValue)}')),
              DataCell(Text(
                '+৳${_money.format(row.margin)}',
                style: TextStyle(fontWeight: FontWeight.w700, color: StatusLevel.good.color),
              )),
            ],
          ),

        _sectionTitle(
          'Selling below $_basis',
          'Sold for less than the company charged — every unit here lost money.',
          icon: Icons.arrow_downward,
          color: StatusLevel.serious.color,
        ),
        if (below.isEmpty)
          _emptyNote('Nothing sold below $_basis this month.')
        else
          _table(
            rows: below,
            units: belowUnits,
            minWidth: minWidth,
            trailingColumns: [
              const DataColumn(label: Text('Sold for'), numeric: true),
              DataColumn(label: Text('$_basis value'), numeric: true),
              const DataColumn(label: Text('Shortfall'), numeric: true),
            ],
            trailingCells: (row, _) => [
              DataCell(Text('৳${_money.format(row.revenue)}')),
              DataCell(Text('৳${_money.format(row.basisValue)}')),
              DataCell(Text(
                '−৳${_money.format(row.margin.abs())}',
                style: TextStyle(fontWeight: FontWeight.w700, color: StatusLevel.serious.color),
              )),
            ],
          ),
        if (below.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Tip: a unit lands here when its selling price is under the $_basis for that same unit — '
              'raise the price on the salesman\'s monthly price list, or check the $_basis is right.',
              style: const TextStyle(fontSize: 11, color: VizChrome.secondaryInk),
            ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  List<UnitType> _unitsIn(List<_ProductRow> rows) {
    final present = <UnitType>{for (final row in rows) ...row.units};
    return [for (final unit in _displayUnits) if (present.contains(unit)) unit];
  }
}

/// A thin proportion bar — reads faster than a percentage when scanning a
/// ranked list for where the money actually comes from.
class _ShareBar extends StatelessWidget {
  const _ShareBar({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 110,
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: fraction.clamp(0, 1),
                minHeight: 6,
                backgroundColor: VizChrome.muted.withValues(alpha: 0.25),
                color: VizChrome.accentTeal,
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 34,
            child: Text(
              '${(fraction * 100).toStringAsFixed(1)}%',
              style: const TextStyle(fontSize: 11, color: VizChrome.secondaryInk),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

/// An empty month is usually the wrong month rather than no sales, so offer
/// the months that do have deliveries instead of a bare "nothing here".
class _NoSalesForMonth extends StatelessWidget {
  const _NoSalesForMonth({required this.month, required this.months, required this.onPick});

  final DateTime month;
  final List<DateTime> months;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox, size: 40, color: VizChrome.secondaryInk),
            const SizedBox(height: 12),
            Text(
              'No delivered sales in ${DateFormat.yMMMM().format(month)}.',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (months.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Months with sales:', style: TextStyle(fontSize: 12, color: VizChrome.secondaryInk)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final m in months)
                    OutlinedButton(
                      onPressed: () => onPick(m),
                      child: Text(DateFormat.yMMM().format(m)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
