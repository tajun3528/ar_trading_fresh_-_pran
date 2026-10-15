import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auto_refresh_mixin.dart';
import '../../core/company_selector.dart';
import '../../core/insforge/insforge_exception.dart';
import '../../core/providers.dart';
import '../../core/viz/status_palette.dart';
import '../../models/category.dart';
import '../../models/company.dart';
import '../../models/product.dart';
import '../../core/design/design_tokens.dart';
import '../../core/motion/skeleton.dart';

class _EtpData {
  _EtpData({
    required this.products,
    required this.categories,
    required this.thisMonth,
    required this.carriedForward,
  });

  final List<Product> products;
  final List<Category> categories;

  /// What's set for the chosen month specifically, by product id.
  final Map<String, ({double? carton, double? pcs})> thisMonth;

  /// What a product would cost this month with nothing set — the most recent
  /// earlier month, or the original sheet figure.
  final Map<String, ({double? carton, double? pcs})> carriedForward;
}

/// Where the Owner keeps ETP up to date. The company revises it monthly, and
/// profit is measured against it, so each month keeps its own figures rather
/// than a later revision reaching back and rewriting a closed month.
class EtpPricesScreen extends ConsumerStatefulWidget {
  const EtpPricesScreen({super.key});

  @override
  ConsumerState<EtpPricesScreen> createState() => _EtpPricesScreenState();
}

