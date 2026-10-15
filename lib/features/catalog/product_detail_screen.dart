import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auto_refresh_mixin.dart';
import '../../core/insforge/insforge_exception.dart';
import '../../core/providers.dart';
import '../../models/category.dart';
import '../../models/company.dart';
import '../../models/product.dart';
import '../../models/stock.dart';
import '../../models/unit_type.dart';
import '../../core/design/design_tokens.dart';
import '../../core/motion/skeleton.dart';

class ProductDetailScreen extends ConsumerStatefulWidget {
  const ProductDetailScreen({required this.product, super.key});

  final Product product;

  @override
  ConsumerState<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen>
    with AutoRefreshMixin<ProductDetailScreen> {
  late Product _product;

  @override
  void refreshData() => _reload();
  final Map<UnitType, TextEditingController> _priceControllers = {
    for (final unit in UnitType.values) unit: TextEditingController(),
  };
  late final TextEditingController _pcsPerCartonController;
  late final TextEditingController _poliPerCartonController;
  late final TextEditingController _jarPerCartonController;
  late final TextEditingController _boxPerCartonController;
  String? _categoryName;
  List<Category> _companyCategories = const [];
  List<Stock> _stock = const [];
  late Future<void> _future;

  @override
  void initState() {
    super.initState();
    _product = widget.product;
    _pcsPerCartonController = TextEditingController(text: _product.pcsPerCarton?.toString() ?? '');
    _poliPerCartonController = TextEditingController(text: _product.poliPerCarton?.toString() ?? '');
    _jarPerCartonController = TextEditingController(text: _product.jarPerCarton?.toString() ?? '');
    _boxPerCartonController = TextEditingController(text: _product.boxPerCarton?.toString() ?? '');
    _future = _load();
  }

  @override
  void dispose() {
    for (final c in _priceControllers.values) {
      c.dispose();
    }
    _pcsPerCartonController.dispose();
    _poliPerCartonController.dispose();
    _jarPerCartonController.dispose();
    _boxPerCartonController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final client = ref.read(insforgeClientProvider);

    // Re-fetch the product itself too — not just its related rows — so any
    // edit made via _showEditDetailsDialog (name, category, reference data)
    // is reflected here immediately instead of showing stale widget.product.
    _product = Product.fromJson(await client.from('products').select().eq('id', _product.id).single());

    final category =
        await client.from('categories').select('name').eq('id', _product.categoryId).maybeSingle();
    _categoryName = category?['name'] as String?;

    final categoryRows =
        await client.from('categories').select().eq('company_id', _product.companyId).order('name').get();
    _companyCategories = categoryRows.map(Category.fromJson).toList();

    final unitRows = await client.from('product_units').select().eq('product_id', _product.id).get();
    for (final unit in unitRows.map(ProductUnit.fromJson)) {
      _priceControllers[unit.unitType]!.text = unit.price.toStringAsFixed(2);
    }

    final stockRows = await client.from('stock').select().eq('product_id', _product.id).get();
    _stock = stockRows.map(Stock.fromJson).toList();
  }

  void _reload() => setState(() { _future = _load(); });

  /// Shared by the pcs and poli "per carton" rollup fields below — same
  /// validation, same save/apply shape, just a different column and
  /// Product field.
  Future<void> _saveRollupField({
    required String column,
    required TextEditingController controller,
    required Product Function(int? value) applyLocal,
  }) async {
    final text = controller.text.trim();
    final value = text.isEmpty ? null : int.tryParse(text);
    if (text.isNotEmpty && (value == null || value <= 0)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter a positive whole number, or leave blank')));
      return;
    }
    final client = ref.read(insforgeClientProvider);
    try {
      await client.from('products').eq('id', _product.id).update({column: value});
      setState(() {
        _product = applyLocal(value);
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
    } on InsforgeException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _savePcsPerCarton() => _saveRollupField(
        column: 'pcs_per_carton',
        controller: _pcsPerCartonController,
        applyLocal: (v) => _product.copyWith(pcsPerCarton: v),
      );

  Future<void> _savePoliPerCarton() => _saveRollupField(
        column: 'poli_per_carton',
        controller: _poliPerCartonController,
        applyLocal: (v) => _product.copyWith(poliPerCarton: v),
      );

  Future<void> _saveJarPerCarton() => _saveRollupField(
        column: 'jar_per_carton',
        controller: _jarPerCartonController,
        applyLocal: (v) => _product.copyWith(jarPerCarton: v),
      );

  Future<void> _saveBoxPerCarton() => _saveRollupField(
        column: 'box_per_carton',
        controller: _boxPerCartonController,
        applyLocal: (v) => _product.copyWith(boxPerCarton: v),
      );

  Future<void> _savePrices() async {
    final client = ref.read(insforgeClientProvider);
    try {
      for (final unit in UnitType.values) {
        final text = _priceControllers[unit]!.text.trim();
        if (text.isEmpty) continue;
        final price = double.tryParse(text);
        if (price == null || price < 0) continue;

        final existing = await client
            .from('product_units')
            .select('id')
            .eq('product_id', _product.id)
            .eq('unit_type', unit.name)
            .maybeSingle();
        if (existing == null) {
          await client.from('product_units').insert([
            {'product_id': _product.id, 'unit_type': unit.name, 'price': price}
          ]);
        } else {
          await client.from('product_units').eq('id', existing['id'] as String).update({'price': price});
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Prices saved')));
      }
    } on InsforgeException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _toggleActive() async {
    final client = ref.read(insforgeClientProvider);
    try {
      await client.from('products').eq('id', _product.id).update({'is_active': !_product.isActive});
      setState(() {
        _product = _product.copyWith(isActive: !_product.isActive);
      });
    } on InsforgeException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  static int? _parseInt(String text) => text.trim().isEmpty ? null : int.tryParse(text.trim());
  static double? _parseDouble(String text) => text.trim().isEmpty ? null : double.tryParse(text.trim());
  static String? _parseText(String text) => text.trim().isEmpty ? null : text.trim();

  /// Corrects any mistake found while cross-checking the vendor sheet —
  /// name included — in one place, rather than needing a direct DB fix.
  Future<void> _showEditDetailsDialog() async {
    final nameController = TextEditingController(text: _product.name);
    final descriptionController = TextEditingController(text: _product.description ?? '');
    final thresholdController = TextEditingController(text: _product.lowStockThreshold.toString());
    String categoryId = _product.categoryId;

    final itemCodeController = TextEditingController(text: _product.itemCode ?? '');
    final factorController = TextEditingController(text: _product.factor?.toString() ?? '');
    final dpController = TextEditingController(text: _product.dpPrice?.toString() ?? '');
    final dpPerPcsController = TextEditingController(text: _product.perPcsDpPrice?.toString() ?? '');
    final tpController = TextEditingController(text: _product.tpPrice?.toString() ?? '');
    final mrpController = TextEditingController(text: _product.mrpPrice?.toString() ?? '');
    final mrpPerPcsController = TextEditingController(text: _product.mrpPricePerPcs?.toString() ?? '');
    final skuQtyController = TextEditingController(text: _product.skuQty?.toString() ?? '');
    final tradeQtyController = TextEditingController(text: _product.tradeQty?.toString() ?? '');
    final tradeNoteController = TextEditingController(text: _product.tradeNote ?? '');
    final soNoteController = TextEditingController(text: _product.soNote ?? '');
    final jarBoxSizeController = TextEditingController(text: _product.jarBoxSize?.toString() ?? '');
    final afterTradeDpController = TextEditingController(text: _product.afterTradeDpPrice?.toString() ?? '');
    final afterTradeTpController = TextEditingController(text: _product.afterTradeTpPrice?.toString() ?? '');
    final perPcsTpController = TextEditingController(text: _product.perPcsTpPrice?.toString() ?? '');
    final ermController = TextEditingController(text: _product.ermPercent?.toString() ?? '');

    // AlertDialog reserves 40px of inset each side, so that's the widest the
    // content can be before it overflows a phone screen.
    final dialogWidth = math.min(480.0, MediaQuery.of(context).size.width - 80);
    // Below this, side-by-side number fields lose their labels to ellipsis —
    // stack each pair instead.
    final stackFields = dialogWidth < 380;
    Widget fieldPair(Widget first, Widget second) => stackFields
        ? Column(children: [first, const SizedBox(height: 12), second])
        : Row(
            children: [
              Expanded(child: first),
              const SizedBox(width: 12),
              Expanded(child: second),
            ],
          );

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit product details'),
          content: SizedBox(
            width: dialogWidth,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Name')),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(labelText: 'Description (optional)'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: categoryId,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: [
                      for (final c in _companyCategories) DropdownMenuItem(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: (v) => setDialogState(() => categoryId = v ?? categoryId),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: thresholdController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Low-stock threshold'),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 20, bottom: 4),
                    child: Text('Vendor reference data (optional)', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  TextField(controller: itemCodeController, decoration: const InputDecoration(labelText: 'Item code')),
                  const SizedBox(height: 12),
                  TextField(
                    controller: factorController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Factor'),
                  ),
                  const SizedBox(height: 12),
                  fieldPair(
                    TextField(
                      controller: dpController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'DP'),
                    ),
                    TextField(
                      controller: dpPerPcsController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'DP (per piece)'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: tpController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'TP (reference)'),
                  ),
                  const SizedBox(height: 12),
                  fieldPair(
                    TextField(
                      controller: mrpController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'MRP'),
                    ),
                    TextField(
                      controller: mrpPerPcsController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'MRP (per piece)'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  fieldPair(
                    TextField(
                      controller: skuQtyController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'SKU'),
                    ),
                    TextField(
                      controller: jarBoxSizeController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Jar/Box size'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: tradeQtyController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Trade qty'),
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: tradeNoteController, decoration: const InputDecoration(labelText: 'Trade note')),
                  const SizedBox(height: 12),
                  TextField(
                      controller: soNoteController, decoration: const InputDecoration(labelText: 'Standing order')),
                  const SizedBox(height: 12),
                  TextField(
                    controller: afterTradeDpController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'After trade DP'),
                  ),
                  const SizedBox(height: 12),
                  fieldPair(
                    TextField(
                      controller: afterTradeTpController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Effective price (after trade)'),
                    ),
                    TextField(
                      controller: perPcsTpController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Effective price (per piece)'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ermController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Effective margin %'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (saved != true) return;
    final name = nameController.text.trim();
    if (name.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name is required')));
      return;
    }

    final client = ref.read(insforgeClientProvider);
    try {
      await client.from('products').eq('id', _product.id).update({
        'name': name,
        'description': _parseText(descriptionController.text),
        'category_id': categoryId,
        'low_stock_threshold': _parseInt(thresholdController.text) ?? 0,
        'item_code': _parseText(itemCodeController.text),
        'factor': _parseInt(factorController.text),
        'dp_price': _parseDouble(dpController.text),
        'per_pcs_dp_price': _parseDouble(dpPerPcsController.text),
        'tp_price': _parseDouble(tpController.text),
        'mrp_price': _parseDouble(mrpController.text),
        'mrp_price_per_pcs': _parseDouble(mrpPerPcsController.text),
        'sku_qty': _parseInt(skuQtyController.text),
        'trade_qty': _parseInt(tradeQtyController.text),
        'trade_note': _parseText(tradeNoteController.text),
        'so_note': _parseText(soNoteController.text),
        'jar_box_size': _parseInt(jarBoxSizeController.text),
        'after_trade_dp_price': _parseDouble(afterTradeDpController.text),
        'after_trade_tp_price': _parseDouble(afterTradeTpController.text),
        'per_pcs_tp_price': _parseDouble(perPcsTpController.text),
        'erm_percent': _parseDouble(ermController.text),
      });
      _reload();
    } on InsforgeException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// One dialog, one save — a delivery usually arrives as some mix of
  /// cartons, jars, and loose pieces all at once, so stocking each in
  /// separately used to take three trips through this dialog. Only offers
  /// the units this product actually sells in (isTradePricing's single-pack
  /// products just get one field, same as the price editor below).
  Future<void> _showStockInDialog(List<UnitType> units) async {
    final quantityControllers = <UnitType, TextEditingController>{
      for (final u in units) u: TextEditingController(),
    };

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add stock'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final u in units)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: quantityControllers[u],
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: '${u.label} quantity'),
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

    final entries = <(UnitType, int)>[
      for (final u in units)
        if (int.tryParse(quantityControllers[u]!.text) case final qty? when qty > 0) (u, qty),
    ];
    if (entries.isEmpty) return;

    final client = ref.read(insforgeClientProvider);
    try {
      for (final (unit, quantity) in entries) {
        await client.rpc('stock_in', {
          'p_product_id': _product.id,
          'p_unit_type': unit.name,
          'p_quantity': quantity,
        });
      }
      _reload();
    } on InsforgeException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Fixes a mistaken quantity directly — stock_in() only ever adds, so a
  /// typo'd stock-in (or any other wrong number) had no way back before this.
  /// Sets the exact correct available/damaged counts rather than adding a
  /// delta; every correction shows up on the Audit Log like any other change.
  Future<void> _showCorrectStockDialog(Stock current) async {
    final availableController = TextEditingController(text: current.availableQty.toString());
    final damagedController = TextEditingController(text: current.damagedQty.toString());

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Correct ${current.unitType.label.toLowerCase()} stock'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: availableController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Available'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: damagedController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Damaged'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );

    final available = int.tryParse(availableController.text);
    final damaged = int.tryParse(damagedController.text);
    if (saved != true || available == null || available < 0 || damaged == null || damaged < 0) return;

    final client = ref.read(insforgeClientProvider);
    try {
      await client.rpc('correct_stock', {
        'p_product_id': _product.id,
        'p_unit_type': current.unitType.name,
        'p_available_qty': available,
        'p_damaged_qty': damaged,
      });
      _reload();
    } on InsforgeException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final companies = ref.watch(companiesProvider).valueOrNull ?? const <Company>[];
    final company = Company.findById(companies, _product.companyId);
    final isTradePricing = company?.catalogStyle == CompanyCatalogStyle.tradePricing;
    // Every unit, for both catalogs. This used to be carton-only for a
    // trade-pricing company, from when that catalog really was one flat pack
    // per product — but Pran now nests carton -> jar -> piece exactly like
    // Fresh, and the lock meant a new Pran product could only ever be given a
    // carton price, so it could only ever be ordered by the carton.
    final priceUnits = UnitType.values;

    return Scaffold(
      appBar: AppBar(
        title: Text(_product.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit product details',
            onPressed: _showEditDetailsDialog,
          ),
          TextButton(
            onPressed: _toggleActive,
            child: Text(_product.isActive ? 'Deactivate' : 'Activate',
                style: TextStyle(color: Theme.of(context).colorScheme.onPrimary)),
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Padding(padding: const EdgeInsets.all(AppSpace.md), child: const SkeletonTable());
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                title: Text(_categoryName ?? '-'),
                leading: const Icon(Icons.category),
              ),
              const Divider(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Current stock', style: Theme.of(context).textTheme.titleMedium),
                  OutlinedButton.icon(
                    onPressed: () => _showStockInDialog(priceUnits),
                    icon: const Icon(Icons.add),
                    label: const Text('Add stock'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_stock.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No stock recorded yet.'),
                )
              else
                for (final s in _stock)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(isTradePricing && s.unitType == UnitType.carton ? 'Pack' : s.unitType.label),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${s.availableQty} available'
                              '${s.damagedQty > 0 ? ' • ${s.damagedQty} damaged' : ''}',
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              tooltip: 'Correct ${s.unitType.label.toLowerCase()} stock',
                              onPressed: () => _showCorrectStockDialog(s),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              if (_product.hasVendorReferenceData) ...[
                const Divider(height: 32),
                _VendorPriceListCard(product: _product),
              ],
              ...[
                const Divider(height: 32),
                Text('Packaging', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Optional. If set, stocking in or ordering enough loose pieces (or poli) '
                  'automatically rolls full cartons into the carton count, leaving the '
                  'remainder in its original unit. Leave blank if this product has no '
                  'fixed carton size.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _pcsPerCartonController,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Pieces per carton', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(onPressed: _savePcsPerCarton, child: const Text('Save')),
                  ],
                ),
                ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _poliPerCartonController,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Poli per carton', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(onPressed: _savePoliPerCarton, child: const Text('Save')),
                    ],
                  ),
                ],
                // Jar and box don't roll up into cartons, but their count per
                // carton is the only way to work out what one costs — without
                // it, sales in these units show no profit.
                ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _jarPerCartonController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Jars per carton',
                            helperText: 'Used to work out the DP cost of one jar.',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(onPressed: _saveJarPerCarton, child: const Text('Save')),
                    ],
                  ),
                ],
                ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _boxPerCartonController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Boxes per carton',
                            helperText: 'Used to work out the DP cost of one box.',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(onPressed: _saveBoxPerCarton, child: const Text('Save')),
                    ],
                  ),
                ],
              ],
              const Divider(height: 32),
              Text(isTradePricing ? 'Selling price (BDT)' : 'Unit prices (BDT)',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                isTradePricing
                    ? 'This is the trade price (TP) actually charged on orders — the vendor '
                        'reference figures above are informational only.'
                    : 'Pieces, jars, and cartons are sold and stocked independently — '
                        'set a price for whichever units this product is actually sold in.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              for (final unit in priceUnits)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: _priceControllers[unit],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: isTradePricing ? 'Pack price (TP)' : '${unit.label} price',
                      prefixText: '৳ ',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              FilledButton(onPressed: _savePrices, child: const Text('Save prices')),
            ],
          );
        },
      ),
    );
  }
}

/// Read-only snapshot of the vendor's own price sheet (Item Code, Factor,
/// DP/MRP, SKU/Trade/Jar-Box quantities, After-Trade and Per-pcs figures) —
/// reference only; the editable selling price lives in the section below.
class _VendorPriceListCard extends StatelessWidget {
  const _VendorPriceListCard({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      if (product.itemCode != null) ('Item code', product.itemCode!),
      if (product.factor != null) ('Factor', '${product.factor}'),
      if (product.dpPrice != null) ('DP', '৳${product.dpPrice!.toStringAsFixed(2)}'),
      if (product.perPcsDpPrice != null) ('DP (per piece)', '৳${product.perPcsDpPrice!.toStringAsFixed(2)}'),
      if (product.mrpPrice != null) ('MRP', '৳${product.mrpPrice!.toStringAsFixed(2)}'),
      if (product.mrpPricePerPcs != null) ('MRP (per piece)', '৳${product.mrpPricePerPcs!.toStringAsFixed(2)}'),
      if (product.skuQty != null) ('SKU', '${product.skuQty}'),
      if (product.tradeQty != null) ('Trade', '${product.tradeQty}'),
      if (product.tradeNote != null) ('Trade note', product.tradeNote!),
      if (product.soNote != null) ('Standing order', product.soNote!),
      if (product.jarBoxSize != null) ('Jar/Box size', '${product.jarBoxSize}'),
      if (product.afterTradeDpPrice != null) ('After trade DP', '৳${product.afterTradeDpPrice!.toStringAsFixed(2)}'),
      if (product.afterTradeTpPrice != null)
        ('Effective price (after trade)', '৳${product.afterTradeTpPrice!.toStringAsFixed(2)}'),
      if (product.perPcsTpPrice != null)
        ('Effective price (per piece)', '৳${product.perPcsTpPrice!.toStringAsFixed(2)}'),
      if (product.ermPercent != null) ('Effective margin', '${product.ermPercent!.toStringAsFixed(0)}%'),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Vendor price list (reference)', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              "Snapshot from the vendor's own price sheet — not used in order pricing.",
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              const Text('No vendor pricing data on file for this product.')
            else
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [Text(r.$1), Text(r.$2, style: const TextStyle(fontWeight: FontWeight.w600))],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
