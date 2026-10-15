/// One salesman's or one route's month, for comparing them side by side.
/// Both grains carry the same figures so a single widget can rank either.
class PerformanceRow {
  PerformanceRow({
    required this.id,
    required this.name,
    required this.orders,
    required this.revenue,
    required this.basisValue,
    required this.profit1,
    required this.profit2,
    required this.commissionTotal,
    required this.ordersProfit,
    this.profitMarginPercent,
    this.avgOrderValue,
    this.salesmen,
    required this.linesMissingPrice,
    required this.linesMissingBasis,
  });

  static double _d(Object? v) => v == null ? 0 : (v as num).toDouble();
  static double? _dn(Object? v) => v == null ? null : (v as num).toDouble();

  factory PerformanceRow.fromJson(Map<String, dynamic> json, {required String idField, required String name}) {
    return PerformanceRow(
      id: json[idField] as String,
      name: name,
      orders: (json['orders'] as num?)?.toInt() ?? 0,
      revenue: _d(json['revenue']),
      basisValue: _d(json['basis_value']),
      profit1: _d(json['profit1']),
      profit2: _d(json['profit2']),
      commissionTotal: _d(json['commission_total']),
      ordersProfit: _d(json['orders_profit']),
      profitMarginPercent: _dn(json['profit_margin_percent']),
      avgOrderValue: _dn(json['avg_order_value']),
      salesmen: (json['salesmen'] as num?)?.toInt(),
      linesMissingPrice: (json['lines_missing_price'] as num?)?.toInt() ?? 0,
      linesMissingBasis: (json['lines_missing_basis'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String name;
  final int orders;
  final double revenue;
  final double basisValue;
  final double profit1;
  final double profit2;
  final double commissionTotal;
  final double ordersProfit;

  /// What the owner keeps per taka sold. The number that separates a big
  /// seller from a profitable one.
  final double? profitMarginPercent;

  /// Routes only — many small drops or a few big ones.
  final double? avgOrderValue;

  /// Routes only — how many salesmen worked it.
  final int? salesmen;

  final int linesMissingPrice;
  final int linesMissingBasis;
}