class _EtpPricesScreenState extends ConsumerState<EtpPricesScreen> with AutoRefreshMixin<EtpPricesScreen> {
  Company? _company;
  Future<_EtpData>? _future;
  final Map<String, TextEditingController> _cartonControllers = {};
  final Map<String, TextEditingController> _pcsControllers = {};
  final _searchController = TextEditingController();
  String _search = '';
  late DateTime _month;
  bool _saving = false;

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
    for (final c in _cartonControllers.values) {
      c.dispose();
    }
    for (final c in _pcsControllers.values) {
      c.dispose();
    }
    _searchController.dispose();
    super.dispose();
  }

  String get _monthParam => DateFormat('yyyy-MM-01').format(_month);

  TextEditingController _cartonFor(String id) =>
      _cartonControllers.putIfAbsent(id, () => TextEditingController());
  TextEditingController _pcsFor(String id) => _pcsControllers.putIfAbsent(id, () => TextEditingController());

  Future<_EtpData> _load(String companyId) async {
    final client = ref.read(insforgeClientProvider);
    final productRows =
        await client.from('products').select().eq('company_id', companyId).eq('is_active', true).order('name').get();
    final products = productRows.map(Product.fromJson).toList();
    final ids = products.map((p) => p.id).toSet();
    final categoryRows = await client.from('categories').select().eq('company_id', companyId).order('name').get();

    final etpRows = await client.from('product_monthly_etp').select().order('month').get();

    final thisMonth = <String, ({double? carton, double? pcs})>{};
    final carried = <String, ({double? carton, double? pcs})>{};
    for (final row in etpRows) {
      final productId = row['product_id'] as String;
      if (!ids.contains(productId)) continue;
      final rowMonth = DateTime.parse(row['month'] as String);
      final value = (
        carton: (row['etp_per_carton'] as num?)?.toDouble(),
        pcs: (row['etp_per_pcs'] as num?)?.toDouble(),
      );
      if (rowMonth.year == _month.year && rowMonth.month == _month.month) {
        thisMonth[productId] = value;
      }
      // Rows arrive oldest first, so the last one at or before this month wins.
      if (!rowMonth.isAfter(_month)) carried[productId] = value;
    }

    // Each figure falls back to the sheet on its own, matching what
    // product_unit_dp_at does — a month that set only the piece price still
    // costs cartons at the sheet figure.
    for (final product in products) {
      final found = carried[product.id];
      carried[product.id] = (
        carton: found?.carton ?? product.etpPerCarton,
        pcs: found?.pcs ?? product.etpPerPcs,
      );
    }

    for (final product in products) {
      final set = thisMonth[product.id];
      final cartonText = set?.carton == null ? '' : set!.carton!.toStringAsFixed(2);
      final pcsText = set?.pcs == null ? '' : set!.pcs!.toStringAsFixed(2);
      final carton = _cartonFor(product.id);
      final pcs = _pcsFor(product.id);
      if (carton.text.isEmpty || carton.text != cartonText) carton.text = cartonText;
      if (pcs.text.isEmpty || pcs.text != pcsText) pcs.text = pcsText;
    }

    return _EtpData(
      products: products,
      categories: categoryRows.map(Category.fromJson).toList(),
      thisMonth: thisMonth,
      carriedForward: carried,
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
    for (final c in _cartonControllers.values) {
      c.clear();
    }
    for (final c in _pcsControllers.values) {
      c.clear();
    }
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _reload();
  }

  Future<void> _save(_EtpData data) async {
    final rows = <Map<String, dynamic>>[];
    for (final product in data.products) {
      final carton = double.tryParse(_cartonFor(product.id).text.trim());
      final pcs = double.tryParse(_pcsFor(product.id).text.trim());
      final wasSet = data.thisMonth.containsKey(product.id);
      if (carton != null || pcs != null) {
        rows.add({'product_id': product.id, 'etp_per_carton': carton, 'etp_per_pcs': pcs});
      } else if (wasSet) {
        rows.add({'product_id': product.id, 'etp_per_carton': null, 'etp_per_pcs': null});
      }
    }
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nothing to save')));
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(insforgeClientProvider).rpc('set_monthly_etp', {
        'p_month': _monthParam,
        'p_rows': rows,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved ${DateFormat.yMMMM().format(_month)} ETP')),
        );
        _reload();
      }
    } on InsforgeException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Copies whatever each product costs this month into the boxes, so a new
  /// month starts from last month's figures instead of empty.
  void _carryForward(_EtpData data) {
    setState(() {
      for (final product in data.products) {
        final value = data.carriedForward[product.id];
        if (value == null) continue;
        if (value.carton != null) _cartonFor(product.id).text = value.carton!.toStringAsFixed(2);
        if (value.pcs != null) _pcsFor(product.id).text = value.pcs!.toStringAsFixed(2);
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Filled from the last set month — adjust what changed, then Save')),
    );
  }

  Widget _numberBox(TextEditingController controller, String? placeholder) {
    return SizedBox(
      width: 96,
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          prefixText: '৳',
          hintText: placeholder,
          hintStyle: const TextStyle(color: VizChrome.muted, fontSize: 12),
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _buildCategoryTable(BuildContext context, _EtpData data, List<Product> products, double minWidth) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: minWidth),
          child: DataTable(
            dataRowMinHeight: 48,
            dataRowMaxHeight: 48,
            headingTextStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: VizChrome.secondaryInk,
            ),
            dataTextStyle: const TextStyle(fontSize: 13),
            columnSpacing: 20,
            columns: const [
              DataColumn(label: Text('Product')),
              DataColumn(label: Text('ETP / carton')),
              DataColumn(label: Text('ETP / piece')),
              DataColumn(label: Text('In force')),
            ],
            rows: [
              for (final product in products)
                DataRow(
                  cells: [
                    DataCell(Text(product.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                    DataCell(_numberBox(
                      _cartonFor(product.id),
                      data.carriedForward[product.id]?.carton?.toStringAsFixed(2),
                    )),
                    DataCell(_numberBox(
                      _pcsFor(product.id),
                      data.carriedForward[product.id]?.pcs?.toStringAsFixed(2),
                    )),
                    DataCell(Text(
                      data.thisMonth.containsKey(product.id) ? 'This month' : 'Carried forward',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: data.thisMonth.containsKey(product.id)
                            ? StatusLevel.good.color
                            : VizChrome.secondaryInk,
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
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    tooltip: 'Previous month',
                    onPressed: _saving ? null : () => _changeMonth(-1),
                  ),
                  Text(DateFormat.yMMMM().format(_month),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    tooltip: 'Next month',
                    onPressed: _saving ? null : () => _changeMonth(1),
                  ),
                ],
              ),
              if (_future != null)
                FutureBuilder<_EtpData>(
                  future: _future,
                  builder: (context, snapshot) => OutlinedButton.icon(
                    onPressed: _saving || !snapshot.hasData ? null : () => _carryForward(snapshot.data!),
                    icon: const Icon(Icons.copy_all, size: 16),
                    label: const Text('Fill from last set month'),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
        const Divider(height: 1),
        Expanded(
          child: _future == null
              ? const SizedBox.shrink()
              : FutureBuilder<_EtpData>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return Padding(padding: const EdgeInsets.all(AppSpace.md), child: const SkeletonTable());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('Failed to load ETP: ${snapshot.error}'));
                    }
                    final data = snapshot.data!;
                    final usesEtp = _company?.costBasis == CompanyCostBasis.etp;
                    final query = _search.trim().toLowerCase();
                    final visible = query.isEmpty
                        ? data.products
                        : data.products.where((p) => p.name.toLowerCase().contains(query)).toList();
                    if (visible.isEmpty) {
                      return Center(child: Text('No products match "${_search.trim()}".'));
                    }
                    final byCategory = <String, List<Product>>{};
                    for (final product in visible) {
                      byCategory.putIfAbsent(product.categoryId, () => []).add(product);
                    }

                    return LayoutBuilder(
                      builder: (context, constraints) => ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          Card(
                            color: (usesEtp ? VizChrome.info : StatusLevel.warning.color).withValues(alpha: 0.08),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                usesEtp
                                    ? 'Profit is measured against ETP. A month with nothing set carries forward '
                                        'the last month you did set, so you only record what changed — and past '
                                        'months keep the figures they were costed at.'
                                    : "${_company!.name} profit is measured against "
                                        '${_company!.costBasis.label}, not ETP, so anything you set here will '
                                        'not affect its profit until the cost basis is changed.',
                                style: const TextStyle(fontSize: 12, color: VizChrome.secondaryInk),
                              ),
                            ),
                          ),
                          for (final category in data.categories)
                            if (byCategory[category.id] case final products?) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                                child: Text(category.name, style: Theme.of(context).textTheme.titleMedium),
                              ),
                              _buildCategoryTable(context, data, products, constraints.maxWidth - 24),
                            ],
                        ],
                      ),
                    );
                  },
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Applies to ${DateFormat.yMMMM().format(_month)}',
                  style: const TextStyle(color: VizChrome.secondaryInk, fontSize: 12),
                ),
              ),
              if (_future != null)
                FutureBuilder<_EtpData>(
                  future: _future,
                  builder: (context, snapshot) => FilledButton(
                    onPressed: _saving || !snapshot.hasData ? null : () => _save(snapshot.data!),
                    child: _saving
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Save ETP'),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
