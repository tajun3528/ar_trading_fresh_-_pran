import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auto_refresh_mixin.dart';
import '../../core/insforge/insforge_exception.dart';
import '../../core/providers.dart';
import '../../core/viz/status_palette.dart';
import '../../models/category.dart';
import '../../models/daily_summary.dart';
import '../../models/product.dart';
import '../../models/profile.dart';
import '../../models/profit.dart';
import '../../models/sales_route.dart';
import '../../models/unit_type.dart';
import '../../core/design/design_tokens.dart';
import '../../core/motion/skeleton.dart';

typedef _Prices = Map<String, Map<UnitType, double>>;
typedef _Stock = Map<String, Map<UnitType, int>>;

/// Largest-to-smallest, matching the app's established column order (see
/// products_screen.dart) so units line up the same way everywhere.
const _displayUnits = [UnitType.carton, UnitType.box, UnitType.poli, UnitType.jar, UnitType.pcs];

class _MemoData {
  _MemoData({
    required this.products,
    required this.categories,
    required this.prices,
    required this.stock,
    required this.atTradePrice,
  });

  final List<Product> products;
  final List<Category> categories;

  /// What each unit will actually be billed at: the salesman's own price for
  /// the delivery month, falling back to the catalog trade price.
  final _Prices prices;
  final _Stock stock;

  /// Keys ("productId|unit") priced at TP because no monthly price was set —
  /// the backend falls back the same way, and these are flagged on screen.
  final Set<String> atTradePrice;
}

/// Composes the salesman's aggregate "what's needed" submission as a single
/// memo: pick a delivery date and route, then enter a quantity directly
/// beside every product in the catalog (grouped by category) — no shop
/// selection; shop-level dealing stays on paper cash memos.
class SubmitSummaryScreen extends ConsumerStatefulWidget {
  const SubmitSummaryScreen({this.existingSummary, this.existingItems, super.key});

  final DailySummary? existingSummary;
  final List<DailySummaryItem>? existingItems;

  bool get isEdit => existingSummary != null;

  @override
  ConsumerState<SubmitSummaryScreen> createState() => _SubmitSummaryScreenState();
}

