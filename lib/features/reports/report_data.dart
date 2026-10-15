import '../../core/insforge/insforge_client.dart';
import '../../models/daily_summary.dart';
import '../../models/product.dart';
import '../../models/stock.dart';
import '../../models/unit_type.dart';

class _ProductUnitKey {
  _ProductUnitKey(this.productId, this.unitType);
  final String productId;
  final UnitType unitType;

  @override
  bool operator ==(Object other) =>
      other is _ProductUnitKey && other.productId == productId && other.unitType == unitType;

  @override
  int get hashCode => Object.hash(productId, unitType);
}

/// Aggregates daily_summaries + daily_summary_items data for a date range
/// into product/salesman breakdowns (FR-10.3), plus a stock-movement view
/// (FR-10.4). No shop/route breakdown — those aren't tracked digitally.
class ReportData {
  ReportData({
    required this.byProduct,
    required this.bySalesman,
    required this.stockMovement,
    required this.totalRevenue,
  });

  static Future<ReportData> load(InsforgeClient client, DateTime from, DateTime to, {String? companyId}) async {
    String fmt(DateTime d) => d.toIso8601String().substring(0, 10);

    var query = client
        .from('daily_summaries')
        .select()
        .gte('submission_date', fmt(from))
        .lte('submission_date', fmt(to))
        .inList('status', ['delivered', 'partially_delivered']);
    if (companyId != null) query = query.eq('company_id', companyId);
    final summaryRows = await query.get();
    final summaries = summaryRows.map(DailySummary.fromJson).toList();
    final summariesById = {for (final s in summaries) s.id: s};
    if (summaries.isEmpty) {
      return ReportData(
        byProduct: const [],
        bySalesman: const [],
        stockMovement: await _loadStockMovement(client, from, to, companyId: companyId),
        totalRevenue: 0,
      );
    }

    final itemRows = await client
        .from('daily_summary_items')
        .select()
        .inList('summary_id', summaries.map((s) => s.id).toList())
        .get();

    final profileRows = await client.from('profiles').select('user_id,name').get();
    final salesmanNames = {for (final p in profileRows) p['user_id'] as String: p['name'] as String};
    final productRows = await client.from('products').select('id,name').get();
    final productNames = {for (final p in productRows) p['id'] as String: p['name'] as String};

    final byProduct = <String, ReportRow>{};
    final bySalesman = <String, ReportRow>{};
    double totalRevenue = 0;

    for (final row in itemRows) {
      final summaryId = row['summary_id'] as String;
      final summary = summariesById[summaryId];
      if (summary == null) continue;
      final lineTotal = (row['line_total'] as num).toDouble();
      final quantity = row['quantity'] as int;
      totalRevenue += lineTotal;

      final productId = row['product_id'] as String;
      byProduct.putIfAbsent(productId, () => ReportRow(productNames[productId] ?? 'Product'))
        ..quantity += quantity
        ..revenue += lineTotal;

      bySalesman.putIfAbsent(summary.salesmanId, () => ReportRow(salesmanNames[summary.salesmanId] ?? 'Salesman'))
        ..quantity += quantity
        ..revenue += lineTotal;
    }

    int byRevenueDesc(ReportRow a, ReportRow b) => b.revenue.compareTo(a.revenue);

    return ReportData(
      byProduct: byProduct.values.toList()..sort(byRevenueDesc),
      bySalesman: bySalesman.values.toList()..sort(byRevenueDesc),
      stockMovement: await _loadStockMovement(client, from, to, companyId: companyId),
      totalRevenue: totalRevenue,
    );
  }

