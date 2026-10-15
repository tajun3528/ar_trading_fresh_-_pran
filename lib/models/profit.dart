import 'unit_type.dart';

double _toDouble(Object? value) => value == null ? 0 : (value as num).toDouble();
double? _toDoubleOrNull(Object? value) => value == null ? null : (value as num).toDouble();

/// What one salesman sells one unit of one product for, in one month. Two
/// salesmen can price the same product differently — profit is always worked
/// out against the price of whoever made the sale.
class MonthlySellingPrice {
  MonthlySellingPrice({
    required this.productId,
    required this.unitType,
    required this.month,
    required this.sellingPrice,
  });

  factory MonthlySellingPrice.fromJson(Map<String, dynamic> json) {
    return MonthlySellingPrice(
      productId: json['product_id'] as String,
      unitType: UnitType.parse(json['unit_type'] as String),
      month: DateTime.parse(json['month'] as String),
      sellingPrice: _toDouble(json['selling_price']),
    );
  }

  final String productId;
  final UnitType unitType;
  final DateTime month;
  final double sellingPrice;
}

/// The Owner's monthly sales target for a company, and the bonus percentage
/// the vendor pays on the month's DP-value once it's reached.
class MonthlyTarget {
  MonthlyTarget({
    required this.id,
    required this.companyId,
    required this.month,
    required this.targetAmount,
    required this.bonusPercent,
  });

  factory MonthlyTarget.fromJson(Map<String, dynamic> json) {
    return MonthlyTarget(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      month: DateTime.parse(json['month'] as String),
      targetAmount: _toDouble(json['target_amount']),
      bonusPercent: _toDouble(json['bonus_percent']),
    );
  }

  final String id;
  final String companyId;
  final DateTime month;
  final double targetAmount;
  final double bonusPercent;
}

/// One delivered order's bottom line: the margin over DP, the vendor's
/// commission on that DP, less the salesman's own commission.
class SummaryProfit {
  SummaryProfit({
    required this.summaryId,
    required this.salesmanId,
    required this.companyId,
    required this.deliveryDate,
    required this.commissionAmount,
    required this.revenue,
    required this.dpValue,
    required this.profit1,
    required this.profit2,
    required this.orderProfit,
    required this.linesMissingPrice,
    required this.linesMissingDp,
  });

  factory SummaryProfit.fromJson(Map<String, dynamic> json) {
    return SummaryProfit(
      summaryId: json['summary_id'] as String,
      salesmanId: json['salesman_id'] as String,
      companyId: json['company_id'] as String,
      deliveryDate: DateTime.parse(json['delivery_date'] as String),
      commissionAmount: _toDouble(json['commission_amount']),
      revenue: _toDouble(json['revenue']),
      dpValue: _toDouble(json['dp_value']),
      profit1: _toDouble(json['profit1']),
      profit2: _toDouble(json['profit2']),
      orderProfit: _toDouble(json['order_profit']),
      linesMissingPrice: (json['lines_missing_price'] as num?)?.toInt() ?? 0,
      linesMissingDp: (json['lines_missing_dp'] as num?)?.toInt() ?? 0,
    );
  }

  final String summaryId;
  final String salesmanId;
  final String companyId;
  final DateTime deliveryDate;
  final double commissionAmount;
  final double revenue;
  final double dpValue;

  /// Margin over what the goods cost: (selling price − DP) × delivered qty.
  final double profit1;

  /// The vendor's commission on the DP-value of what was sold.
  final double profit2;
  final double orderProfit;

  /// Delivered lines the salesman never priced for that month — their revenue
  /// is missing from these figures, so the Owner can chase it up.
  final int linesMissingPrice;
  final int linesMissingDp;

  bool get hasGaps => linesMissingPrice > 0 || linesMissingDp > 0;
}

/// A whole month for one company: every delivered order's profit, plus the
/// target bonus once the month's DP-value clears the target.
class MonthlyProfit {
  MonthlyProfit({
    required this.companyId,
    required this.month,
    required this.revenue,
    required this.dpValue,
    required this.profit1,
    required this.profit2,
    required this.commissionTotal,
    required this.ordersProfit,
    required this.targetAmount,
    required this.bonusPercent,
    required this.targetMet,
    required this.bonusAmount,
    required this.netProfit,
  });

  factory MonthlyProfit.fromJson(Map<String, dynamic> json) {
    return MonthlyProfit(
      companyId: json['company_id'] as String,
      month: DateTime.parse(json['month'] as String),
      revenue: _toDouble(json['revenue']),
      dpValue: _toDouble(json['dp_value']),
      profit1: _toDouble(json['profit1']),
      profit2: _toDouble(json['profit2']),
      commissionTotal: _toDouble(json['commission_total']),
      ordersProfit: _toDouble(json['orders_profit']),
      targetAmount: _toDoubleOrNull(json['target_amount']),
      bonusPercent: _toDouble(json['bonus_percent']),
      targetMet: json['target_met'] as bool? ?? false,
      bonusAmount: _toDouble(json['bonus_amount']),
      netProfit: _toDouble(json['net_profit']),
    );
  }

  final String companyId;
  final DateTime month;
  final double revenue;
  final double dpValue;
  final double profit1;
  final double profit2;
  final double commissionTotal;
  final double ordersProfit;
  final double? targetAmount;
  final double bonusPercent;
  final bool targetMet;
  final double bonusAmount;
  final double netProfit;

  /// How far the month's DP-value has come toward the target, 0..1.
  double get targetProgress {
    final target = targetAmount;
    if (target == null || target <= 0) return 0;
    return (dpValue / target).clamp(0, 1).toDouble();
  }
}

/// One product sold in one unit, over one month — what moved, what it earned,
/// and how its selling price compared with what the company charged for it.
///
/// Deliberately per-unit rather than per-product: the same item can sell above
/// the company's price by the carton and below it loose, and a per-product
/// total would average that away.
class ProductSales {
  ProductSales({
    required this.productId,
    required this.productName,
    required this.categoryId,
    required this.unitType,
    required this.month,
    required this.quantity,
    required this.revenue,
    required this.basisValue,
    required this.margin,
    required this.avgSellingPrice,
    required this.avgBasisPrice,
    required this.orders,
    required this.linesMissingBasis,
  });

  factory ProductSales.fromJson(Map<String, dynamic> json) {
    return ProductSales(
      productId: json['product_id'] as String,
      productName: json['product_name'] as String,
      categoryId: json['category_id'] as String,
      unitType: UnitType.parse(json['unit_type'] as String),
      month: DateTime.parse(json['month'] as String),
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      revenue: _toDouble(json['revenue']),
      basisValue: _toDouble(json['basis_value']),
      margin: _toDouble(json['margin']),
      avgSellingPrice: _toDoubleOrNull(json['avg_selling_price']),
      avgBasisPrice: _toDoubleOrNull(json['avg_basis_price']),
      orders: (json['orders'] as num?)?.toInt() ?? 0,
      linesMissingBasis: (json['lines_missing_basis'] as num?)?.toInt() ?? 0,
    );
  }

  final String productId;
  final String productName;
  final String categoryId;
  final UnitType unitType;
  final DateTime month;
  final int quantity;
  final double revenue;
  final double basisValue;
  final double margin;
  final double? avgSellingPrice;
  final double? avgBasisPrice;
  final int orders;

  /// Lines whose cost price couldn't be worked out — their value is missing
  /// from [basisValue] and [margin], so those read better than they are.
  final int linesMissingBasis;

  bool get isAboveBasis => margin > 0;
  bool get isBelowBasis => margin < 0;
}
