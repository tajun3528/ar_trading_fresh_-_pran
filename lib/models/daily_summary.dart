import 'unit_type.dart';

enum SummaryStatus {
  booked,
  delivered,
  partiallyDelivered,
  cancelled;

  static SummaryStatus parse(String value) {
    switch (value) {
      case 'partially_delivered':
        return SummaryStatus.partiallyDelivered;
      default:
        return SummaryStatus.values.byName(value);
    }
  }

  String get label {
    switch (this) {
      case SummaryStatus.booked:
        return 'Submitted';
      case SummaryStatus.delivered:
        return 'Delivered';
      case SummaryStatus.partiallyDelivered:
        return 'Partially Delivered';
      case SummaryStatus.cancelled:
        return 'Cancelled';
    }
  }
}

/// A salesman's aggregate "what's needed tomorrow" submission — no shop
/// reference; shop-level dealing happens on paper cash memos in the field.
class DailySummary {
  DailySummary({
    required this.id,
    required this.salesmanId,
    required this.submissionDate,
    required this.deliveryDate,
    required this.totalAmount,
    required this.status,
    required this.companyId,
    this.routeId,
    this.commissionAmount = 0,
  });

  factory DailySummary.fromJson(Map<String, dynamic> json) {
    return DailySummary(
      id: json['id'] as String,
      salesmanId: json['salesman_id'] as String,
      submissionDate: DateTime.parse(json['submission_date'] as String),
      deliveryDate: DateTime.parse(json['delivery_date'] as String),
      totalAmount: (json['total_amount'] as num).toDouble(),
      status: SummaryStatus.parse(json['status'] as String),
      companyId: json['company_id'] as String,
      routeId: json['route_id'] as String?,
      commissionAmount: (json['commission_amount'] as num?)?.toDouble() ?? 0,
    );
  }

  final String id;
  final String salesmanId;
  final DateTime submissionDate;
  final DateTime deliveryDate;
  final double totalAmount;
  final SummaryStatus status;
  final String companyId;
  final String? routeId;
  final double commissionAmount;

  /// What's left for the Owner after the salesman keeps their commission —
  /// salesmen collect on paper cash memos in the field and remit this net
  /// amount.
  double get netAmount => totalAmount - commissionAmount;

  bool get isEditable => status == SummaryStatus.booked;
}

class DailySummaryItem {
  DailySummaryItem({
    required this.id,
    required this.summaryId,
    required this.productId,
    required this.unitType,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  factory DailySummaryItem.fromJson(Map<String, dynamic> json) {
    return DailySummaryItem(
      id: json['id'] as String,
      summaryId: json['summary_id'] as String,
      productId: json['product_id'] as String,
      unitType: UnitType.parse(json['unit_type'] as String),
      quantity: json['quantity'] as int,
      unitPrice: (json['unit_price'] as num).toDouble(),
      lineTotal: (json['line_total'] as num).toDouble(),
    );
  }

  final String id;
  final String summaryId;
  final String productId;
  final UnitType unitType;
  final int quantity;
  final double unitPrice;
  final double lineTotal;
}

/// A single line the salesman is composing before submitting — not persisted
/// until submit_daily_summary()/edit_daily_summary() is called.
class DraftSummaryLine {
  DraftSummaryLine({
    required this.productId,
    required this.productName,
    required this.unitType,
    required this.quantity,
    required this.unitPrice,
  });

  final String productId;
  final String productName;
  final UnitType unitType;
  final int quantity;
  final double unitPrice;

  double get lineTotal => unitPrice * quantity;

  Map<String, dynamic> toRpcJson() => {
        'product_id': productId,
        'unit_type': unitType.name,
        'quantity': quantity,
      };
}
