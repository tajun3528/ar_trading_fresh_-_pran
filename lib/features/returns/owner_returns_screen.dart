import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auto_refresh_mixin.dart';
import '../../core/company_selector.dart';
import '../../core/providers.dart';
import '../../core/viz/bold_stat_card.dart';
import '../../core/viz/status_palette.dart';
import '../../models/company.dart';
import '../../models/unit_type.dart';
import '../dashboard/stat_tile.dart';
import '../../core/design/design_tokens.dart';
import '../../core/motion/skeleton.dart';

final _money = NumberFormat('#,##0.00');

class _DamageRecord {
  _DamageRecord({
    required this.productName,
    required this.unitType,
    required this.quantity,
    required this.lineTotal,
    required this.deliveryDate,
    required this.salesman,
    required this.route,
    required this.approved,
  });

  final String productName;
  final UnitType unitType;
  final int quantity;
  final double lineTotal;
  final DateTime deliveryDate;
  final String salesman;
  final String route;

  /// Damage on a round you haven't approved yet isn't final money.
  final bool approved;
}

/// What has come back damaged or date-expired from shops, collected by the
/// deliveryman on his rounds. Each entry is a refund the shop was credited,
/// which is why it comes off the cash handed over.
class OwnerReturnsScreen extends ConsumerStatefulWidget {
  const OwnerReturnsScreen({super.key});

  @override
  ConsumerState<OwnerReturnsScreen> createState() => _OwnerReturnsScreenState();
}