  /// Pieces, jars, and cartons are independent stock, so movement is grouped
  /// per (product, unit) rather than converted into a single common count.
  static Future<List<StockMovementRow>> _loadStockMovement(
    InsforgeClient client,
    DateTime from,
    DateTime to, {
    String? companyId,
  }) async {
    String fmt(DateTime d) => d.toIso8601String().substring(0, 10);

    var productsQuery = client.from('products').select();
    if (companyId != null) productsQuery = productsQuery.eq('company_id', companyId);
    final products = (await productsQuery.get()).map(Product.fromJson).toList();
    final productsById = {for (final p in products) p.id: p};
    final productIds = productsById.keys.toSet();

    // stock/stock_ins/returns aren't company-scoped columns themselves — RLS
    // (and this in-memory filter, for an Owner viewing one company) scope
    // them via a join on product_id instead (see the company-scoping
    // migration), so filter these unfiltered fetches down to this report's
    // own product ids.
    final stockRows = (await client.from('stock').select().get())
        .map(Stock.fromJson)
        .where((s) => productIds.contains(s.productId));
    final stockByKey = {for (final s in stockRows) _ProductUnitKey(s.productId, s.unitType): s};

    final stockInRows =
        await client.from('stock_ins').select().gte('entry_date', fmt(from)).lte('entry_date', fmt(to)).get();
    final stockInByKey = <_ProductUnitKey, int>{};
    for (final row in stockInRows) {
      final productId = row['product_id'] as String;
      if (!productIds.contains(productId)) continue;
      final key = _ProductUnitKey(productId, UnitType.parse(row['unit_type'] as String));
      stockInByKey[key] = (stockInByKey[key] ?? 0) + (row['quantity'] as int);
    }

    // Returns and damage both come off delivery rounds now — the standalone
    // returns table is no longer written to. Only approved rounds count: an
    // unapproved one hasn't moved stock or settled any money yet.
    final goodByKey = <_ProductUnitKey, int>{};
    final damagedByKey = <_ProductUnitKey, int>{};

    final approvedDeliveryRows = await client
        .from('deliveries')
        .select('id,summary_id')
        .eq('approval_status', 'approved')
        .get();
    final approvedIds = approvedDeliveryRows.map((d) => d['id'] as String).toList();

    if (approvedIds.isNotEmpty) {
      final summaryIds = approvedDeliveryRows.map((d) => d['summary_id'] as String).toSet().toList();
      final datedSummaries = await client
          .from('daily_summaries')
          .select('id,delivery_date')
          .inList('id', summaryIds)
          .gte('delivery_date', fmt(from))
          .lte('delivery_date', fmt(to))
          .get();
      final inRangeSummaryIds = datedSummaries.map((s) => s['id'] as String).toSet();
      final inRangeDeliveryIds = [
        for (final d in approvedDeliveryRows)
          if (inRangeSummaryIds.contains(d['summary_id'] as String)) d['id'] as String,
      ];

      if (inRangeDeliveryIds.isNotEmpty) {
        // Unsold goods that came back in the van.
        final lineRows = await client
            .from('delivery_items')
            .select('summary_item_id,returned_quantity')
            .inList('delivery_id', inRangeDeliveryIds)
            .get();
        final summaryItemIds = lineRows.map((r) => r['summary_item_id'] as String).toSet().toList();
        final summaryItemRows = summaryItemIds.isEmpty
            ? <Map<String, dynamic>>[]
            : await client
                .from('daily_summary_items')
                .select('id,product_id,unit_type')
                .inList('id', summaryItemIds)
                .get();
        final itemById = {for (final row in summaryItemRows) row['id'] as String: row};

        for (final row in lineRows) {
          final qty = (row['returned_quantity'] as int?) ?? 0;
          if (qty <= 0) continue;
          final item = itemById[row['summary_item_id'] as String];
          if (item == null) continue;
          final productId = item['product_id'] as String;
          if (!productIds.contains(productId)) continue;
          final key = _ProductUnitKey(productId, UnitType.parse(item['unit_type'] as String));
          goodByKey[key] = (goodByKey[key] ?? 0) + qty;
        }

        // Damaged and expired stock collected back from shops.
        final damageRows = await client
            .from('delivery_damages')
            .select('product_id,unit_type,quantity')
            .inList('delivery_id', inRangeDeliveryIds)
            .get();
        for (final row in damageRows) {
          final productId = row['product_id'] as String;
          if (!productIds.contains(productId)) continue;
          final key = _ProductUnitKey(productId, UnitType.parse(row['unit_type'] as String));
          damagedByKey[key] = (damagedByKey[key] ?? 0) + (row['quantity'] as int);
        }
      }
    }

    final allKeys = {...stockByKey.keys, ...stockInByKey.keys, ...goodByKey.keys, ...damagedByKey.keys};

    return [
      for (final key in allKeys)
        if (productsById[key.productId] != null)
          StockMovementRow(
            productName: productsById[key.productId]!.name,
            unitType: key.unitType,
            stockIn: stockInByKey[key] ?? 0,
            returnedGood: goodByKey[key] ?? 0,
            damaged: damagedByKey[key] ?? 0,
            closingAvailable: stockByKey[key]?.availableQty ?? 0,
            closingDamaged: stockByKey[key]?.damagedQty ?? 0,
          ),
    ];
  }

  final List<ReportRow> byProduct;
  final List<ReportRow> bySalesman;
  final List<StockMovementRow> stockMovement;
  final double totalRevenue;
}

/// One aggregated row (name / quantity sold / revenue) for a report breakdown.
class ReportRow {
  ReportRow(this.name);
  final String name;
  int quantity = 0;
  double revenue = 0;
}

class StockMovementRow {
  StockMovementRow({
    required this.productName,
    required this.unitType,
    required this.stockIn,
    required this.returnedGood,
    required this.damaged,
    required this.closingAvailable,
    required this.closingDamaged,
  });

  final String productName;
  final UnitType unitType;
  final int stockIn;
  final int returnedGood;
  final int damaged;
  final int closingAvailable;
  final int closingDamaged;
}
