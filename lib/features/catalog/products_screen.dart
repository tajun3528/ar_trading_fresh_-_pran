import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auto_refresh_mixin.dart';
import '../../core/company_selector.dart';
import '../../core/insforge/insforge_exception.dart';
import '../../core/providers.dart';
import '../../core/viz/status_palette.dart';
import '../../models/category.dart';
import '../../models/company.dart';
import '../../models/product.dart';
import '../../models/unit_type.dart';
import 'product_detail_screen.dart';
import '../../core/design/design_tokens.dart';
import '../../core/motion/skeleton.dart';

/// Largest-to-smallest, matching the app's established column order —
/// iterated instead of hardcoded so a future unit type (see UnitType) shows
/// up in every "simple"-style table automatically.
const _displayUnits = [UnitType.carton, UnitType.box, UnitType.poli, UnitType.jar, UnitType.pcs];

typedef _StockByProduct = Map<String, Map<UnitType, int>>;
typedef _DamagedByProduct = Map<String, Map<UnitType, int>>;
typedef _PricesByProduct = Map<String, Map<UnitType, double>>;

class _ProductsData {
  _ProductsData({
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

class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> with AutoRefreshMixin<ProductsScreen> {
  Company? _company;
  Future<_ProductsData>? _future;
  final _searchController = TextEditingController();
  String _search = '';

  @override
  void refreshData() => _reload();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<_ProductsData> _load(String companyId) async {
    final client = ref.read(insforgeClientProvider);
    final productsRows = await client.from('products').select().eq('company_id', companyId).order('name').get();
    final categoryRows = await client.from('categories').select().eq('company_id', companyId).order('name').get();
    final products = productsRows.map(Product.fromJson).toList();
    final productIds = products.map((p) => p.id).toSet();

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

    return _ProductsData(
      products: products,
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

  /// Everything a product needs to be usable, in one form: how a carton
  /// breaks down, what each unit sells for, and what it costs.
  ///
  /// It used to collect a name, a category and a threshold, which left every
  /// new product with no price for any unit — so it could not be ordered at
  /// all until someone opened it and filled in the rest. For a trade-pricing
  /// catalog that was worse, because the detail screen then only offered a
  /// carton price, and the product stayed carton-only for good.
  Future<void> _showAddForm(List<Category> categories, bool isTradePricing) async {
    final company = _company;
    if (company == null) return;
    if (categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add a category first.')));
      return;
    }

    final name = TextEditingController();
    final threshold = TextEditingController(text: '0');
    final perCarton = {for (final u in _packUnits) u: TextEditingController()};
    final prices = {for (final u in UnitType.values) u: TextEditingController()};
    final costPerPiece = TextEditingController();
    final costPerPack = TextEditingController();
    var categoryId = categories.first.id;

    int? whole(TextEditingController c) => int.tryParse(c.text.trim());
    double? money(TextEditingController c) => double.tryParse(c.text.trim());

    final basis = company.costBasis;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Price lists are written one carton at a time, with the smaller
          // units divided down by how many fit — so offer that as one tap
          // rather than making someone do it by hand for every product.
          void fillFromCarton() {
            final carton = money(prices[UnitType.carton]!);
            if (carton == null || carton <= 0) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Enter the carton price first')));
              return;
            }
            var filled = 0;
            for (final unit in _packUnits) {
              final count = whole(perCarton[unit]!);
              if (count == null || count <= 0) continue;
              prices[unit]!.text = (carton / count).toStringAsFixed(2);
              filled++;
            }
            if (filled == 0) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Enter how many fit in a carton first')));
            }
            setDialogState(() {});
          }

          return AlertDialog(
            title: Text('New ${company.name} product'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: name,
                      autofocus: true,
                      decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: AppSpace.md),
                    DropdownButtonFormField<String>(
                      initialValue: categoryId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                      items: [
                        for (final c in categories)
                          DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) => setDialogState(() => categoryId = v ?? categoryId),
                    ),
                    const SizedBox(height: AppSpace.md),
                    TextField(
                      controller: threshold,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Low-stock threshold', border: OutlineInputBorder()),
                    ),
                    const _FormHeading('Packaging', 'How one carton breaks down. Leave blank what does not apply.'),
                    for (final unit in _packUnits)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpace.sm),
                        child: TextField(
                          controller: perCarton[unit],
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: '${_plural(unit)} per carton',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                    const _FormHeading(
                        'Selling price', 'A unit can only be ordered once it has a price.'),
                    for (final unit in UnitType.values)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpace.sm),
                        child: TextField(
                          controller: prices[unit],
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: '${unit.label} price',
                            prefixText: '৳ ',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: fillFromCarton,
                        icon: const Icon(Icons.calculate_outlined, size: 16),
                        label: const Text('Fill the rest from the carton price'),
                      ),
                    ),
                    if (basis != CompanyCostBasis.dp) ...[
                      _FormHeading(
                        'Cost — ${basis.label}',
                        'What ${company.name} charges you. Profit is measured against this, so a '
                            'product without it sells with no margin figure.',
                      ),
                      TextField(
                        controller: costPerPiece,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: '${basis.label} per piece',
                          prefixText: '৳ ',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: AppSpace.sm),
                      TextField(
                        controller: costPerPack,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: basis == CompanyCostBasis.etp
                              ? '${basis.label} per carton'
                              : '${basis.label} per jar or box',
                          prefixText: '৳ ',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
            ],
          );
        },
      ),
    );

