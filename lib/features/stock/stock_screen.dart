import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auto_refresh_mixin.dart';
import '../../core/company_selector.dart';
import '../../core/providers.dart';
import '../../core/viz/status_palette.dart';
import '../../models/category.dart';
import '../../models/company.dart';
import '../../models/product.dart';
import '../../models/unit_type.dart';
import '../catalog/product_detail_screen.dart';
import '../../core/design/design_tokens.dart';
import '../../core/motion/skeleton.dart';

/// Largest-to-smallest, matching the app's established column order —
/// iterated instead of hardcoded so a future unit type (see UnitType) shows
/// up in every "simple"-style table automatically.
const _displayUnits = [UnitType.carton, UnitType.box, UnitType.poli, UnitType.jar, UnitType.pcs];

typedef _StockByProduct = Map<String, Map<UnitType, int>>;
typedef _DamagedByProduct = Map<String, Map<UnitType, int>>;
typedef _PricesByProduct = Map<String, Map<UnitType, double>>;

class _StockData {
  _StockData({
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

/// Full stock ledger, grouped by category — one section per category with
/// every detail (carton/jar/pcs on hand, the carton rollup setting, unit
/// prices, low-stock threshold, damage, status) plus a direct edit action.
/// Mirrors the Products table: this screen is the stock-focused read of the
/// same data.
class StockScreen extends ConsumerStatefulWidget {
  const StockScreen({super.key});

  @override
  ConsumerState<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends ConsumerState<StockScreen> with AutoRefreshMixin<StockScreen> {
  Company? _company;
  Future<_StockData>? _future;
  final _searchController = TextEditingController();
  String _search = '';

  @override
  void refreshData() => _reload();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<_StockData> _load(String companyId) async {
    final client = ref.read(insforgeClientProvider);
    final productsRows = await client.from('products').select().eq('company_id', companyId).order('name').get();
    final categoryRows = await client.from('categories').select().eq('company_id', companyId).order('name').get();
    final allProducts = productsRows.map(Product.fromJson).toList();
    final productIds = allProducts.map((p) => p.id).toSet();

    // stock/product_units aren't company-scoped columns themselves (RLS
    // scopes them via a join on product_id instead — see the company-scoping
    // migration) — an Owner's unfiltered fetch here can include every
    // company's rows, so filter down to this company's own product ids.
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

    // Stock-specific view: only products that actually have a stock record
    // (i.e. some stock-in has happened for them) — a product with no stock
    // history yet belongs on the Products catalog, not here.
    final stockedProducts = allProducts.where((p) => stock.containsKey(p.id)).toList();

    return _StockData(
      products: stockedProducts,
      categories: categoryRows.map(Category.fromJson).toList(),
      stock: stock,
      damaged: damaged,
      prices: prices,
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

  Future<void> _openProduct(Product product) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProductDetailScreen(product: product)),
    );
    _reload();
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

  /// Low only when *every* unit is down to the threshold. Flagging on any one
  /// unit marked most of the catalog low: loose pieces sit at zero by design
  /// once they roll up into a carton, so a product with 92 cartons and no
  /// loose pieces was being reported as needing restock.
  bool _isLowStock(Product product, _StockData data) {
    final byUnit = data.stock[product.id];
    if (byUnit == null || byUnit.isEmpty) return false;
    // Only units the product is actually sold in count — a leftover stock row
    // for an unpriced unit isn't shown in the table, so letting it sway the
    // verdict would give a "Low" flag with nothing on screen to justify it.
    final priced = byUnit.entries.where((e) => data.prices[product.id]?.containsKey(e.key) ?? false);
    if (priced.isEmpty) return false;
    return priced.every((e) => e.value <= product.lowStockThreshold);
  }

  /// Sum of available qty × price across carton/jar/pcs — the units are
  /// independent stock, not convertible into each other, but each unit's own
  /// value in Taka adds up into one figure.
  double _totalValue(_StockData data, String productId) {
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
  List<UnitType> _relevantUnits(_StockData data, List<Product> products) {
    return _displayUnits.where((u) => products.any((p) => data.prices[p.id]?.containsKey(u) ?? false)).toList();
  }

  /// One category's stocked products as a table — no Category column since
  /// the section header above it already says which one this is.
  Widget _buildCategoryTable(BuildContext context, _StockData data, List<Product> products, bool isTradePricing) {
    final units = _relevantUnits(data, products);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          showCheckboxColumn: false,
          headingTextStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: VizChrome.secondaryInk,
          ),
          dataTextStyle: const TextStyle(fontSize: 13),
          columnSpacing: 24,
          // Trade-pricing companies used to be carton-only; now they nest
          // carton → jar → piece like the rest, so every unit gets a column
          // rather than a single "Available" that hid them.
          columns: isTradePricing
              ? [
                  const DataColumn(label: Text('Product')),
                  for (final u in units) DataColumn(label: Text(u.label)),
                  for (final u in units) DataColumn(label: Text('Price/${u.label}')),
                  const DataColumn(label: Text('Total Value')),
                  const DataColumn(label: Text('Item Code')),
                  const DataColumn(label: Text('DP')),
                  const DataColumn(label: Text('MRP')),
                  const DataColumn(label: Text('Damaged')),
                  const DataColumn(label: Text('Status')),
                  const DataColumn(label: Text('')),
                ]
              : [
                  const DataColumn(label: Text('Product')),
                  // Quantity columns stay together and uninterrupted — the
                  // pack-size setting used to sit right after them and got
                  // read as another quantity in stock.
                  for (final u in units) DataColumn(label: Text(u.label)),
                  for (final u in units) DataColumn(label: Text('Price/${u.label}')),
                  const DataColumn(label: Text('Total Value')),
                  const DataColumn(label: Text('Pcs per carton')),
                  const DataColumn(label: Text('Threshold')),
                  const DataColumn(label: Text('Damaged')),
                  const DataColumn(label: Text('Status')),
                  const DataColumn(label: Text('')),
                ],
          rows: [
            for (final product in products)
              DataRow(
                onSelectChanged: (_) => _openProduct(product),
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
                        DataCell(Text(product.dpPrice == null ? '—' : '৳${product.dpPrice!.toStringAsFixed(2)}')),
                        DataCell(Text(product.mrpPrice == null ? '—' : '৳${product.mrpPrice!.toStringAsFixed(2)}')),
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
                        DataCell(IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          tooltip: 'Edit ${product.name}',
                          onPressed: () => _openProduct(product),
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
                        DataCell(IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          tooltip: 'Edit ${product.name}',
                          onPressed: () => _openProduct(product),
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
    final isTradePricing = _company?.catalogStyle == CompanyCatalogStyle.tradePricing;
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: Column(
        children: [
          CompanySelector(selectedId: _company?.id, onChanged: _onCompanyChanged),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
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
            child: _future == null
                ? const SizedBox.shrink()
                : FutureBuilder<_StockData>(
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
                        return const Center(child: Text('No stock recorded yet. Open a product to add stock.'));
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
                      final sections = [
                        for (final category in data.categories)
                          if (byCategory[category.id] case final products?) (category, products),
                      ];
                      // Lazy, not SingleChildScrollView + Column: the whole
                      // catalog is one table per category and building them
                      // all up front costs thousands of cells before the
                      // first frame.
                      return ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: sections.length,
                        itemBuilder: (context, i) {
                          final (category, products) = sections[i];
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                                child: Text(category.name, style: Theme.of(context).textTheme.titleMedium),
                              ),
                              _buildCategoryTable(context, data, products, isTradePricing),
                              const SizedBox(height: 12),
                            ],
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