class _OwnerReturnsScreenState extends ConsumerState<OwnerReturnsScreen>
    with AutoRefreshMixin<OwnerReturnsScreen> {
  Company? _company;
  Future<List<_DamageRecord>>? _future;
  final _searchController = TextEditingController();
  String _search = '';

  @override
  void refreshData() => _reload();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<_DamageRecord>> _load(String companyId) async {
    final client = ref.read(insforgeClientProvider);

    final damageRows =
        await client.from('delivery_damages').select().order('created_at', ascending: false).limit(500).get();
    if (damageRows.isEmpty) return [];

    final deliveryIds = damageRows.map((r) => r['delivery_id'] as String).toSet().toList();
    final deliveryRows =
        await client.from('deliveries').select('id,summary_id,approval_status').inList('id', deliveryIds).get();
    final deliveryById = {for (final d in deliveryRows) d['id'] as String: d};

    final summaryIds = deliveryRows.map((d) => d['summary_id'] as String).toSet().toList();
    final summaryRows = summaryIds.isEmpty
        ? <Map<String, dynamic>>[]
        : await client
            .from('daily_summaries')
            .select('id,salesman_id,route_id,delivery_date,company_id')
            .inList('id', summaryIds)
            .get();
    final summaryById = {for (final s in summaryRows) s['id'] as String: s};

    final productRows = await client.from('products').select('id,name,company_id').get();
    final productNames = {for (final p in productRows) p['id'] as String: p['name'] as String};

    final profileRows = await client.from('profiles').select('user_id,name').get();
    final names = {for (final p in profileRows) p['user_id'] as String: p['name'] as String};
    final routeRows = await client.from('routes').select('id,name').get();
    final routeNames = {for (final r in routeRows) r['id'] as String: r['name'] as String};

    final records = <_DamageRecord>[];
    for (final row in damageRows) {
      final delivery = deliveryById[row['delivery_id'] as String];
      if (delivery == null) continue;
      final summary = summaryById[delivery['summary_id'] as String];
      if (summary == null || summary['company_id'] != companyId) continue;

      records.add(_DamageRecord(
        productName: productNames[row['product_id'] as String] ?? 'Product',
        unitType: UnitType.parse(row['unit_type'] as String),
        quantity: row['quantity'] as int,
        lineTotal: (row['line_total'] as num).toDouble(),
        deliveryDate: DateTime.parse(summary['delivery_date'] as String),
        salesman: names[summary['salesman_id'] as String] ?? 'Salesman',
        route: routeNames[summary['route_id'] as String? ?? ''] ?? '—',
        approved: delivery['approval_status'] == 'approved',
      ));
    }
    return records;
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

  Widget _buildTable(BuildContext context, List<_DamageRecord> records, double minWidth) {
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
            columns: const [
              DataColumn(label: Text('Delivery day')),
              DataColumn(label: Text('Product')),
              DataColumn(label: Text('Unit')),
              DataColumn(label: Text('Quantity')),
              DataColumn(label: Text('Refunded')),
              DataColumn(label: Text('Salesman')),
              DataColumn(label: Text('Route')),
              DataColumn(label: Text('Status')),
            ],
            rows: [
              for (final r in records)
                DataRow(
                  cells: [
                    DataCell(Text(DateFormat.yMMMd().format(r.deliveryDate))),
                    DataCell(Text(r.productName, style: const TextStyle(fontWeight: FontWeight.w600))),
                    DataCell(Text(r.unitType.label)),
                    DataCell(Text(
                      '${r.quantity}',
                      style: TextStyle(fontWeight: FontWeight.w700, color: StatusLevel.serious.color),
                    )),
                    DataCell(Text(
                      '−৳${_money.format(r.lineTotal)}',
                      style: TextStyle(fontWeight: FontWeight.w700, color: StatusLevel.serious.color),
                    )),
                    DataCell(Text(r.salesman)),
                    DataCell(Text(r.route)),
                    DataCell(Text(
                      r.approved ? 'Approved' : 'Awaiting approval',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: r.approved ? StatusLevel.good.color : StatusLevel.warning.color,
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
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search by product, salesman or route',
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
        const Divider(height: 1),
        Expanded(
          child: _future == null
              ? const SizedBox.shrink()
              : RefreshIndicator(
                  onRefresh: () async => _reload(),
                  child: FutureBuilder<List<_DamageRecord>>(
                    future: _future,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return Padding(padding: const EdgeInsets.all(AppSpace.md), child: const SkeletonDashboard());
                      }
                      if (snapshot.hasError) {
                        return Center(child: Text('Failed to load damage: ${snapshot.error}'));
                      }
                      final all = snapshot.data!;
                      if (all.isEmpty) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No damaged or expired stock collected yet.\n\n'
                              'The deliveryman records these on the Damage tab of a round.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }

                      final query = _search.trim().toLowerCase();
                      final records = query.isEmpty
                          ? all
                          : all
                              .where((r) =>
                                  r.productName.toLowerCase().contains(query) ||
                                  r.salesman.toLowerCase().contains(query) ||
                                  r.route.toLowerCase().contains(query))
                              .toList();
                      if (records.isEmpty) {
                        return Center(child: Text('Nothing matches "${_search.trim()}".'));
                      }

                      final totalValue = records.fold<double>(0, (s, r) => s + r.lineTotal);
                      final totalUnits = records.fold<int>(0, (s, r) => s + r.quantity);
                      final awaiting = records.where((r) => !r.approved).length;

                      return LayoutBuilder(
                        builder: (context, constraints) => ListView(
                          padding: const EdgeInsets.all(12),
                          children: [
                            StatGrid(tiles: [
                              BoldStatCard(
                                label: 'Value refunded',
                                value: '৳${_money.format(totalValue)}',
                                icon: Icons.currency_exchange,
                                color: StatusLevel.serious.color,
                              ),
                              BoldStatCard(
                                label: 'Units collected',
                                value: '$totalUnits',
                                icon: Icons.report_problem,
                                color: VizChrome.accentPlum,
                              ),
                              BoldStatCard(
                                label: 'Entries',
                                value: '${records.length}',
                                icon: Icons.receipt_long,
                                color: VizChrome.accentSlate,
                              ),
                              BoldStatCard(
                                label: 'Awaiting approval',
                                value: '$awaiting',
                                icon: Icons.schedule,
                                color: awaiting > 0 ? StatusLevel.warning.color : StatusLevel.good.color,
                              ),
                            ]),
                            const SizedBox(height: 16),
                            _buildTable(context, records, constraints.maxWidth - 24),
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