    if (saved != true || name.text.trim().isEmpty) return;

    final pcsPerCarton = whole(perCarton[UnitType.pcs]!);
    final jarPerCarton = whole(perCarton[UnitType.jar]!);

    final row = <String, dynamic>{
      'name': name.text.trim(),
      'category_id': categoryId,
      'company_id': company.id,
      'low_stock_threshold': whole(threshold) ?? 0,
      'pcs_per_carton': pcsPerCarton,
      'poli_per_carton': whole(perCarton[UnitType.poli]!),
      'jar_per_carton': jarPerCarton,
      'box_per_carton': whole(perCarton[UnitType.box]!),
    };

    // An After Trade TP company works out the cost of one jar as
    // per_pcs_tp_price * (factor / jar_per_carton), so factor has to carry the
    // pieces in a carton or every unit's cost comes back null — which is
    // exactly how a new product ends up selling with no margin figure.
    if (basis == CompanyCostBasis.afterTradeTp) {
      row['factor'] = pcsPerCarton;
      row['per_pcs_tp_price'] = money(costPerPiece);
      row['after_trade_tp_price'] = money(costPerPack);
      if (pcsPerCarton != null && jarPerCarton != null && jarPerCarton > 0) {
        row['jar_box_size'] = pcsPerCarton ~/ jarPerCarton;
      }
    } else if (basis == CompanyCostBasis.etp) {
      row['etp_per_pcs'] = money(costPerPiece);
      row['etp_per_carton'] = money(costPerPack);
    }