class _SubmitSummaryScreenState extends ConsumerState<SubmitSummaryScreen>
    with AutoRefreshMixin<SubmitSummaryScreen> {
  late Future<_MemoData> _future;
  final Map<String, TextEditingController> _qtyControllers = {};
  late final TextEditingController _commissionController;
  final _searchController = TextEditingController();
  String _search = '';
  // Lines already on the summary being edited — exempt from the out-of-stock
  // gate so an edit can't quietly delete them.
  final Set<String> _existingLines = {};
  bool _itemsPrefilled = false;
  DateTime? _deliveryDate;
  String? _routeId;
  bool _submitting = false;

  // Only refreshes available products/prices in the background — never
  // touches already-typed quantities, so an in-progress memo is never lost.
  //
  // Deliberately the plain read, not _ensureThenLoad: seeding prices is a
  // write, and a write triggers this very callback, which would seed again.
  @override
  void refreshData() => setState(() { _future = _load(); });

  /// Gives this month's prices a starting value from the catalog wherever the
  /// salesman hasn't set one, so every line on the order carries a real
  /// selling price of theirs rather than a stand-in.
  Future<_MemoData> _ensureThenLoad() async {
    final profile = ref.read(authControllerProvider).valueOrNull;
    if (!widget.isEdit && profile?.role == UserRole.salesman && profile?.companyId != null) {
      try {
        await ref.read(insforgeClientProvider).rpc('ensure_monthly_prices', {
          'p_month': DateFormat('yyyy-MM-01').format(_deliveryDate ?? DateTime.now()),
        });
      } on InsforgeException {
        // Not worth blocking the order over — _load falls back to the
        // catalog price exactly as before.
      }
    }
    return _load();
  }

  /// When the owner books, the order belongs to a salesman they pick: it uses
  /// that salesman's monthly prices and commission, and their company decides
  /// the catalog. A salesman booking their own order never sees this.
  String? _onBehalfOf;
  List<Profile> _salesmen = const [];

  bool get _isOwner => ref.read(authControllerProvider).valueOrNull?.role == UserRole.owner;

  /// The company whose catalog this order draws from.
  String? get _companyId {
    if (widget.isEdit) return widget.existingSummary!.companyId;
    final profile = ref.read(authControllerProvider).valueOrNull;
    if (profile?.role != UserRole.owner) return profile?.companyId;
    return _salesmen.where((p) => p.userId == _onBehalfOf).firstOrNull?.companyId;
  }

  Future<void> _loadSalesmen() async {
    final rows = await ref
        .read(insforgeClientProvider)
        .from('profiles')
        .select()
        .eq('role', 'salesman')
        .eq('status', 'active')
        .order('name')
        .get();
    if (mounted) setState(() { _salesmen = rows.map(Profile.fromJson).toList(); });
  }

  @override
  void initState() {
    super.initState();
    _deliveryDate = widget.isEdit ? widget.existingSummary!.deliveryDate : DateTime.now().add(const Duration(days: 1));
    _routeId = widget.existingSummary?.routeId;
    _commissionController = TextEditingController(
      text: widget.isEdit && widget.existingSummary!.commissionAmount > 0
          ? widget.existingSummary!.commissionAmount.toStringAsFixed(2)
          : '',
    );
    _future = _ensureThenLoad();
    // The owner has to say whose order this is before a catalog can load.
    if (_isOwner && !widget.isEdit) _loadSalesmen();
  }

  @override
  void dispose() {
    for (final c in _qtyControllers.values) {
      c.dispose();
    }
    _commissionController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String _key(String productId, UnitType unit) => '$productId|${unit.name}';

  TextEditingController _controllerFor(String productId, UnitType unit) =>
      _qtyControllers.putIfAbsent(_key(productId, unit), () => TextEditingController());

  Future<_MemoData> _load() async {
    final client = ref.read(insforgeClientProvider);
    final companyId = _companyId;

    if (companyId == null) {
      return _MemoData(
        products: const [],
        categories: const [],
        prices: const {},
        stock: const {},
        atTradePrice: const {},
      );
    }

    final productRows =
        await client.from('products').select().eq('is_active', true).eq('company_id', companyId).order('name').get();
    final categoryRows = await client.from('categories').select().eq('company_id', companyId).order('name').get();
    final products = productRows.map(Product.fromJson).toList();
    final productIds = products.map((p) => p.id).toSet();

    final unitRows = await client.from('product_units').select().get();
    final stockRows = await client.from('stock').select().get();

    // Start from the catalog trade price, then override with whatever the
    // salesman priced for the delivery month — the same fallback order the
    // backend applies when it stores the line.
    final prices = <String, Map<UnitType, double>>{};
    final atTradePrice = <String>{};
    for (final row in unitRows) {
      final unit = ProductUnit.fromJson(row);
      if (!productIds.contains(unit.productId)) continue;
      prices.putIfAbsent(unit.productId, () => {})[unit.unitType] = unit.price;
      atTradePrice.add(_key(unit.productId, unit.unitType));
    }

    final month = _deliveryDate ?? DateTime.now();
    final monthParam = DateFormat('yyyy-MM-01').format(month);
    final myPriceRows = await client.from('salesman_monthly_prices').select().eq('month', monthParam).get();
    for (final row in myPriceRows.map(MonthlySellingPrice.fromJson)) {
      if (!productIds.contains(row.productId)) continue;
      prices.putIfAbsent(row.productId, () => {})[row.unitType] = row.sellingPrice;
      atTradePrice.remove(_key(row.productId, row.unitType));
    }

    final stock = <String, Map<UnitType, int>>{};
    for (final row in stockRows) {
      final productId = row['product_id'] as String;
      if (!productIds.contains(productId)) continue;
      final unit = UnitType.parse(row['unit_type'] as String);
      stock.putIfAbsent(productId, () => {})[unit] = row['available_qty'] as int;
    }

    if (widget.isEdit && !_itemsPrefilled) {
      for (final item in widget.existingItems!) {
        _controllerFor(item.productId, item.unitType).text = item.quantity.toString();
        _existingLines.add(_key(item.productId, item.unitType));
      }
      _itemsPrefilled = true;
    }

    return _MemoData(
      products: products,
      categories: categoryRows.map(Category.fromJson).toList(),
      prices: prices,
      stock: stock,
      atTradePrice: atTradePrice,
    );
  }

  /// A unit can be ordered when the product prices it AND there is stock to
  /// cover it — nothing out of stock can be sold. The one exception is a line
  /// already on the summary being edited: it stays editable even if stock ran
  /// out since, so re-saving never silently drops it.
  List<UnitType> _orderableUnits(_MemoData data, Product product) {
    final priced = data.prices[product.id] ?? const {};
    return _displayUnits
        .where((u) =>
            priced.containsKey(u) &&
            (_effectiveAvailable(data, product, u) > 0 || _existingLines.contains(_key(product.id, u))))
        .toList();
  }

  /// Only the units this category's own products actually price in — e.g.
  /// Snacks never shows empty Box/Jar columns just because some other
  /// category uses them. Mirrors products_screen.dart/stock_screen.dart so
  /// the same category reads the same way everywhere.
  List<UnitType> _relevantUnits(_MemoData data, List<Product> products) {
    return _displayUnits.where((u) => products.any((p) => data.prices[p.id]?.containsKey(u) ?? false)).toList();
  }

  /// How many of a product's units fit in one carton, if that's configured.
  int? _perCarton(Product product, UnitType unit) {
    switch (unit) {
      case UnitType.pcs:
        return product.pcsPerCarton;
      case UnitType.poli:
        return product.poliPerCarton;
      case UnitType.jar:
        return product.jarPerCarton;
      case UnitType.box:
        return product.boxPerCarton;
      case UnitType.carton:
        return null;
    }
  }

  /// How many of this unit could actually be handed over right now.
  ///
  /// Packaging nests: a carton of Chocolate Bar-Box 12.5g (8X24) holds 8
  /// boxes, and each box holds 24 pieces. So a piece can come out of a loose
  /// box as well as out of a carton, and a box can come out of a carton —
  /// counting only the exact unit's own bucket understates what's on the
  /// shelf, which is what made 1 carton plus 4 loose boxes read as 4 boxes
  /// rather than 12.
  int _effectiveAvailable(_MemoData data, Product product, UnitType unit) {
    final byUnit = data.stock[product.id] ?? const <UnitType, int>{};
    final raw = byUnit[unit] ?? 0;
    if (unit == UnitType.carton) return raw;

    final perCarton = _perCarton(product, unit);
    if (perCarton == null || perCarton <= 0) return raw;

    var total = raw + (byUnit[UnitType.carton] ?? 0) * perCarton;

    // Pieces additionally come out of any loose mid-size packs. A box of a
    // (8X24) carton is 192 / 8 = 24 pieces.
    if (unit == UnitType.pcs) {
      for (final mid in const [UnitType.box, UnitType.jar, UnitType.poli]) {
        final midPerCarton = _perCarton(product, mid);
        final looseMid = byUnit[mid] ?? 0;
        if (midPerCarton == null || midPerCarton <= 0 || looseMid <= 0) continue;
        total += looseMid * (perCarton ~/ midPerCarton);
      }
    }
    return total;
  }

  /// How many lines the salesman has actually entered a quantity for that
  /// will be billed at TP rather than their own price.
  int _tpPricedLineCount(_MemoData data) {
    var count = 0;
    for (final product in data.products) {
      for (final unit in _orderableUnits(data, product)) {
        if (!data.atTradePrice.contains(_key(product.id, unit))) continue;
        if ((int.tryParse(_controllerFor(product.id, unit).text) ?? 0) > 0) count++;
      }
    }
    return count;
  }

  double _total(_MemoData data) {
    var total = 0.0;
    for (final product in data.products) {
      for (final unit in _orderableUnits(data, product)) {
        final qty = int.tryParse(_controllerFor(product.id, unit).text) ?? 0;
        if (qty <= 0) continue;
        total += qty * (data.prices[product.id]![unit] ?? 0);
      }
    }
    return total;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: _deliveryDate ?? tomorrow,
      // Past dates are allowed so a day's selling recorded on paper can be
      // entered afterwards, against the day it actually happened.
      firstDate: DateTime(now.year - 1),
      lastDate: tomorrow.add(const Duration(days: 60)),
    );
    if (picked == null) return;
    // Prices are per month, so moving the delivery into a different month
    // changes what the order is worth — reload them.
    final monthChanged =
        _deliveryDate == null || picked.year != _deliveryDate!.year || picked.month != _deliveryDate!.month;
    setState(() {
      _deliveryDate = picked;
      if (monthChanged) _future = _ensureThenLoad();
    });
  }

  Future<void> _submit(_MemoData data) async {
    if (!widget.isEdit) {
      if (_routeId == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a route')));
        return;
      }
      if (_deliveryDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a delivery date')));
        return;
      }
    }

    final lines = <Map<String, dynamic>>[];
    for (final product in data.products) {
      for (final unit in _orderableUnits(data, product)) {
        final qty = int.tryParse(_controllerFor(product.id, unit).text) ?? 0;
        if (qty <= 0) continue;
        lines.add({'product_id': product.id, 'unit_type': unit.name, 'quantity': qty});
      }
    }
    if (lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter at least one quantity')));
      return;
    }

    final commissionText = _commissionController.text.trim();
    final commission = commissionText.isEmpty ? null : double.tryParse(commissionText);
    if (commissionText.isNotEmpty && (commission == null || commission < 0)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter a valid commission amount, or leave it blank')));
      return;
    }

    setState(() => _submitting = true);
    final client = ref.read(insforgeClientProvider);
    try {
      if (widget.isEdit) {
        await client.rpc('edit_daily_summary', {
          'p_summary_id': widget.existingSummary!.id,
          'p_items': lines,
          'p_commission_amount': commission,
        });
      } else {
        await client.rpc('submit_daily_summary', {
          'p_items': lines,
          'p_route_id': _routeId,
          'p_delivery_date': _deliveryDate!.toIso8601String().substring(0, 10),
          'p_commission_amount': commission,
          // Null for a salesman booking their own; the server rejects an
          // owner who has not chosen one.
          'p_salesman_id': _onBehalfOf,
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(widget.isEdit ? 'Summary updated' : 'Summary submitted')));
        if (widget.isEdit) {
          context.pop();
        } else {
          context.go('/salesman/summaries');
        }
      }
    } on InsforgeException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  double _lineTotal(_MemoData data, Product product, List<UnitType> units) {
    var total = 0.0;
    for (final unit in units) {
      final qty = int.tryParse(_controllerFor(product.id, unit).text) ?? 0;
      if (qty <= 0) continue;
      total += qty * (data.prices[product.id]![unit] ?? 0);
    }
    return total;
  }

  /// One unit's cell: a compact quantity box plus a caption showing what's
  /// actually available (including cartons that could be broken open) and
  /// the unit price — same information the Stock page shows, just editable.
  Widget _buildUnitCell(_MemoData data, Product product, UnitType unit) {
    final priced = data.prices[product.id]?[unit];
    if (priced == null) {
      return const Text('—', style: TextStyle(color: VizChrome.muted));
    }
    final available = _effectiveAvailable(data, product, unit);
    if (available <= 0 && !_existingLines.contains(_key(product.id, unit))) {
      return Text(
        'Out of stock',
        style: TextStyle(fontSize: 11, color: Colors.orange.shade800, fontWeight: FontWeight.w600),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 68,
          height: 36,
          child: TextField(
            controller: _controllerFor(product.id, unit),
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: 3),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$available avail · ',
                style: TextStyle(color: available > 0 ? Colors.black45 : Colors.orange.shade800),
              ),
              TextSpan(
                text: '৳${priced.toStringAsFixed(0)}'
                    '${data.atTradePrice.contains(_key(product.id, unit)) ? ' TP' : ''}',
                style: TextStyle(
                  color: data.atTradePrice.contains(_key(product.id, unit))
                      ? Colors.orange.shade800
                      : Colors.black45,
                  fontWeight:
                      data.atTradePrice.contains(_key(product.id, unit)) ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ],
          ),
          style: const TextStyle(fontSize: 10),
        ),
      ],
    );
  }

  /// One category's products as a table, mirroring the Stock page exactly
  /// (same category grouping, same per-unit columns) — only the "Available"
  /// column becomes an editable quantity box here.
  Widget _buildCategoryTable(BuildContext context, _MemoData data, List<Product> products, double minWidth) {
    final units = _relevantUnits(data, products);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        // Forces the table to fill the available page width even when it has
        // few columns (e.g. a single-unit category) instead of shrinking to
        // its own content width and leaving a bare gap beside it — still
        // scrolls horizontally past minWidth for wide, many-unit categories.
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: minWidth),
          child: DataTable(
            showCheckboxColumn: false,
            dataRowMinHeight: 58,
            dataRowMaxHeight: 58,
            headingTextStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: VizChrome.secondaryInk,
            ),
            dataTextStyle: const TextStyle(fontSize: 13),
            columnSpacing: 20,
            columns: [
              const DataColumn(label: Text('Product')),
              for (final u in units) DataColumn(label: Text(u.label)),
              const DataColumn(label: Text('Line total')),
            ],
            rows: [
              for (final product in products)
                () {
                  final orderUnits = _orderableUnits(data, product);
                  final lineTotal = _lineTotal(data, product, orderUnits);
                  return DataRow(
                    color: lineTotal > 0
                        ? WidgetStateProperty.all(Theme.of(context).colorScheme.primary.withValues(alpha: 0.06))
                        : null,
                    cells: [
                      DataCell(Text(product.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                      for (final u in units) DataCell(_buildUnitCell(data, product, u)),
                      DataCell(Text(
                        lineTotal > 0 ? '৳${lineTotal.toStringAsFixed(2)}' : '—',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: lineTotal > 0 ? Theme.of(context).colorScheme.primary : VizChrome.muted,
                        ),
                      )),
                    ],
                  );
                }(),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authControllerProvider).valueOrNull;
    final isOwner = profile?.role == UserRole.owner;
    if (!widget.isEdit && !isOwner && profile?.companyId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('New daily summary')),
        body: const Center(child: Text("You're not assigned to a company yet — ask the Owner to assign one.")),
      );
    }

    final routes = ref.watch(routesProvider).valueOrNull ?? const <SalesRoute>[];
    final activeRoutes = routes.where((r) => r.isActive).toList();

    return Scaffold(
      appBar: AppBar(title: Text(widget.isEdit ? 'Edit summary' : 'New daily summary')),
      body: FutureBuilder<_MemoData>(
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
          final visibleProducts =
              query.isEmpty ? data.products : data.products.where((p) => p.name.toLowerCase().contains(query)).toList();
          final byCategory = <String, List<Product>>{};
          for (final product in visibleProducts) {
            byCategory.putIfAbsent(product.categoryId, () => []).add(product);
          }
          final routeName = widget.isEdit
              ? (routes.where((r) => r.id == widget.existingSummary!.routeId).isEmpty
                  ? 'No route'
                  : routes.firstWhere((r) => r.id == widget.existingSummary!.routeId).name)
              : null;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Shown only to the owner: the salesman this order belongs
                    // to decides its prices, its commission and its catalog.
                    final behalfField = (!isOwner || widget.isEdit)
                        ? null
                        : DropdownButtonFormField<String>(
                            initialValue: _onBehalfOf,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'Booking for',
                              border: const OutlineInputBorder(),
                              helperText: _onBehalfOf == null
                                  ? 'Pick the salesman this order belongs to'
                                  : 'Uses their monthly selling prices and commission',
                            ),
                            items: [
                              for (final sm in _salesmen)
                                DropdownMenuItem(
                                  value: sm.userId,
                                  child: Text(sm.name, overflow: TextOverflow.ellipsis),
                                ),
                            ],
                            onChanged: (id) {
                              setState(() {
                                _onBehalfOf = id;
                                // Quantities typed against the previous
                                // salesman's catalog must not carry over.
                                for (final c in _qtyControllers.values) {
                                  c.clear();
                                }
                              });
                              // A different salesman means a different catalog
                              // and different prices.
                              setState(() { _future = _ensureThenLoad(); });
                            },
                          );

                    final dateField = widget.isEdit
                        ? _ReadOnlyField(
                            label: 'Delivery date',
                            value: DateFormat.yMMMd().format(widget.existingSummary!.deliveryDate),
                          )
                        : OutlinedButton.icon(
                            onPressed: _pickDate,
                            icon: const Icon(Icons.calendar_today, size: 18),
                            label: Text(
                              _deliveryDate == null ? 'Select date' : DateFormat.yMMMd().format(_deliveryDate!),
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                    final routeField = widget.isEdit
                        ? _ReadOnlyField(label: 'Route', value: routeName!)
                        : DropdownButtonFormField<String>(
                            initialValue: _routeId,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'Route', border: OutlineInputBorder()),
                            items: [
                              for (final r in activeRoutes)
                                DropdownMenuItem(
                                  value: r.id,
                                  child: Text(r.name, overflow: TextOverflow.ellipsis),
                                ),
                            ],
                            onChanged: (v) => setState(() => _routeId = v),
                          );
                    // Side by side only when each half still has room for a
                    // full date and a route name — otherwise stack them.
                    // The salesman picker always takes its own full-width row:
                    // it decides the catalog, so it reads first.
                    if (constraints.maxWidth < 480) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (behalfField != null) ...[behalfField, const SizedBox(height: 12)],
                          dateField,
                          const SizedBox(height: 12),
                          routeField,
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (behalfField != null) ...[behalfField, const SizedBox(height: 12)],
                        Row(
                          children: [
                            Expanded(child: dateField),
                            const SizedBox(width: 12),
                            Expanded(child: routeField),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: TextField(
                  controller: _commissionController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Your commission (optional)',
                    prefixText: '৳ ',
                    border: OutlineInputBorder(),
                    helperText: 'Deducted from the order total — what you remit to the Owner is the rest.',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              if (data.products.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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
                    ? const Center(child: Text('No products available to order.'))
                    : visibleProducts.isEmpty
                        ? Center(child: Text('No products match "${_search.trim()}".'))
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              // Only the categories that actually have matching
                              // products, resolved once per build rather than
                              // inside the item builder.
                              final sections = [
                                for (final category in data.categories)
                                  if (byCategory[category.id] case final products?) (category, products),
                              ];
                              // ListView.builder, not ListView(children:) —
                              // typing a quantity rebuilds this list, and a
                              // non-lazy list would rebuild every category's
                              // table and every quantity box in the catalog on
                              // each keystroke. Lazily, only what is on screen
                              // is rebuilt.
                              return ListView.builder(
                                padding: const EdgeInsets.all(12),
                                itemCount: sections.length,
                                itemBuilder: (context, i) {
                                  final (category, products) = sections[i];
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                                        child: Text(category.name,
                                            style: Theme.of(context).textTheme.titleMedium),
                                      ),
                                      _buildCategoryTable(
                                          context, data, products, constraints.maxWidth - 24),
                                      const SizedBox(height: 12),
                                    ],
                                  );
                                },
                              );
                            },
                          ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                // Wrap so a long total and the submit button take separate
                // lines on a phone rather than overflowing side by side.
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    Builder(builder: (context) {
                      final total = _total(data);
                      final commission = double.tryParse(_commissionController.text.trim()) ?? 0;
                      final tpLines = _tpPricedLineCount(data);
                      final warning = tpLines == 0
                          ? null
                          : Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '$tpLines line${tpLines == 1 ? '' : 's'} priced at TP — no selling price set '
                                'for ${DateFormat.yMMMM().format(_deliveryDate ?? DateTime.now())}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.orange.shade800,
                                ),
                              ),
                            );
                      if (commission <= 0) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Total: ৳${total.toStringAsFixed(2)}',
                                style: Theme.of(context).textTheme.titleMedium),
                            ?warning,
                          ],
                        );
                      }
                      final net = total - commission;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Commission: −৳${commission.toStringAsFixed(2)}'),
                          Text('Order total: ৳${total.toStringAsFixed(2)}'),
                          Text('Net to Owner: ৳${net.toStringAsFixed(2)}',
                              style: Theme.of(context).textTheme.titleMedium),
                          ?warning,
                        ],
                      );
                    }),
                    FilledButton(
                      onPressed: _submitting ? null : () => _submit(data),
                      child: _submitting
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(widget.isEdit ? 'Save changes' : 'Submit summary'),
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

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      child: Text(value),
    );
  }
}
