import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auto_refresh_mixin.dart';
import '../../core/insforge/insforge_exception.dart';
import '../../core/providers.dart';
import '../../models/product.dart';
import '../../models/unit_type.dart';
import '../../core/viz/status_palette.dart';
import '../../core/design/design_tokens.dart';
import '../../core/motion/skeleton.dart';

class _QuickItem {
  _QuickItem({
    required this.product,
    required this.unitType,
    required this.price,
    required this.stockAvailable,
    required this.timesOrdered,
    required this.suggestedQty,
  });

  final Product product;
  final UnitType unitType;
  final double price;
  final int stockAvailable;
  final int timesOrdered;
  final int suggestedQty;
}

/// Fast reorder flow: the salesman's own most-frequently-ordered products,
/// each with a pre-filled quantity field (their historical average) instead
/// of the full catalog's browse-and-add-one-at-a-time dialog.
class QuickOrderScreen extends ConsumerStatefulWidget {
  const QuickOrderScreen({super.key});

  @override
  ConsumerState<QuickOrderScreen> createState() => _QuickOrderScreenState();
}

class _QuickOrderScreenState extends ConsumerState<QuickOrderScreen> with AutoRefreshMixin<QuickOrderScreen> {
  late Future<List<_QuickItem>> _future;
  final Map<String, TextEditingController> _controllers = {};
  bool _submitting = false;

  @override
  void refreshData() => setState(() { _future = _load(); });

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  String _key(String productId, UnitType unit) => '$productId|${unit.name}';

  Future<List<_QuickItem>> _load() async {
    final client = ref.read(insforgeClientProvider);

    // RLS already scopes daily_summary_items to what this salesman can see
    // (their own), so no explicit salesman filter is needed here.
    final historyRows = await client.from('daily_summary_items').select('product_id,unit_type,quantity').get();
    final frequency = <String, int>{};
    final totalQty = <String, int>{};
    for (final row in historyRows) {
      final key = '${row['product_id']}|${row['unit_type']}';
      frequency[key] = (frequency[key] ?? 0) + 1;
      totalQty[key] = (totalQty[key] ?? 0) + (row['quantity'] as int);
    }

    final topKeys = frequency.keys.toList()..sort((a, b) => frequency[b]!.compareTo(frequency[a]!));
    final top = topKeys.take(8).toList();
    if (top.isEmpty) return [];

    final productRows = await client.from('products').select().eq('is_active', true).get();
    final productsById = {for (final p in productRows.map(Product.fromJson)) p.id: p};
    final unitRows = await client.from('product_units').select().get();
    final prices = <String, Map<UnitType, double>>{};
    for (final row in unitRows) {
      final unit = ProductUnit.fromJson(row);
      prices.putIfAbsent(unit.productId, () => {})[unit.unitType] = unit.price;
    }
    final stockRows = await client.from('stock').select().get();
    final stock = <String, Map<UnitType, int>>{};
    for (final row in stockRows) {
      final productId = row['product_id'] as String;
      final unit = UnitType.parse(row['unit_type'] as String);
      stock.putIfAbsent(productId, () => {})[unit] = row['available_qty'] as int;
    }

    final items = <_QuickItem>[];
    for (final key in top) {
      final parts = key.split('|');
      final productId = parts[0];
      final unit = UnitType.parse(parts[1]);
      final product = productsById[productId];
      if (product == null) continue;
      final price = prices[productId]?[unit];
      final available = stock[productId]?[unit] ?? 0;
      if (price == null || available <= 0) continue; // no longer orderable

      items.add(_QuickItem(
        product: product,
        unitType: unit,
        price: price,
        stockAvailable: available,
        timesOrdered: frequency[key]!,
        suggestedQty: (totalQty[key]! / frequency[key]!).round().clamp(1, available),
      ));

      final controllerKey = _key(productId, unit);
      _controllers.putIfAbsent(
        controllerKey,
        () => TextEditingController(text: items.last.suggestedQty.toString()),
      );
    }

    return items;
  }

  Future<void> _submit(List<_QuickItem> items) async {
    final lines = <Map<String, dynamic>>[];
    for (final item in items) {
      final qty = int.tryParse(_controllers[_key(item.product.id, item.unitType)]!.text) ?? 0;
      if (qty <= 0) continue;
      lines.add({'product_id': item.product.id, 'unit_type': item.unitType.name, 'quantity': qty});
    }
    if (lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter at least one quantity')));
      return;
    }

    setState(() => _submitting = true);
    final client = ref.read(insforgeClientProvider);
    try {
      await client.rpc('submit_daily_summary', {'p_items': lines});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order submitted')));
        context.go('/salesman/summaries');
      }
    } on InsforgeException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(authControllerProvider).valueOrNull?.companyId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Quick order')),
        body: const Center(child: Text("You're not assigned to a company yet — ask the Owner to assign one.")),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Quick order')),
      body: FutureBuilder<List<_QuickItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Padding(padding: const EdgeInsets.all(AppSpace.md), child: const SkeletonTable());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Failed to load: ${snapshot.error}'));
          }
          final items = snapshot.data!;
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'No order history yet — quick order learns from what you\'ve ordered before.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => context.go('/salesman/new-summary/full'),
                      child: const Text('Use full catalog order instead'),
                    ),
                  ],
                ),
              ),
            );
          }

          final total = items.fold<double>(0, (sum, item) {
            final qty = int.tryParse(_controllers[_key(item.product.id, item.unitType)]?.text ?? '0') ?? 0;
            return sum + qty * item.price;
          });

          return Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Your most-ordered products — quantities are pre-filled with your usual amount.'),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: items.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final controller = _controllers[_key(item.product.id, item.unitType)]!;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.product.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                Text(
                                  '${item.unitType.label} • ৳${item.price.toStringAsFixed(2)} each • '
                                  '${item.stockAvailable} in stock • ordered ${item.timesOrdered}x before',
                                  style: const TextStyle(fontSize: 11, color: VizChrome.muted),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 80,
                            child: TextField(
                              controller: controller,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              decoration: const InputDecoration(labelText: 'Qty'),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
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
                    Text('Total: ৳${total.toStringAsFixed(2)}', style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    FilledButton(
                      onPressed: _submitting ? null : () => _submit(items),
                      child: _submitting
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Submit order'),
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
