import 'unit_type.dart';

enum ReturnCondition {
  good,
  damaged;

  static ReturnCondition parse(String value) => ReturnCondition.values.byName(value);
}

/// Damage and undelivered-return reports are self-attested by the
/// deliveryman who filed them, so they sit `pending` — with no stock effect
/// yet — until an Owner reviews them via `approve_return`/`reject_return`.
enum ReturnStatus {
  pending,
  approved,
  rejected;

  static ReturnStatus parse(String value) => ReturnStatus.values.byName(value);

  String get label {
    switch (this) {
      case ReturnStatus.pending:
        return 'Pending';
      case ReturnStatus.approved:
        return 'Approved';
      case ReturnStatus.rejected:
        return 'Rejected';
    }
  }
}

/// A standalone field event — no shop/order linkage, since dues aren't
/// tracked digitally. `condition == damaged` and `condition == good` (i.e.
/// an undelivered-but-resellable item) are kept as one table but shown as
/// two separate lists — see OwnerReturnsScreen — since approval routes them
/// to different stock buckets (damaged_qty vs. available_qty).
class ReturnRecord {
  ReturnRecord({
    required this.id,
    required this.productId,
    required this.unitType,
    required this.quantity,
    required this.condition,
    this.reason,
    required this.returnDate,
    required this.recordedBy,
    required this.status,
    this.approvedBy,
    this.approvedAt,
  });

  factory ReturnRecord.fromJson(Map<String, dynamic> json) {
    return ReturnRecord(
      id: json['id'] as String,
      productId: json['product_id'] as String,
      unitType: UnitType.parse(json['unit_type'] as String),
      quantity: json['quantity'] as int,
      condition: ReturnCondition.parse(json['condition'] as String),
      reason: json['reason'] as String?,
      returnDate: DateTime.parse(json['return_date'] as String),
      recordedBy: json['recorded_by'] as String,
      status: ReturnStatus.parse(json['status'] as String),
      approvedBy: json['approved_by'] as String?,
      approvedAt: json['approved_at'] == null ? null : DateTime.parse(json['approved_at'] as String),
    );
  }

  final String id;
  final String productId;
  final UnitType unitType;
  final int quantity;
  final ReturnCondition condition;
  final String? reason;
  final DateTime returnDate;
  final String recordedBy;
  final ReturnStatus status;
  final String? approvedBy;
  final DateTime? approvedAt;
}
