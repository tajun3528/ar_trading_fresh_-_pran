import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auto_refresh_mixin.dart';
import '../../core/insforge/insforge_exception.dart';
import '../../core/providers.dart';
import '../../core/viz/status_palette.dart';
import '../../models/category.dart';
import '../../models/product.dart';
import '../../models/profit.dart';
import '../../models/unit_type.dart';
import '../../core/design/design_tokens.dart';
import '../../core/motion/skeleton.dart';

const _displayUnits = [UnitType.carton, UnitType.box, UnitType.poli, UnitType.jar, UnitType.pcs];

class _PricesData {
  _PricesData({
    required this.products,
    required this.categories,
    required this.units,
    required this.saved,
    required this.dp,
    required this.tp,
  });

  final List<Product> products;
  final List<Category> categories;

  /// Which units each product is actually sold in.
  final Map<String, Set<UnitType>> units;

  /// What this salesman already set for the chosen month.
  final Map<String, double> saved;

  /// Cost per unit, straight from the backend so it always matches what
  /// profit is measured against. Keyed like [saved].
  final Map<String, double> dp;

  /// The company's own trade price per unit — the catalog's live price.
  final Map<String, double> tp;
}

/// Where a salesman sets what they'll sell each product for, month by month.
/// These prices are what every profit figure is measured against, so the
/// screen leads with how many are still unset for the month.
class MonthlyPricesScreen extends ConsumerStatefulWidget {
  const MonthlyPricesScreen({super.key});

  @override
  ConsumerState<MonthlyPricesScreen> createState() => _MonthlyPricesScreenState();
}

