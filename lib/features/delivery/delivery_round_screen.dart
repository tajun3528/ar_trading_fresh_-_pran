import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auto_refresh_mixin.dart';
import '../../core/insforge/insforge_exception.dart';
import '../../core/providers.dart';
import '../../core/viz/status_palette.dart';
import '../../models/category.dart';
import '../../models/daily_summary.dart';
import '../../models/delivery.dart';
import '../../models/product.dart';
import '../../models/profit.dart';
import '../../models/unit_type.dart';
import '../summaries/summary_status_chip.dart';
import '../../core/design/design_tokens.dart';
import '../../core/motion/skeleton.dart';

final _money = NumberFormat('#,##0.00');

/// Largest-to-smallest, the order units appear in everywhere else.
const _displayUnits = [UnitType.carton, UnitType.box, UnitType.poli, UnitType.jar, UnitType.pcs];

/// Damaged or expired stock collected back from shops on this round.
class _DamageRow {
  _DamageRow({
    required this.productName,
    required this.unitType,
    required this.quantity,
    required this.lineTotal,
  });

  final String productName;
  final UnitType unitType;
  final int quantity;
  final double lineTotal;
}

class _RoundData {
  _RoundData({
    required this.summary,
    required this.items,
    required this.productNames,
    required this.productCategories,
    required this.categories,
    required this.delivery,
    required this.deliveryItems,
    required this.damages,
    required this.catalog,
    required this.catalogPrices,
  });

  final DailySummary summary;
  final List<DailySummaryItem> items;
  final Map<String, String> productNames;
  final Map<String, String> productCategories;
  final List<Category> categories;

  final Delivery? delivery;
  final List<DeliveryItem> deliveryItems;
  final List<_DamageRow> damages;

  /// Every active product of the order's company — damaged and expired goods
  /// come back from shops off any of them, not just what is in today's van.
  final List<Product> catalog;

  /// What each unit refunds at: the salesman's own monthly price where set,
  /// otherwise the catalog trade price. Keyed "productId|unit".
  final Map<String, double> catalogPrices;

  /// What is on the order but not yet on the van — because a salesman added
  /// to it after loading, or because only part of it fitted the first time.
  List<({DailySummaryItem item, int missing})> get notYetLoaded {
    final out = <({DailySummaryItem item, int missing})>[];
    for (final item in items) {
      final onVan = lineForSummaryItem(item.id)?.loadedQuantity ?? 0;
      if (item.quantity > onVan) out.add((item: item, missing: item.quantity - onVan));
    }
    return out;
  }

  /// The round's line for a given order line, if it is on the van at all.
  DeliveryItem? lineForSummaryItem(String summaryItemId) {
    for (final line in deliveryItems) {
      if (line.summaryItemId == summaryItemId) return line;
    }
    return null;
  }

  DailySummaryItem? summaryItemFor(DeliveryItem line) {
    for (final item in items) {
      if (item.id == line.summaryItemId) return item;
    }
    return null;
  }

  /// The round's own lines, one entry per product with its units beside it.
  Map<String, Map<UnitType, DeliveryItem>> get linesByProduct {
    final map = <String, Map<UnitType, DeliveryItem>>{};
    for (final line in deliveryItems) {
      if (line.loadedQuantity <= 0) continue;
      final item = summaryItemFor(line);
      if (item == null) continue;
      map.putIfAbsent(item.productId, () => {})[item.unitType] = line;
    }
    return map;
  }
}

/// The deliveryman's round: load the van, then account for what came back —
/// unsold goods off this order, and damaged or expired stock collected from
/// shops off anywhere in the catalog.
class DeliveryRoundScreen extends ConsumerStatefulWidget {
  const DeliveryRoundScreen({required this.summaryId, super.key});

  final String summaryId;

  @override
  ConsumerState<DeliveryRoundScreen> createState() => _DeliveryRoundScreenState();
}