    final client = ref.read(insforgeClientProvider);
    try {
      final created = await client.from('products').insert([row]);
      final productId = created.first['id'] as String;

      final unitRows = <Map<String, dynamic>>[];
      for (final unit in UnitType.values) {
        final price = money(prices[unit]!);
        if (price == null || price <= 0) continue;
        unitRows.add({'product_id': productId, 'unit_type': unit.name, 'price': price});
      }
      if (unitRows.isNotEmpty) {
        await client.from('product_units').insert(unitRows);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(unitRows.isEmpty
                ? 'Added ${name.text.trim()} — give it a price before it can be ordered'
                : 'Added ${name.text.trim()} — orderable in ${unitRows.length} unit(s)'),
          ),
        );
      }
      _reload();
    } on InsforgeException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Moving a product between categories is available inside the full edit
  /// dialog too, but that means opening the product and passing twenty vendor
  /// fields — this is the direct route for re-organising the catalog.
  Future<void> _showMoveCategoryDialog(Product product, List<Category> categories) async {
    if (categories.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('There is only one category to put it in.')),
      );
      return;
    }

    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Move "${product.name}" to'),
        children: [
          for (final category in categories)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, category.id),
              child: Row(
                children: [
                  Icon(
                    category.id == product.categoryId ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    size: 18,
                    color: category.id == product.categoryId ? Theme.of(context).colorScheme.primary : VizChrome.muted,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      category.name,
                      style: TextStyle(
                        fontWeight: category.id == product.categoryId ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ),
          ),
        ],
      ),
    );
    if (picked == null || picked == product.categoryId) return;

    final client = ref.read(insforgeClientProvider);
    try {
      await client.from('products').eq('id', product.id).update({'category_id': picked});
      if (mounted) {
        final name = categories.firstWhere((c) => c.id == picked).name;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Moved to $name')));
      }
      _reload();
    } on InsforgeException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
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

  /// Sum of available qty × price across carton/jar/pcs — the units are
  /// independent stock, not convertible into each other, but each unit's own
  /// value in Taka adds up into one figure.
  double _totalValue(_ProductsData data, String productId) {
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
  List<UnitType> _relevantUnits(_ProductsData data, List<Product> products) {
    return _displayUnits.where((u) => products.any((p) => data.prices[p.id]?.containsKey(u) ?? false)).toList();
  }

  /// One category's products as a table — no Category column since the
  /// section header above it already says which one this is.
  Widget _buildCategoryTable(BuildContext context, _ProductsData data, List<Product> products, bool isTradePricing) {
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
          // A trade-pricing company used to be carton-only, so this layout
          // showed a single "Available" column. Pran now nests carton → jar →
          // piece like Fresh, and those units were invisible here while Total
          // Value counted them — so it shows the same per-unit columns, with
          // the vendor reference figures kept alongside.
          columns: isTradePricing
              ? [
                  const DataColumn(label: Text('Product')),
                  for (final u in units) DataColumn(label: Text(u.label)),
                  for (final u in units) DataColumn(label: Text('Price/${u.label}')),
                  const DataColumn(label: Text('Total Value')),
                  const DataColumn(label: Text('Item Code')),
                  const DataColumn(label: Text('DP')),
                  const DataColumn(label: Text('MRP')),
                  const DataColumn(label: Text('SKU')),
                  const DataColumn(label: Text('Trade')),
                  const DataColumn(label: Text('Damaged')),
                  const DataColumn(label: Text('Status')),
                  const DataColumn(label: Text('')),
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
                  const DataColumn(label: Text('')),
                ],
          rows: [
            for (final product in products)
              DataRow(
                onSelectChanged: (_) => _openProduct(product),
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
                        DataCell(Text(product.skuQty?.toString() ?? '—')),
                        DataCell(Text(product.tradeQty?.toString() ?? '—')),
                        DataCell(Text(
                          _damagedText(data.damaged, product.id),
                          style: TextStyle(color: StatusLevel.serious.color),
                        )),
                        DataCell(Text(
                          product.isActive ? 'Active' : 'Inactive',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: product.isActive ? StatusLevel.good.color : VizChrome.muted,
                          ),
                        )),
                        DataCell(Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.drive_file_move_outlined, size: 18),
                              tooltip: 'Move ${product.name} to another category',
                              onPressed: () => _showMoveCategoryDialog(product, data.categories),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              tooltip: 'Edit ${product.name}',
                              onPressed: () => _openProduct(product),
                            ),
                          ],
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
                          product.isActive ? 'Active' : 'Inactive',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: product.isActive ? StatusLevel.good.color : VizChrome.muted,
                          ),
                        )),
                        DataCell(Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.drive_file_move_outlined, size: 18),
                              tooltip: 'Move ${product.name} to another category',
                              onPressed: () => _showMoveCategoryDialog(product, data.categories),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              tooltip: 'Edit ${product.name}',
                              onPressed: () => _openProduct(product),
                            ),
                          ],
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
    return Scaffold(
      body: Column(
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
                : FutureBuilder<_ProductsData>(
                    future: _future,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return Padding(padding: const EdgeInsets.all(AppSpace.md), child: const SkeletonTable());
                      }
                      if (snapshot.hasError) {
                        return Center(child: Text('Failed to load products: ${snapshot.error}'));
                      }
                      final data = snapshot.data!;
                      if (data.products.isEmpty) {
                        return const Center(child: Text('No products yet. Tap + to add one.'));
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
      floatingActionButton: _future == null
          ? null
          : FutureBuilder<_ProductsData>(
              future: _future,
              builder: (context, snapshot) {
                final categories = snapshot.data?.categories ?? const <Category>[];
                return FloatingActionButton(
                  onPressed: () => _showAddForm(categories, isTradePricing),
                  child: const Icon(Icons.add),
                );
              },
            ),
    );
  }
}


/// The units a carton can be broken into — carton itself is the whole, so it
/// never appears as a "per carton" count.
const _packUnits = [UnitType.box, UnitType.jar, UnitType.poli, UnitType.pcs];

String _plural(UnitType unit) {
  switch (unit) {
    case UnitType.pcs:
      return 'Pieces';
    case UnitType.jar:
      return 'Jars';
    case UnitType.box:
      return 'Boxes';
    case UnitType.poli:
      return 'Poli';
    case UnitType.carton:
      return 'Cartons';
  }
}

/// A labelled break between groups of fields, so a long setup form reads as
/// sections rather than one run of boxes.
class _FormHeading extends StatelessWidget {
  const _FormHeading(this.title, this.caption);

  final String title;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.lg, bottom: AppSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppType.titleS.copyWith(color: Theme.of(context).colorScheme.primary)),
          Text(caption, style: AppType.caption.copyWith(color: VizChrome.secondaryInk)),
        ],
      ),
    );
  }
}