class _MonthlyPricesScreenState extends ConsumerState<MonthlyPricesScreen>
    with AutoRefreshMixin<MonthlyPricesScreen> {
  late Future<_PricesData> _future;
  final Map<String, TextEditingController> _controllers = {};
  final _searchController = TextEditingController();
  String _search = '';
  late DateTime _month;
  bool _saving = false;

  @override
  void refreshData() => setState(() { _future = _load(); });

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _future = _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _searchController.dispose();
    super.dispose();
  }

  String _key(String productId, UnitType unit) => '$productId|${unit.name}';

  TextEditingController _controllerFor(String productId, UnitType unit) =>
      _controllers.putIfAbsent(_key(productId, unit), () => TextEditingController());

  String get _monthParam => DateFormat('yyyy-MM-01').format(_month);

  Future<_PricesData> _load() async {
    final client = ref.read(insforgeClientProvider);
    final companyId = ref.read(authControllerProvider).valueOrNull?.companyId;
    if (companyId == null) {
      return _PricesData(
        products: const [],
        categories: const [],
        units: const {},
        saved: const {},
        dp: const {},
        tp: const {},
      );
    }

    final productRows =
        await client.from('products').select().eq('is_active', true).eq('company_id', companyId).order('name').get();
    final categoryRows = await client.from('categories').select().eq('company_id', companyId).order('name').get();
    final products = productRows.map(Product.fromJson).toList();
    final productIds = products.map((p) => p.id).toSet();

    // product_unit_costs carries both the live trade price and the backend's
    // own DP figure, so "Set as TP"/"Set as DP" fill exactly what the catalog
    // charges and what profit is costed at.
    final unitRows = await client.from('product_unit_costs').select().get();
    final units = <String, Set<UnitType>>{};
    final dp = <String, double>{};
    final tp = <String, double>{};
    for (final row in unitRows) {
      final productId = row['product_id'] as String;
      if (!productIds.contains(productId)) continue;
      final unit = UnitType.parse(row['unit_type'] as String);
      units.putIfAbsent(productId, () => {}).add(unit);
      final key = _key(productId, unit);
      final dpValue = (row['dp_price'] as num?)?.toDouble();
      if (dpValue != null) dp[key] = dpValue;
      final tpValue = (row['selling_price'] as num?)?.toDouble();
      if (tpValue != null) tp[key] = tpValue;
    }

    final priceRows =
        await client.from('salesman_monthly_prices').select().eq('month', _monthParam).get();
    final saved = <String, double>{};
    for (final row in priceRows.map(MonthlySellingPrice.fromJson)) {
      if (!productIds.contains(row.productId)) continue;
      saved[_key(row.productId, row.unitType)] = row.sellingPrice;
    }

    // Typed-but-unsaved edits win, so switching months or a background
    // refresh never wipes what's being typed.
    for (final entry in saved.entries) {
      final controller = _controllers[entry.key];
      if (controller == null || controller.text.isEmpty) {
        _controllerFor(entry.key.split('|')[0], UnitType.parse(entry.key.split('|')[1])).text =
            entry.value.toStringAsFixed(2);
      }
    }

    return _PricesData(
      products: products,
      categories: categoryRows.map(Category.fromJson).toList(),
      units: units,
      saved: saved,
      dp: dp,
      tp: tp,
    );
  }

  void _changeMonth(int delta) {
    for (final c in _controllers.values) {
      c.clear();
    }
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _future = _load();
    });
  }

  List<UnitType> _unitsFor(_PricesData data, Product product) {
    final available = data.units[product.id] ?? const <UnitType>{};
    return _displayUnits.where(available.contains).toList();
  }

  List<UnitType> _relevantUnits(_PricesData data, List<Product> products) {
    return _displayUnits.where((u) => products.any((p) => data.units[p.id]?.contains(u) ?? false)).toList();
  }

  int _unsetCount(_PricesData data) {
    var missing = 0;
    for (final product in data.products) {
      for (final unit in _unitsFor(data, product)) {
        final text = _controllerFor(product.id, unit).text.trim();
        if ((double.tryParse(text) ?? 0) <= 0) missing++;
      }
    }
    return missing;
  }

  Future<void> _save(_PricesData data) async {
    final entries = <Map<String, dynamic>>[];
    for (final product in data.products) {
      for (final unit in _unitsFor(data, product)) {
        final text = _controllerFor(product.id, unit).text.trim();
        final price = double.tryParse(text);
        final wasSaved = data.saved.containsKey(_key(product.id, unit));
        if (price != null && price > 0) {
          entries.add({'product_id': product.id, 'unit_type': unit.name, 'selling_price': price});
        } else if (wasSaved) {
          // Cleared on purpose — send it so the stored price is removed.
          entries.add({'product_id': product.id, 'unit_type': unit.name, 'selling_price': null});
        }
      }
    }
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter at least one price')));
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(insforgeClientProvider).rpc('set_monthly_prices', {
        'p_month': _monthParam,
        'p_prices': entries,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved ${DateFormat.yMMMM().format(_month)} prices')),
        );
        setState(() { _future = _load(); });
      }
    } on InsforgeException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Fills one product's row from its own DP or TP. No confirmation — a
  /// single row is trivial to retype, and the boxes update in place so the
  /// change is visible immediately.
  void _fillProduct(_PricesData data, Product product, {required bool useTp}) {
    final source = useTp ? data.tp : data.dp;
    final updates = <String, String>{};
    for (final unit in _unitsFor(data, product)) {
      final value = source[_key(product.id, unit)];
      if (value == null || value <= 0) continue;
      updates[_key(product.id, unit)] = value.toStringAsFixed(2);
    }

    if (updates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            useTp
                ? 'No trade price set for ${product.name}'
                : 'No DP for ${product.name} — set its per-carton count first',
          ),
        ),
      );
      return;
    }

    setState(() {
      for (final entry in updates.entries) {
        final parts = entry.key.split('|');
        _controllerFor(parts[0], UnitType.parse(parts[1])).text = entry.value;
      }
    });
  }

  /// Fills every price box with the product's own DP or TP as a starting
  /// point — the salesman then edits up or down from there. Nothing is saved
  /// until they press Save, so a mis-click is undone by leaving the screen.
  Future<void> _fillFrom(_PricesData data, {required bool useTp}) async {
    final filled = <String, String>{};
    var skipped = 0;
    for (final product in data.products) {
      for (final unit in _unitsFor(data, product)) {
        final key = _key(product.id, unit);
        final value = useTp ? data.tp[key] : data.dp[key];
        if (value == null || value <= 0) {
          skipped++;
          continue;
        }
        filled[key] = value.toStringAsFixed(2);
      }
    }

    if (filled.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No ${useTp ? 'TP' : 'DP'} figures available to fill from')),
      );
      return;
    }

    final existing = filled.keys.where((k) => (_controllers[k]?.text.trim() ?? '').isNotEmpty).length;
    if (existing > 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Set all prices to ${useTp ? 'TP' : 'DP'}?'),
          content: Text(
            'This replaces $existing price${existing == 1 ? '' : 's'} you have already entered, '
            'across all ${filled.length} units.'
            '${skipped > 0 ? '\n\n$skipped unit(s) have no ${useTp ? 'TP' : 'DP'} figure and stay as they are.' : ''}',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Replace')),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() {
      for (final entry in filled.entries) {
        final parts = entry.key.split('|');
        _controllerFor(parts[0], UnitType.parse(parts[1])).text = entry.value;
      }
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Filled ${filled.length} price${filled.length == 1 ? '' : 's'} from '
            '${useTp ? 'TP' : 'DP'}${skipped > 0 ? ' ($skipped skipped)' : ''} — press Save to keep them',
          ),
        ),
      );
    }
  }

  Future<void> _copyPreviousMonth() async {
    setState(() => _saving = true);
    try {
      await ref.read(insforgeClientProvider).rpc('copy_prices_from_previous_month', {'p_month': _monthParam});
      if (mounted) {
        for (final c in _controllers.values) {
          c.clear();
        }
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("Copied last month's prices — adjust what changed")));
        setState(() { _future = _load(); });
      }
    } on InsforgeException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildPriceCell(_PricesData data, Product product, UnitType unit) {
    if (!(data.units[product.id]?.contains(unit) ?? false)) {
      return const Text('—', style: TextStyle(color: VizChrome.muted));
    }
    return SizedBox(
      width: 84,
      child: TextField(
        controller: _controllerFor(product.id, unit),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13),
        decoration: const InputDecoration(prefixText: '৳', isDense: true, border: OutlineInputBorder()),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _buildCategoryTable(BuildContext context, _PricesData data, List<Product> products, double minWidth) {
    final units = _relevantUnits(data, products);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: minWidth),
          child: DataTable(
            showCheckboxColumn: false,
            dataRowMinHeight: 48,
            dataRowMaxHeight: 48,
            headingTextStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: VizChrome.secondaryInk,
            ),
            columnSpacing: 20,
            columns: [
              const DataColumn(label: Text('Product')),
              for (final u in units) DataColumn(label: Text('${u.label} price')),
              const DataColumn(label: Text('Set to')),
            ],
            rows: [
              for (final product in products)
                DataRow(
                  cells: [
                    DataCell(Text(product.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                    for (final u in units) DataCell(_buildPriceCell(data, product, u)),
                    DataCell(Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _MiniFillButton(
                          label: 'DP',
                          tooltip: 'Set ${product.name} to its DP cost',
                          onPressed: () => _fillProduct(data, product, useTp: false),
                        ),
                        const SizedBox(width: 6),
                        _MiniFillButton(
                          label: 'TP',
                          tooltip: 'Set ${product.name} to its trade price',
                          onPressed: () => _fillProduct(data, product, useTp: true),
                        ),
                      ],
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
    if (ref.watch(authControllerProvider).valueOrNull?.companyId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Monthly selling prices')),
        body: const Center(child: Text("You're not assigned to a company yet — ask the Owner to assign one.")),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Monthly selling prices')),
      body: FutureBuilder<_PricesData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Padding(padding: const EdgeInsets.all(AppSpace.md), child: const SkeletonTable());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Failed to load: ${snapshot.error}'));
          }
          final data = snapshot.data!;
          final query = _search.trim().toLowerCase();
          final visible = query.isEmpty
              ? data.products
              : data.products.where((p) => p.name.toLowerCase().contains(query)).toList();
          final byCategory = <String, List<Product>>{};
          for (final product in visible) {
            byCategory.putIfAbsent(product.categoryId, () => []).add(product);
          }
          final unset = _unsetCount(data);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
                        Text(
                          DateFormat.yMMMM().format(_month),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          tooltip: 'Next month',
                          onPressed: _saving ? null : () => _changeMonth(1),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _saving ? null : () => _fillFrom(data, useTp: false),
                          icon: const Icon(Icons.south_west, size: 16),
                          label: const Text('Set as DP'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _saving ? null : () => _fillFrom(data, useTp: true),
                          icon: const Icon(Icons.north_east, size: 16),
                          label: const Text('Set as TP'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _saving ? null : _copyPreviousMonth,
                          icon: const Icon(Icons.copy_all, size: 16),
                          label: const Text('Copy last month'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (unset > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: StatusLevel.warning.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$unset unit${unset == 1 ? '' : 's'} still without a price — sales of those '
                      "won't show any profit for this month.",
                      style: TextStyle(fontSize: 12, color: StatusLevel.warning.color, fontWeight: FontWeight.w600),
                    ),
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
                child: data.products.isEmpty
                    ? const Center(child: Text('No products to price.'))
                    : visible.isEmpty
                        ? Center(child: Text('No products match "${_search.trim()}".'))
                        : LayoutBuilder(
                            builder: (context, constraints) => ListView(
                              padding: const EdgeInsets.all(12),
                              children: [
                                for (final category in data.categories)
                                  if (byCategory[category.id] case final products?) ...[
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                                      child: Text(category.name, style: Theme.of(context).textTheme.titleMedium),
                                    ),
                                    _buildCategoryTable(context, data, products, constraints.maxWidth - 24),
                                    const SizedBox(height: 12),
                                  ],
                              ],
                            ),
                          ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Prices apply to ${DateFormat.yMMMM().format(_month)}',
                        style: const TextStyle(color: VizChrome.secondaryInk, fontSize: 12),
                      ),
                    ),
                    FilledButton(
                      onPressed: _saving ? null : () => _save(data),
                      child: _saving
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Save prices'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Compact enough to sit inside a table row without stretching it.
class _MiniFillButton extends StatelessWidget {
  const _MiniFillButton({required this.label, required this.tooltip, required this.onPressed});

  final String label;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(34, 26),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          visualDensity: VisualDensity.compact,
        ),
        child: Text(label),
      ),
    );
  }
}