class _DeliveryRoundScreenState extends ConsumerState<DeliveryRoundScreen>
    with AutoRefreshMixin<DeliveryRoundScreen>, SingleTickerProviderStateMixin {
  late Future<_RoundData> _future;
  TabController? _tabs;

  /// Stage 1 — which summary items are ticked as aboard the van.
  final Set<String> _loaded = {};
  bool _loadedPrefilled = false;

  /// Stage 2 — unsold goods, keyed by delivery item id.
  final Map<String, TextEditingController> _returnedControllers = {};

  /// Stage 2 — collected damage, keyed "productId|unit" across the catalog.
  final Map<String, TextEditingController> _damageControllers = {};

  final _searchController = TextEditingController();
  String _search = '';

  /// The tab currently on screen, so the controller's per-frame notifications
  /// can be told apart from a real tab change.
  int _shownTab = 0;
  bool _redoing = false;
  bool _submitting = false;

  @override
  void refreshData() => setState(() { _future = _load(); });

  @override
  void initState() {
    super.initState();
    final tabs = TabController(length: 2, vsync: this);
    _tabs = tabs;
    // A TabController notifies on every frame of its slide, and rebuilding
    // this screen is expensive — so react only once the index has actually
    // settled on a different tab. The Returns and Damage tabs share one
    // search box, so the new tab still has to re-filter when it arrives.
    tabs.addListener(() {
      if (tabs.indexIsChanging || tabs.index == _shownTab) return;
      _shownTab = tabs.index;
      setState(() => _search = _searchController.text);
    });
    _future = _load();
  }

  @override
  void dispose() {
    for (final c in _returnedControllers.values) {
      c.dispose();
    }
    for (final c in _damageControllers.values) {
      c.dispose();
    }
    _searchController.dispose();
    _tabs?.dispose();
    super.dispose();
  }

  String _key(String productId, UnitType unit) => '$productId|${unit.name}';

  TextEditingController _damageControllerFor(String productId, UnitType unit) =>
      _damageControllers.putIfAbsent(_key(productId, unit), () => TextEditingController());

  Future<_RoundData> _load() async {
    final client = ref.read(insforgeClientProvider);
    final summary =
        DailySummary.fromJson(await client.from('daily_summaries').select().eq('id', widget.summaryId).single());
    final itemRows = await client.from('daily_summary_items').select().eq('summary_id', widget.summaryId).get();
    final items = itemRows.map(DailySummaryItem.fromJson).toList();

    final productRows =
        await client.from('products').select().eq('company_id', summary.companyId).eq('is_active', true).get();
    final catalog = productRows.map(Product.fromJson).toList();
    final productNames = {for (final p in productRows) p['id'] as String: p['name'] as String};
    final productCategories = {for (final p in productRows) p['id'] as String: p['category_id'] as String};
    final categoryRows = await client.from('categories').select().order('name').get();
    final categories = categoryRows.map(Category.fromJson).toList();

    // Trade price first, then whatever the salesman priced for the delivery
    // month — the same order the backend uses to value a refund.
    final catalogPrices = <String, double>{};
    final unitRows = await client.from('product_units').select().get();
    for (final row in unitRows) {
      final unit = ProductUnit.fromJson(row);
      catalogPrices[_key(unit.productId, unit.unitType)] = unit.price;
    }
    final monthParam = DateFormat('yyyy-MM-01').format(summary.deliveryDate);
    final priceRows = await client
        .from('salesman_monthly_prices')
        .select()
        .eq('salesman_id', summary.salesmanId)
        .eq('month', monthParam)
        .get();
    for (final row in priceRows.map(MonthlySellingPrice.fromJson)) {
      catalogPrices[_key(row.productId, row.unitType)] = row.sellingPrice;
    }

    final deliveryRows = await client
        .from('deliveries')
        .select()
        .eq('summary_id', widget.summaryId)
        .order('delivery_datetime', ascending: false)
        .limit(1)
        .get();
    final delivery = deliveryRows.isEmpty ? null : Delivery.fromJson(deliveryRows.first);

    var deliveryItems = <DeliveryItem>[];
    var damages = <_DamageRow>[];
    if (delivery != null) {
      final lineRows = await client.from('delivery_items').select().eq('delivery_id', delivery.id).get();
      deliveryItems = lineRows.map(DeliveryItem.fromJson).toList();
      for (final line in deliveryItems) {
        _returnedControllers.putIfAbsent(line.id, () => TextEditingController(text: '0'));
      }

      final damageRows = await client.from('delivery_damages').select().eq('delivery_id', delivery.id).get();
      damages = [
        for (final row in damageRows)
          _DamageRow(
            productName: productNames[row['product_id'] as String] ?? 'Product',
            unitType: UnitType.parse(row['unit_type'] as String),
            quantity: row['quantity'] as int,
            lineTotal: (row['line_total'] as num).toDouble(),
          ),
      ]..sort((a, b) => a.productName.compareTo(b.productName));
    }

    // Everything ticked by default — the common case is a full van, and it's
    // quicker to untick the one thing missing than to tick thirty.
    if (!_loadedPrefilled && delivery == null) {
      _loaded.addAll(items.map((i) => i.id));
      _loadedPrefilled = true;
    }

    return _RoundData(
      summary: summary,
      items: items,
      productNames: productNames,
      productCategories: productCategories,
      categories: categories,
      delivery: delivery,
      deliveryItems: deliveryItems,
      damages: damages,
      catalog: catalog,
      catalogPrices: catalogPrices,
    );
  }

  // ------------------------------------------------------------------ maths
  int _returnedQty(DeliveryItem line) => int.tryParse(_returnedControllers[line.id]?.text ?? '0') ?? 0;

  int _deliveredQty(DeliveryItem line) =>
      (line.loadedQuantity - _returnedQty(line)).clamp(0, line.loadedQuantity);

  bool _lineOverflows(DeliveryItem line) => _returnedQty(line) > line.loadedQuantity;

  double _deliveredValue(_RoundData data) {
    var total = 0.0;
    for (final line in data.deliveryItems) {
      final item = data.summaryItemFor(line);
      if (item == null) continue;
      total += _deliveredQty(line) * item.unitPrice;
    }
    return total;
  }

  double _damagedValue(_RoundData data) {
    var total = 0.0;
    for (final entry in _damageControllers.entries) {
      final qty = int.tryParse(entry.value.text) ?? 0;
      if (qty <= 0) continue;
      total += qty * (data.catalogPrices[entry.key] ?? 0);
    }
    return total;
  }

  int _damagedUnits() {
    var count = 0;
    for (final controller in _damageControllers.values) {
      if ((int.tryParse(controller.text) ?? 0) > 0) count++;
    }
    return count;
  }

  // ------------------------------------------------------------------ writes
  Future<void> _loadVan(_RoundData data) async {
    if (_loaded.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Tick at least one product as loaded')));
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref.read(insforgeClientProvider).rpc('load_delivery_van', {
        'p_summary_id': widget.summaryId,
        'p_items': [
          for (final item in data.items)
            {
              'summary_item_id': item.id,
              'loaded_quantity': _loaded.contains(item.id) ? item.quantity : 0,
            },
        ],
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Now record returns and any damage collected')));
        setState(() {
          _redoing = false;
          _future = _load();
        });
      }
    } on InsforgeException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// A second (or third) trip to the warehouse for the same order. Tops up
  /// what is on the van without closing the round, so one big order still
  /// settles as one round with one cash figure at the end.
  Future<void> _showLoadMoreDialog(_RoundData data) async {
    final controllers = <String, TextEditingController>{};
    for (final item in data.items) {
      controllers[item.id] = TextEditingController();
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Load more into the van'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enter how much you are adding now. You can carry more than the '
                  'order if you want spare stock for the shops.',
                  style: AppType.bodyS.copyWith(color: VizChrome.secondaryInk),
                ),
                const SizedBox(height: AppSpace.md),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: data.items.length,
                    separatorBuilder: (_, _) => const Divider(height: 12),
                    itemBuilder: (context, i) {
                      final item = data.items[i];
                      final line = data.lineForSummaryItem(item.id);
                      final onVan = line?.loadedQuantity ?? 0;
                      return Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  data.productNames[item.productId] ?? 'Product',
                                  style: AppType.label,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${item.quantity} ${item.unitType.label.toLowerCase()} ordered · '
                                  '$onVan already on the van',
                                  style: AppType.caption.copyWith(color: VizChrome.secondaryInk),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpace.sm),
                          SizedBox(
                            width: 74,
                            child: TextField(
                              controller: controllers[item.id],
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              decoration: const InputDecoration(
                                hintText: 'Add',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Load')),
          ],
        ),
      ),
    );

    final additions = <Map<String, dynamic>>[];
    for (final entry in controllers.entries) {
      final n = int.tryParse(entry.value.text.trim()) ?? 0;
      if (n > 0) additions.add({'summary_item_id': entry.key, 'add_quantity': n});
    }
    for (final c in controllers.values) {
      c.dispose();
    }
    if (confirmed != true || !mounted) return;

    if (additions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a quantity for at least one product')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref.read(insforgeClientProvider).rpc('load_more_into_van', {
        'p_delivery_id': data.delivery!.id,
        'p_items': additions,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Loaded more onto the van (${additions.length} product(s))')),
      );
      refreshData();
    } on InsforgeException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Adds a product to the order mid-round, at the salesman's own selling
  /// price, and puts it on the van as loaded. The owner sees it on the
  /// approval screen and is notified that the order changed.
  Future<void> _showAddProductDialog(_RoundData data) async {
    Product? product;
    UnitType? unit;
    final qtyController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          final units = product == null
              ? const <UnitType>[]
              : [
                  for (final u in UnitType.values)
                    if (data.catalogPrices.containsKey('${product!.id}|${u.name}')) u,
                ];
          final price = (product != null && unit != null)
              ? data.catalogPrices['${product!.id}|${unit!.name}']
              : null;

          return AlertDialog(
            title: const Text('Add a product to this round'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<Product>(
                    initialValue: product,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Product', border: OutlineInputBorder()),
                    items: [
                      for (final p in data.catalog)
                        DropdownMenuItem(value: p, child: Text(p.name, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (p) => setLocal(() {
                      product = p;
                      unit = null;
                    }),
                  ),
                  const SizedBox(height: AppSpace.md),
                  DropdownButtonFormField<UnitType>(
                    initialValue: unit,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Unit', border: OutlineInputBorder()),
                    items: [for (final u in units) DropdownMenuItem(value: u, child: Text(u.label))],
                    onChanged: units.isEmpty ? null : (u) => setLocal(() => unit = u),
                  ),
                  const SizedBox(height: AppSpace.md),
                  TextField(
                    controller: qtyController,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Quantity', border: OutlineInputBorder()),
                    onChanged: (_) => setLocal(() {}),
                  ),
                  if (price != null) ...[
                    const SizedBox(height: AppSpace.md),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Sells at ৳${price.toStringAsFixed(2)} per ${unit!.label.toLowerCase()}'
                        '${_addLineTotal(qtyController.text, price)}',
                        style: AppType.bodyS.copyWith(color: VizChrome.secondaryInk),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
            ],
          );
        },
      ),
    );

    final qty = int.tryParse(qtyController.text.trim());
    qtyController.dispose();
    if (confirmed != true || !mounted) return;

    if (product == null || unit == null || qty == null || qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a product and unit, and enter a quantity')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref.read(insforgeClientProvider).rpc('add_delivery_line', {
        'p_delivery_id': data.delivery!.id,
        'p_product_id': product!.id,
        'p_unit_type': unit!.name,
        'p_quantity': qty,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added $qty ${unit!.label.toLowerCase()} of ${product!.name}')),
      );
      refreshData();
    } on InsforgeException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// The running line total shown under the price as the quantity is typed.
  static String _addLineTotal(String raw, double price) {
    final qty = int.tryParse(raw.trim());
    if (qty == null || qty <= 0) return '';
    return ' · ৳${(qty * price).toStringAsFixed(2)} total';
  }

  Future<void> _closeRound(_RoundData data) async {
    if (data.deliveryItems.any(_lineOverflows)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A return is more than what went into the van')),
      );
      return;
    }

    final payment = _deliveredValue(data) - data.summary.commissionAmount - _damagedValue(data);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finish this round?'),
        content: Text(
          'You will hand over ৳${_money.format(payment)} to the owner.\n\n'
          'The report then goes to the owner for approval.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not yet')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Finish round')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _submitting = true);
    try {
      await ref.read(insforgeClientProvider).rpc('close_delivery_round', {
        'p_delivery_id': data.delivery!.id,
        'p_items': [
          for (final line in data.deliveryItems)
            {'delivery_item_id': line.id, 'returned_quantity': _returnedQty(line)},
        ],
        'p_damages': [
          for (final entry in _damageControllers.entries)
            if ((int.tryParse(entry.value.text) ?? 0) > 0)
              {
                'product_id': entry.key.split('|')[0],
                'unit_type': entry.key.split('|')[1],
                'quantity': int.parse(entry.value.text),
              },
        ],
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Round closed — waiting on owner approval')));
        setState(() { _future = _load(); });
      }
    } on InsforgeException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ------------------------------------------------------------------ pieces
  Widget _banner(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _searchField(String hint) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: hint,
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
    );
  }

  Widget _qtyBox(TextEditingController controller, {Color? tint}) {
    return SizedBox(
      width: 62,
      height: 34,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          border: const OutlineInputBorder(),
          filled: tint != null,
          fillColor: tint,
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  /// One card table per category, in catalog order, with anything whose
  /// category didn't come back gathered at the end.
  Widget _categoryTables(
    BuildContext context,
    _RoundData data,
    List<String> productIds,
    List<DataColumn> Function(List<UnitType> units) columns,
    List<DataCell> Function(String productId, List<UnitType> units) cells,
  ) {
    final query = _search.trim().toLowerCase();
    final visible = productIds
        .where((id) => query.isEmpty || (data.productNames[id] ?? '').toLowerCase().contains(query))
        .toList()
      ..sort((a, b) => (data.productNames[a] ?? '').compareTo(data.productNames[b] ?? ''));

    if (visible.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(query.isEmpty ? 'Nothing to show.' : 'No products match "${_search.trim()}".'),
        ),
      );
    }

    final grouped = <String, List<String>>{};
    for (final id in visible) {
      grouped.putIfAbsent(data.productCategories[id] ?? '', () => []).add(id);
    }
    final ordered = <({String title, List<String> ids})>[];
    final known = <String>{};
    for (final category in data.categories) {
      known.add(category.id);
      if (grouped[category.id] case final ids?) ordered.add((title: category.name, ids: ids));
    }
    final orphans = [
      for (final entry in grouped.entries)
        if (!known.contains(entry.key)) ...entry.value,
    ];
    if (orphans.isNotEmpty) ordered.add((title: 'Other products', ids: orphans));

    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final section in ordered) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
              child: Text(section.title, style: Theme.of(context).textTheme.titleMedium),
            ),
            Builder(builder: (context) {
              // Only the units this section's products actually use, so a
              // category never shows an empty column.
              final units = _displayUnits
                  .where((u) => section.ids.any((id) => data.catalogPrices.containsKey(_key(id, u))))
                  .toList();
              return Card(
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth - 24),
                    child: DataTable(
                      showCheckboxColumn: false,
                      dataRowMinHeight: 48,
                      dataRowMaxHeight: 48,
                                headingTextStyle: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: VizChrome.secondaryInk,
                      ),
                      dataTextStyle: const TextStyle(fontSize: 13),
                      columnSpacing: 16,
                      columns: columns(units),
                      rows: [
                        for (final id in section.ids) DataRow(cells: cells(id, units)),
                      ],
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- stage 1
  Widget _buildLoadStage(_RoundData data) {
    final allTicked = _loaded.length == data.items.length;
    final today = DateTime.now();
    final isPast = !data.summary.deliveryDate.isAfter(DateTime(today.year, today.month, today.day));

    // One row per product, its units beside each other.
    final byProduct = <String, Map<UnitType, DailySummaryItem>>{};
    for (final item in data.items) {
      byProduct.putIfAbsent(item.productId, () => {})[item.unitType] = item;
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: _banner(
            isPast
                ? 'This delivery day has passed. Tick what actually went out, then '
                    'record returns and collected damage on the next step.'
                : 'Tick every product as you put it in the van. Anything left unticked '
                    "won't go out and can't be delivered.",
            VizChrome.info,
            isPast ? Icons.history : Icons.local_shipping,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Row(
            children: [
              Text('${_loaded.length} of ${data.items.length} lines loaded',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() {
                  if (allTicked) {
                    _loaded.clear();
                  } else {
                    _loaded.addAll(data.items.map((i) => i.id));
                  }
                }),
                child: Text(allTicked ? 'Untick all' : 'Tick all'),
              ),
            ],
          ),
        ),
        _searchField('Search products'),
        const Divider(height: 1),
        Expanded(
          child: _categoryTables(
            context,
            data,
            byProduct.keys.toList(),
            (units) => [
              const DataColumn(label: Text('Product')),
              for (final u in units) DataColumn(label: Text(u.label)),
            ],
            (productId, units) => [
              DataCell(Text(data.productNames[productId] ?? 'Product',
                  style: const TextStyle(fontWeight: FontWeight.w600))),
              for (final u in units)
                DataCell(
                  byProduct[productId]?[u] == null
                      ? const Text('—', style: TextStyle(color: VizChrome.muted))
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: _loaded.contains(byProduct[productId]![u]!.id),
                              onChanged: (v) => setState(() {
                                if (v == true) {
                                  _loaded.add(byProduct[productId]![u]!.id);
                                } else {
                                  _loaded.remove(byProduct[productId]![u]!.id);
                                }
                              }),
                            ),
                            Text('${byProduct[productId]![u]!.quantity}',
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _submitting ? null : () => _loadVan(data),
              icon: Icon(isPast ? Icons.arrow_forward : Icons.local_shipping),
              label: _submitting
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(isPast ? 'Next: returns & damage' : 'Van is loaded — start round'),
            ),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------- stage 2: returns
  Widget _buildReturnsTab(_RoundData data) {
    final byProduct = data.linesByProduct;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _banner(
            'Only what went out in the van can come back unsold. Enter the '
            'quantity per unit; the rest counts as delivered.',
            VizChrome.info,
            Icons.assignment_return,
          ),
        ),
        _searchField('Search products in the van'),
        const Divider(height: 1),
        Expanded(
          child: _categoryTables(
            context,
            data,
            byProduct.keys.toList(),
            (units) => [
              const DataColumn(label: Text('Product')),
              for (final u in units) DataColumn(label: Text('${u.label} out')),
              for (final u in units) DataColumn(label: Text('${u.label} back')),
            ],
            (productId, units) => [
              DataCell(Text(data.productNames[productId] ?? 'Product',
                  style: const TextStyle(fontWeight: FontWeight.w600))),
              for (final u in units)
                DataCell(Text(
                  byProduct[productId]?[u] == null ? '—' : '${byProduct[productId]![u]!.loadedQuantity}',
                  style: const TextStyle(color: VizChrome.secondaryInk),
                )),
              for (final u in units)
                DataCell(
                  byProduct[productId]?[u] == null
                      ? const Text('—', style: TextStyle(color: VizChrome.muted))
                      : _qtyBox(
                          _returnedControllers[byProduct[productId]![u]!.id]!,
                          tint: _lineOverflows(byProduct[productId]![u]!)
                              ? StatusLevel.critical.color.withValues(alpha: 0.12)
                              : null,
                        ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------- stage 2: damage
  Widget _buildDamageTab(_RoundData data) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _banner(
            'Damaged or date-expired stock collected from shops — any product '
            "in the catalog, not just today's van. Its value comes off the cash "
            'you hand over.',
            StatusLevel.serious.color,
            Icons.report_problem,
          ),
        ),
        _searchField('Search the whole catalog'),
        const Divider(height: 1),
        Expanded(
          child: _categoryTables(
            context,
            data,
            data.catalog.map((p) => p.id).toList(),
            (units) => [
              const DataColumn(label: Text('Product')),
              for (final u in units) DataColumn(label: Text(u.label)),
            ],
            (productId, units) => [
              DataCell(Text(data.productNames[productId] ?? 'Product',
                  style: const TextStyle(fontWeight: FontWeight.w600))),
              for (final u in units)
                DataCell(
                  !data.catalogPrices.containsKey(_key(productId, u))
                      ? const Text('—', style: TextStyle(color: VizChrome.muted))
                      : _qtyBox(_damageControllerFor(productId, u)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _paymentLine(String label, double value, {bool negative = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Text(
            '${negative ? '−' : ''}৳${_money.format(value.abs())}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: negative ? StatusLevel.serious.color : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReturnStage(_RoundData data) {
    final deliveredValue = _deliveredValue(data);
    final damagedValue = _damagedValue(data);
    final commission = data.summary.commissionAmount;
    final payment = deliveredValue - commission - damagedValue;
    final damagedUnits = _damagedUnits();

    return Column(
      children: [
        if (data.notYetLoaded.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(AppSpace.md),
              decoration: BoxDecoration(
                color: StatusLevel.warning.color.withValues(alpha: 0.10),
                borderRadius: AppRadius.rMd,
                border: Border.all(color: StatusLevel.warning.color.withValues(alpha: 0.40)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.inventory_2_outlined, size: 18, color: StatusLevel.warning.color),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${data.notYetLoaded.length} product(s) are on the order but not on your van',
                          style: AppType.label,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          data.notYetLoaded
                              .take(3)
                              .map((e) =>
                                  '${e.missing} ${e.item.unitType.label.toLowerCase()} '
                                  '${data.productNames[e.item.productId] ?? ''}'.trim())
                              .join(' · '),
                          style: AppType.caption.copyWith(color: VizChrome.secondaryInk),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        // A shop often wants more than was booked. Without this the round can
        // only ever record less than the order — delivered, returned,
        // damaged — so an extra sale had to happen on paper.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Another load, or something extra sold?',
                  style: AppType.bodyS.copyWith(color: VizChrome.secondaryInk),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _submitting ? null : () => _showLoadMoreDialog(data),
                icon: const Icon(Icons.local_shipping_outlined, size: 17),
                label: const Text('Load more'),
              ),
              const SizedBox(width: AppSpace.sm),
              FilledButton.tonalIcon(
                onPressed: _submitting ? null : () => _showAddProductDialog(data),
                icon: const Icon(Icons.add, size: 17),
                label: const Text('Add product'),
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabs,
          tabs: [
            const Tab(text: 'Returns'),
            Tab(text: damagedUnits > 0 ? 'Damage ($damagedUnits)' : 'Damage'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [_buildReturnsTab(data), _buildDamageTab(data)],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _paymentLine('Delivered goods', deliveredValue),
              if (commission > 0) _paymentLine("Salesman's commission", commission, negative: true),
              if (damagedValue > 0) _paymentLine('Damage collected back', damagedValue, negative: true),
              const Divider(height: 16),
              Row(
                children: [
                  const Expanded(
                    child: Text('Hand over to owner', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                  Text(
                    '৳${_money.format(payment)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      color: payment >= 0 ? StatusLevel.good.color : StatusLevel.critical.color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submitting ? null : () => _closeRound(data),
                  child: _submitting
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Finish round'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- stage 3
  Widget _buildClosedStage(_RoundData data) {
    final delivery = data.delivery!;
    final rejected = delivery.approvalStatus == DeliveryApprovalStatus.rejected;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (rejected) ...[
          _banner(
            'The owner rejected this report'
            '${delivery.rejectionReason != null ? ': ${delivery.rejectionReason}' : '.'} '
            'File a corrected one below.',
            StatusLevel.critical.color,
            Icons.error_outline,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => setState(() {
                _redoing = true;
                _loaded
                  ..clear()
                  ..addAll(data.items.map((i) => i.id));
              }),
              icon: const Icon(Icons.refresh),
              label: const Text('Start this round again'),
            ),
          ),
        ] else if (delivery.approvalStatus == DeliveryApprovalStatus.approved)
          _banner('Round approved by the owner.', StatusLevel.good.color, Icons.check_circle)
        else
          _banner('Round finished — waiting for the owner to approve it.', VizChrome.info, Icons.schedule),
        const SizedBox(height: 16),
        if (delivery.paymentAmount case final payment?)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Expanded(child: Text('Cash handed over', style: TextStyle(fontWeight: FontWeight.w700))),
                  Text('৳${_money.format(payment)}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        // Three separate tables rather than one wide one: with five possible
        // units, interleaving out/back/sold ran to fifteen quantity columns
        // and nothing could be read across.
        Text('Product out', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _buildRoundTable(context, data, (line) => line.loadedQuantity),
        const SizedBox(height: 16),
        Text('Product back', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _buildRoundTable(context, data, (line) => line.returnedQuantity, hideEmptyRows: true),
        const SizedBox(height: 16),
        Text('Product sold', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _buildRoundTable(context, data, (line) => line.deliveredQuantity, showValue: true),
        if (data.damages.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Damaged / expired collected from shops', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _buildDamageSummaryTable(context, data),
        ],
      ],
    );
  }

  /// One of the round's three views — out, back or sold — as a table with one
  /// row per product and its units beside each other, the way the stock page
  /// reads. [quantityOf] picks which figure the table shows.
  Widget _buildRoundTable(
    BuildContext context,
    _RoundData data,
    int Function(DeliveryItem line) quantityOf, {
    bool showValue = false,
    bool hideEmptyRows = false,
  }) {
    final byProduct = <String, Map<UnitType, DeliveryItem>>{};
    for (final line in data.deliveryItems) {
      if (line.loadedQuantity <= 0) continue;
      final item = data.summaryItemFor(line);
      if (item == null) continue;
      byProduct.putIfAbsent(item.productId, () => {})[item.unitType] = line;
    }

    // The "back" table is usually mostly zeroes — listing every product would
    // bury the handful that actually came back.
    if (hideEmptyRows) {
      byProduct.removeWhere((_, byUnit) => byUnit.values.every((line) => quantityOf(line) <= 0));
    }

    if (byProduct.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(hideEmptyRows ? 'Nothing came back on this round.' : 'Nothing went out on this round.'),
          ),
        ),
      );
    }

    final productIds = byProduct.keys.toList()
      ..sort((a, b) => (data.productNames[a] ?? '').compareTo(data.productNames[b] ?? ''));
    final units = _displayUnits.where((u) => byProduct.values.any((m) => m.containsKey(u))).toList();

    double valueFor(String productId) {
      var total = 0.0;
      for (final entry in byProduct[productId]!.entries) {
        final item = data.summaryItemFor(entry.value);
        if (item != null) total += quantityOf(entry.value) * item.unitPrice;
      }
      return total;
    }

    return LayoutBuilder(
      builder: (context, constraints) => Card(
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
                headingTextStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: VizChrome.secondaryInk,
              ),
              dataTextStyle: const TextStyle(fontSize: 13),
              columnSpacing: 16,
              columns: [
                const DataColumn(label: Text('Product')),
                for (final u in units) DataColumn(label: Text(u.label)),
                if (showValue) const DataColumn(label: Text('Value')),
              ],
              rows: [
                for (final id in productIds)
                  DataRow(
                    cells: [
                      DataCell(Text(data.productNames[id] ?? 'Product',
                          style: const TextStyle(fontWeight: FontWeight.w600))),
                      for (final u in units)
                        DataCell(Builder(builder: (context) {
                          final line = byProduct[id]?[u];
                          if (line == null) {
                            return const Text('—', style: TextStyle(color: VizChrome.muted));
                          }
                          final qty = quantityOf(line);
                          if (qty <= 0) {
                            return const Text('—', style: TextStyle(color: VizChrome.muted));
                          }
                          return Text(
                            '$qty',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: showValue ? StatusLevel.good.color : null,
                            ),
                          );
                        })),
                      if (showValue)
                        DataCell(Text(
                          '৳${_money.format(valueFor(id))}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        )),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDamageSummaryTable(BuildContext context, _RoundData data) {
    final byProduct = <String, Map<UnitType, _DamageRow>>{};
    for (final damage in data.damages) {
      byProduct.putIfAbsent(damage.productName, () => {})[damage.unitType] = damage;
    }
    final names = byProduct.keys.toList()..sort();
    final units = _displayUnits.where((u) => byProduct.values.any((m) => m.containsKey(u))).toList();

    return LayoutBuilder(
      builder: (context, constraints) => Card(
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
                headingTextStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: VizChrome.secondaryInk,
              ),
              dataTextStyle: const TextStyle(fontSize: 13),
              columnSpacing: 16,
              columns: [
                const DataColumn(label: Text('Product')),
                for (final u in units) DataColumn(label: Text(u.label)),
                const DataColumn(label: Text('Refunded')),
              ],
              rows: [
                for (final name in names)
                  DataRow(
                    cells: [
                      DataCell(Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
                      for (final u in units)
                        DataCell(Text(
                          byProduct[name]?[u] == null ? '—' : '${byProduct[name]![u]!.quantity}',
                          style: TextStyle(
                            fontWeight: byProduct[name]?[u] == null ? FontWeight.w400 : FontWeight.w700,
                            color: byProduct[name]?[u] == null ? null : StatusLevel.serious.color,
                          ),
                        )),
                      DataCell(Text(
                        '−৳${_money.format(byProduct[name]!.values.fold<double>(0, (s, d) => s + d.lineTotal))}',
                        style: TextStyle(fontWeight: FontWeight.w700, color: StatusLevel.serious.color),
                      )),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delivery round')),
      body: FutureBuilder<_RoundData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Padding(padding: const EdgeInsets.all(AppSpace.md), child: const SkeletonTable());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Failed to load: ${snapshot.error}'));
          }
          final data = snapshot.data!;
          final delivery = data.delivery;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('৳${_money.format(data.summary.totalAmount)}',
                              style: Theme.of(context).textTheme.titleLarge),
                          Text(
                            'Delivery ${DateFormat.yMMMd().format(data.summary.deliveryDate)}',
                            style: const TextStyle(fontSize: 12, color: VizChrome.secondaryInk),
                          ),
                        ],
                      ),
                    ),
                    SummaryStatusChip(status: data.summary.status),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: delivery == null || _redoing
                    ? _buildLoadStage(data)
                    : delivery.isOutForDelivery
                        ? _buildReturnStage(data)
                        : _buildClosedStage(data),
              ),
            ],
          );
        },
      ),
    );
  }
}
