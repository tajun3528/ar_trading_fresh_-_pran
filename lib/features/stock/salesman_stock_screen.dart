import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auto_refresh_mixin.dart';
import '../../core/providers.dart';
import '../../core/viz/status_palette.dart';
import '../../models/category.dart';
import '../../models/company.dart';
import '../../models/product.dart';
import '../../models/unit_type.dart';
import '../../core/design/design_tokens.dart';
import '../../core/motion/skeleton.dart';

/// Largest-to-smallest, matching the app's established column order —
/// iterated instead of hardcoded so a future unit type (see UnitType) shows
/// up in every "simple"-style table automatically.
const _displayUnits = [UnitType.carton, UnitType.box, UnitType.poli, UnitType.jar, UnitType.pcs];

typedef _StockByProduct = Map<String, Map<UnitType, int>>;
typedef _DamagedByProduct = Map<String, Map<UnitType, int>>;
typedef _PricesByProduct = Map<String, Map<UnitType, double>>;

class _SalesmanStockData {
  _SalesmanStockData({
    required this.products,
    required this.categories,
    required this.stock,
    required this.damaged,
    required this.prices,
  });

  final List<Product> products;
  final List<Category> categories;
  final _StockByProduct stock;
  final _DamagedByProduct damaged;
  final _PricesByProduct prices;
}

/// Same category-grouped, searchable representation as the Owner's
/// Stock/Products pages — read-only for the salesman (no edit action),
/// scoped to their own assigned company.
class SalesmanStockScreen extends ConsumerStatefulWidget {
  const SalesmanStockScreen({super.key});

  @override
  ConsumerState<SalesmanStockScreen> createState() => _SalesmanStockScreenState();
}

