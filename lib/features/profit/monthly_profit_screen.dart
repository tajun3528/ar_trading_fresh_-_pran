import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auto_refresh_mixin.dart';
import '../../core/company_selector.dart';
import '../../core/insforge/insforge_exception.dart';
import '../../core/providers.dart';
import '../../core/viz/bold_stat_card.dart';
import '../../core/viz/status_palette.dart';
import '../../models/company.dart';
import '../../models/profit.dart';
import '../dashboard/stat_tile.dart';
import '../../core/design/design_tokens.dart';
import '../../core/motion/skeleton.dart';

final _money = NumberFormat('#,##0.00');

class _ProfitData {
  _ProfitData({required this.month, required this.orders, required this.salesmanNames});

  final MonthlyProfit? month;
  final List<SummaryProfit> orders;
  final Map<String, String> salesmanNames;
}

/// The Owner's month-end picture: what every delivered order earned, and the
/// month's net profit once the vendor's target bonus is added.
class MonthlyProfitScreen extends ConsumerStatefulWidget {
  const MonthlyProfitScreen({super.key});

  @override
  ConsumerState<MonthlyProfitScreen> createState() => _MonthlyProfitScreenState();
}

class _MonthlyProfitScreenState extends ConsumerState<MonthlyProfitScreen>
    with AutoRefreshMixin<MonthlyProfitScreen> {
  Company? _company;
  Future<_ProfitData>? _future;
  late DateTime _month;

  /// Each vendor measures profit against a different price — Fresh against the
  /// ETP they publish monthly, Pran against After Trade TP — so the figures
  /// below name whichever one this company actually settles on.
  String get _basis => (_company?.costBasis ?? CompanyCostBasis.dp).label;

  @override
  void refreshData() => _reload();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  String get _monthParam => DateFormat('yyyy-MM-01').format(_month);

  Future<_ProfitData> _load(String companyId) async {
    final client = ref.read(insforgeClientProvider);

    final monthRows = await client.rpc('monthly_profit', {
      'p_month': _monthParam,
      'p_company_id': companyId,
    });
    final months = (monthRows as List).cast<Map<String, dynamic>>();

    final orderRows = await client
        .from('summary_profit')
        .select()
        .eq('company_id', companyId)
        .eq('month', _monthParam)
        .order('delivery_date', ascending: false)
        .get();

    final profileRows = await client.from('profiles').select('user_id,name').get();

    return _ProfitData(
      month: months.isEmpty ? null : MonthlyProfit.fromJson(months.first),
      orders: orderRows.map(SummaryProfit.fromJson).toList(),
      salesmanNames: {for (final p in profileRows) p['user_id'] as String: p['name'] as String},
    );
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

  Future<void> _editTarget(MonthlyProfit? current) async {
    final company = _company;
    if (company == null) return;
    final targetController = TextEditingController(
      text: current?.targetAmount == null ? '' : current!.targetAmount!.toStringAsFixed(2),
    );
    final bonusController = TextEditingController(
      text: (current?.bonusPercent ?? 0) == 0 ? '' : current!.bonusPercent.toStringAsFixed(2),
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Target for ${DateFormat.yMMMM().format(_month)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: targetController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Monthly target',
                prefixText: '৳ ',
                helperText: "Measured against the month's total $_basis value of sales.",
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: bonusController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Bonus %',
                suffixText: '%',
                helperText: 'Extra % the company pays on $_basis value once the target is met.',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved != true) return;

    final target = double.tryParse(targetController.text.trim());
    final bonus = double.tryParse(bonusController.text.trim()) ?? 0;
    if (target == null || target < 0 || bonus < 0) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Enter a valid target amount and bonus %')));
      }
      return;
    }

    final client = ref.read(insforgeClientProvider);
    try {
      final existing = await client
          .from('monthly_targets')
          .select('id')
          .eq('company_id', company.id)
          .eq('month', _monthParam)
          .get();
      if (existing.isEmpty) {
        await client.from('monthly_targets').insert([
          {
            'company_id': company.id,
            'month': _monthParam,
            'target_amount': target,
            'bonus_percent': bonus,
          }
        ]);
      } else {
        await client
            .from('monthly_targets')
            .eq('id', existing.first['id'] as String)
            .update({'target_amount': target, 'bonus_percent': bonus});
      }
      _reload();
    } on InsforgeException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Widget _buildTargetCard(MonthlyProfit? month) {
    final target = month?.targetAmount;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Monthly target', style: Theme.of(context).textTheme.titleSmall),
                ),
                TextButton.icon(
                  onPressed: () => _editTarget(month),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: Text(target == null ? 'Set target' : 'Edit'),
                ),
              ],
            ),
            if (target == null)
              const Text(
                'No target set for this month — set one to earn the extra bonus %.',
                style: TextStyle(fontSize: 12, color: VizChrome.secondaryInk),
              )
            else ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: month!.targetProgress,
                  minHeight: 10,
                  backgroundColor: VizChrome.muted.withValues(alpha: 0.25),
                  color: month.targetMet ? StatusLevel.good.color : Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '৳${_money.format(month.dpValue)} of ৳${_money.format(target)} $_basis value'
                '${month.targetMet ? ' — target met' : ''}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: month.targetMet ? StatusLevel.good.color : VizChrome.secondaryInk,
                ),
              ),
              Text(
                month.targetMet
                    ? 'Bonus earned: ৳${_money.format(month.bonusAmount)} (${month.bonusPercent}%)'
                    : 'Bonus if met: ${month.bonusPercent}% of $_basis value',
                style: const TextStyle(fontSize: 12, color: VizChrome.secondaryInk),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBreakdown(MonthlyProfit month) {
    Widget line(String label, double value, {bool negative = false, bool bold = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400, fontSize: 13)),
            ),
            Text(
              '${negative ? '−' : ''}৳${_money.format(value.abs())}',
              style: TextStyle(
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                fontSize: bold ? 15 : 13,
                color: bold
                    ? (month.netProfit >= 0 ? StatusLevel.good.color : StatusLevel.critical.color)
                    : negative
                        ? StatusLevel.serious.color
                        : null,
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('How the month adds up', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            line('Sales at your selling prices', month.revenue),
            line('Cost of those goods ($_basis)', month.dpValue, negative: true),
            const Divider(height: 16),
            line('Margin over $_basis (profit 1)', month.profit1),
            line('Company commission on $_basis (profit 2)', month.profit2),
            line('Salesman commissions', month.commissionTotal, negative: true),
            const Divider(height: 16),
            line('Profit from orders', month.ordersProfit),
            line(
              month.targetMet ? 'Target bonus' : 'Target bonus (not yet earned)',
              month.bonusAmount,
            ),
            const Divider(height: 16),
            line('Net profit for the month', month.netProfit, bold: true),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersTable(_ProfitData data, double minWidth) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: minWidth),
          child: DataTable(
            headingTextStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: VizChrome.secondaryInk,
            ),
            dataTextStyle: const TextStyle(fontSize: 13),
            columnSpacing: 18,
            columns: [
              const DataColumn(label: Text('Delivered')),
              const DataColumn(label: Text('Salesman')),
              const DataColumn(label: Text('Sales')),
              DataColumn(label: Text('$_basis cost')),
              const DataColumn(label: Text('Profit 1')),
              const DataColumn(label: Text('Profit 2')),
              const DataColumn(label: Text('Commission')),
              const DataColumn(label: Text('Order profit')),
            ],
            rows: [
              for (final order in data.orders)
                DataRow(
                  cells: [
                    DataCell(Row(
                      children: [
                        Text(DateFormat.MMMd().format(order.deliveryDate)),
                        if (order.hasGaps) ...[
                          const SizedBox(width: 4),
                          Tooltip(
                            message: '${order.linesMissingPrice} line(s) have no selling price set for this month',
                            child: Icon(Icons.warning_amber, size: 14, color: StatusLevel.warning.color),
                          ),
                        ],
                      ],
                    )),
                    DataCell(Text(data.salesmanNames[order.salesmanId] ?? 'Salesman')),
                    DataCell(Text('৳${_money.format(order.revenue)}')),
                    DataCell(Text('৳${_money.format(order.dpValue)}')),
                    DataCell(Text('৳${_money.format(order.profit1)}')),
                    DataCell(Text('৳${_money.format(order.profit2)}')),
                    DataCell(Text(
                      order.commissionAmount > 0 ? '−৳${_money.format(order.commissionAmount)}' : '—',
                      style: TextStyle(color: order.commissionAmount > 0 ? StatusLevel.serious.color : null),
                    )),
                    DataCell(Text(
                      '৳${_money.format(order.orderProfit)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: order.orderProfit >= 0 ? StatusLevel.good.color : StatusLevel.critical.color,
                      ),
                    )),
                  ],
                ),
            ],
          ),
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
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _changeMonth(-1)),
              Text(DateFormat.yMMMM().format(_month),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _changeMonth(1)),
            ],
          ),
        ),
        Expanded(
          child: _future == null
              ? const SizedBox.shrink()
              : FutureBuilder<_ProfitData>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return Padding(padding: const EdgeInsets.all(AppSpace.md), child: const SkeletonTable());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('Failed to load profit: ${snapshot.error}'));
                    }
                    final data = snapshot.data!;
                    final month = data.month;

                    return LayoutBuilder(
                      builder: (context, constraints) => ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          if (month == null)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  children: [
                                    const Text(
                                      'No approved deliveries this month yet — profit appears once a '
                                      'delivery is approved.',
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 12),
                                    OutlinedButton(
                                      onPressed: () => _editTarget(null),
                                      child: const Text('Set this month\'s target'),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else ...[
                            StatGrid(tiles: [
                              BoldStatCard(
                                label: 'Net profit',
                                value: '৳${_money.format(month.netProfit)}',
                                icon: Icons.savings,
                                color: month.netProfit >= 0 ? StatusLevel.good.color : StatusLevel.critical.color,
                              ),
                              BoldStatCard(
                                label: 'Margin over $_basis',
                                value: '৳${_money.format(month.profit1)}',
                                icon: Icons.trending_up,
                                color: VizChrome.accentTeal,
                              ),
                              BoldStatCard(
                                label: 'Company commission',
                                value: '৳${_money.format(month.profit2)}',
                                icon: Icons.handshake,
                                color: VizChrome.accentIndigo,
                              ),
                              BoldStatCard(
                                label: 'Total sales',
                                value: '৳${_money.format(month.revenue)}',
                                icon: Icons.receipt_long,
                                color: VizChrome.accentPlum,
                              ),
                            ]),
                            const SizedBox(height: 12),
                            _buildTargetCard(month),
                            const SizedBox(height: 12),
                            _buildBreakdown(month),
                          ],
                          const SizedBox(height: 12),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                            child: Text('Delivered orders this month',
                                style: Theme.of(context).textTheme.titleMedium),
                          ),
                          if (data.orders.isEmpty)
                            const Card(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Center(child: Text('No approved deliveries in this month.')),
                              ),
                            )
                          else
                            _buildOrdersTable(data, constraints.maxWidth - 24),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