class _SalesmanStockScreenState extends ConsumerState<SalesmanStockScreen>
    with AutoRefreshMixin<SalesmanStockScreen> {
  Future<_SalesmanStockData>? _future;
  String? _loadedForCompanyId;
  final _searchController = TextEditingController();
  String _search = '';

  @override
  void refreshData() {
    final companyId = _loadedForCompanyId;
    if (companyId != null) setState(() { _future = _load(companyId); });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<_SalesmanStockData> _load(String companyId) async {
    final client = ref.read(insforgeClientProvider);
    final productsRows = await client
        .from('products')
        .select()
        .eq('is_active', true)
        .eq('company_id', companyId)
        .order('name')
        .get();
    final categoryRows = await client.from('categories').select().eq('company_id', companyId).order('name').get();
    final products = productsRows.map(Product.fromJson).toList();
    final productIds = products.map((p) => p.id).toSet();

    final stockRows = await client.from('stock').select().get();
    final unitRows = await client.from('product_units').select().get();

    final stock = <String, Map<UnitType, int>>{};
    final damaged = <String, Map<UnitType, int>>{};
    for (final row in stockRows) {
      final productId = row['product_id'] as String;
      if (!productIds.contains(productId)) continue;
      final unit = UnitType.parse(row['unit_type'] as String);
      stock.putIfAbsent(productId, () => {})[unit] = row['available_qty'] as int;
      damaged.putIfAbsent(productId, () => {})[unit] = row['damaged_qty'] as int;
    }

    final prices = <String, Map<UnitType, double>>{};
    for (final row in unitRows) {
      final unit = ProductUnit.fromJson(row);
      if (!productIds.contains(unit.productId)) continue;
      prices.putIfAbsent(unit.productId, () => {})[unit.unitType] = unit.price;
    }

    final stockedProducts = products.where((p) => stock.containsKey(p.id)).toList();

    return _SalesmanStockData(
      products: stockedProducts,
      categories: categoryRows.map(Category.fromJson).toList(),
      stock: stock,
      damaged: damaged,
      prices: prices,
    );
  }

  String _qtyText(_StockByProduct stock, String productId, UnitType unit) {
    final qty = stock[productId]?[unit];
    return qty == null ? '—' : '$qty';
  }

  String _priceText(_PricesByProduct prices, String productId, UnitType unit) {
    final price = prices[productId]?[unit];
    return price == null ? '—' : '৳${price.toStringAsFixed(2)}';
  }

  String _damagedText(_DamagedByProduct damaged, String productId) {
    final byUnit = damaged[productId];
    if (byUnit == null) return '—';
    final parts = [
      for (final unit in UnitType.values)
        if ((byUnit[unit] ?? 0) > 0) '${byUnit[unit]} ${unit.label.toLowerCase()}',
    ];
    return parts.isEmpty ? '—' : parts.join(', ');
  }

  /// Low only when *every* priced unit is down to the threshold — see the
  /// same method on the Owner's stock screen for why "any unit" was wrong,
  /// and why unpriced leftover stock rows are ignored.
  bool _isLowStock(Product product, _SalesmanStockData data) {
    final byUnit = data.stock[product.id];
    if (byUnit == null || byUnit.isEmpty) return false;
    final priced = byUnit.entries.where((e) => data.prices[product.id]?.containsKey(e.key) ?? false);
    if (priced.isEmpty) return false;
    return priced.every((e) => e.value <= product.lowStockThreshold);
  }

  double _totalValue(_SalesmanStockData data, String productId) {
    final byUnit = data.stock[productId];
    if (byUnit == null) return 0;
    var total = 0.0;
    for (final entry in byUnit.entries) {
      final price = data.prices[productId]?[entry.key];
      if (price != null) total += entry.value * price;
    }
    return total;
  }

  /// Only the units this category's own products actually price/stock in —
  /// e.g. Snacks never shows empty Box/Jar columns just because some other
  /// category uses them.
  List<UnitType> _relevantUnits(_SalesmanStockData data, List<Product> products) {
    return _displayUnits.where((u) => products.any((p) => data.prices[p.id]?.containsKey(u) ?? false)).toList();
  }

  /// One category's stocked products as a table — no Category column since
  /// the section header above it already says which one this is.
  Widget _buildCategoryTable(
    BuildContext context,
    _SalesmanStockData data,
    List<Product> products,
    bool isTradePricing,
  ) {
    final units = _relevantUnits(data, products);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingTextStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: VizChrome.secondaryInk,
          ),
          dataTextStyle: const TextStyle(fontSize: 13),
          columnSpacing: 24,
          // Trade-pricing companies nest carton → jar → piece now, so each
          // unit gets its own column instead of one "Available" that showed
          // cartons only.
          columns: isTradePricing
              ? [
                  const DataColumn(label: Text('Product')),
                  for (final u in units) DataColumn(label: Text(u.label)),
                  for (final u in units) DataColumn(label: Text('Price/${u.label}')),
                  const DataColumn(label: Text('Total Value')),
                  const DataColumn(label: Text('Item Code')),
                  const DataColumn(label: Text('Damaged')),
                  const DataColumn(label: Text('Status')),
                ]
              : [
                  const DataColumn(label: Text('Product')),
                  // Quantity columns stay together — the pack-size setting
                  // beside them was being read as a quantity in stock.
                  for (final u in units) DataColumn(label: Text(u.label)),
                  for (final u in units) DataColumn(label: Text('Price/${u.label}')),
                  const DataColumn(label: Text('Total Value')),
                  const DataColumn(label: Text('Pcs per carton')),
                  const DataColumn(label: Text('Threshold')),
                  const DataColumn(label: Text('Damaged')),
                  const DataColumn(label: Text('Status')),
                ],
          rows: [
            for (final product in products)
              DataRow(
                color: _isLowStock(product, data)
                    ? WidgetStateProperty.all(StatusLevel.warning.color.withValues(alpha: 0.06))
                    : null,
                cells: isTradePricing
                    ? [
                        DataCell(Text(product.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                        for (final u in units) DataCell(Text(_qtyText(data.stock, product.id, u))),
                        for (final u in units) DataCell(Text(_priceText(data.prices, product.id, u))),
                        DataCell(Text(
                          '৳${_totalValue(data, product.id).toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        )),
                        DataCell(Text(product.itemCode ?? '—')),
                        DataCell(Text(
                          _damagedText(data.damaged, product.id),
                          style: TextStyle(color: StatusLevel.serious.color),
                        )),
                        DataCell(Text(
                          _isLowStock(product, data) ? 'Low' : 'Healthy',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: _isLowStock(product, data) ? StatusLevel.warning.color : StatusLevel.good.color,
                          ),
                        )),
                      ]
                    : [
                        DataCell(Text(product.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                        for (final u in units) DataCell(Text(_qtyText(data.stock, product.id, u))),
                        for (final u in units) DataCell(Text(_priceText(data.prices, product.id, u))),
                        DataCell(Text(
                          '৳${_totalValue(data, product.id).toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        )),
                        DataCell(Text(product.pcsPerCarton?.toString() ?? '—')),
                        DataCell(Text('${product.lowStockThreshold}')),
                        DataCell(Text(
                          _damagedText(data.damaged, product.id),
                          style: TextStyle(color: StatusLevel.serious.color),
                        )),
                        DataCell(Text(
                          _isLowStock(product, data) ? 'Low' : 'Healthy',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: _isLowStock(product, data) ? StatusLevel.warning.color : StatusLevel.good.color,
                          ),
                        )),
                      ],
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final companyId = ref.watch(authControllerProvider).valueOrNull?.companyId;
    if (companyId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Stock')),
        body: const Center(child: Text("You're not assigned to a company yet — ask the Owner to assign one.")),
      );
    }
    if (_loadedForCompanyId != companyId) {
      _loadedForCompanyId = companyId;
      _future = _load(companyId);
    }

    final company = Company.findById(ref.watch(companiesProvider).valueOrNull ?? const [], companyId);
    final isTradePricing = company?.catalogStyle == CompanyCatalogStyle.tradePricing;

    return Scaffold(
      appBar: AppBar(title: const Text('Stock')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search products by name or item code',
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
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => refreshData(),
              child: FutureBuilder<_SalesmanStockData>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return Padding(padding: const EdgeInsets.all(AppSpace.md), child: const SkeletonTable());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Failed to load stock: ${snapshot.error}'));
                  }
                  final data = snapshot.data!;
                  if (data.products.isEmpty) {
                    return const Center(child: Text('No stock recorded yet.'));
                  }
                  final query = _search.trim().toLowerCase();
                  final visibleProducts = query.isEmpty
                      ? data.products
                      : data.products.where((p) {
                          return p.name.toLowerCase().contains(query) ||
                              (p.itemCode?.toLowerCase().contains(query) ?? false);
                        }).toList();
                  if (visibleProducts.isEmpty) {
                    return Center(child: Text('No products match "${_search.trim()}".'));
                  }
                  final byCategory = <String, List<Product>>{};
                  for (final product in visibleProducts) {
                    byCategory.putIfAbsent(product.categoryId, () => []).add(product);
                  }
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final category in data.categories)
                          if (byCategory[category.id] case final products?) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                              child: Text(category.name, style: Theme.of(context).textTheme.titleMedium),
                            ),
                            _buildCategoryTable(context, data, products, isTradePricing),
                            const SizedBox(height: 12),
                          ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
