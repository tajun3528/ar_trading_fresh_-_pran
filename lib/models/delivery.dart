import 'daily_summary.dart';

/// A delivery confirmation is the deliveryman's own claim — it doesn't move
/// stock or count as a completed sale until an Owner approves it (see
/// approve_delivery/reject_delivery).
enum DeliveryApprovalStatus {
  pending,
  approved,
  rejected;

  static DeliveryApprovalStatus parse(String value) => DeliveryApprovalStatus.values.byName(value);

  String get label {
    switch (this) {
      case DeliveryApprovalStatus.pending:
        return 'Pending approval';
      case DeliveryApprovalStatus.approved:
        return 'Approved';
      case DeliveryApprovalStatus.rejected:
        return 'Rejected';
    }
  }
}

class Delivery {
  Delivery({
    required this.id,
    required this.summaryId,
    required this.deliverymanId,
    required this.deliveryDatetime,
    required this.status,
    required this.approvalStatus,
    this.approvedBy,
    this.approvedAt,
    this.rejectionReason,
    this.loadedAt,
    this.returnsRecordedAt,
    this.paymentAmount,
  });

  factory Delivery.fromJson(Map<String, dynamic> json) {
    return Delivery(
      id: json['id'] as String,
      summaryId: json['summary_id'] as String,
      deliverymanId: json['deliveryman_id'] as String,
      deliveryDatetime: DateTime.parse(json['delivery_datetime'] as String),
      status: SummaryStatus.parse(json['status'] as String),
      approvalStatus: DeliveryApprovalStatus.parse(json['approval_status'] as String),
      approvedBy: json['approved_by'] as String?,
      approvedAt: json['approved_at'] == null ? null : DateTime.parse(json['approved_at'] as String),
      rejectionReason: json['rejection_reason'] as String?,
      loadedAt: json['loaded_at'] == null ? null : DateTime.parse(json['loaded_at'] as String),
      returnsRecordedAt:
          json['returns_recorded_at'] == null ? null : DateTime.parse(json['returns_recorded_at'] as String),
      paymentAmount: (json['payment_amount'] as num?)?.toDouble(),
    );
  }

  final String id;
  final String summaryId;
  final String deliverymanId;
  final DateTime deliveryDatetime;
  final SummaryStatus status;
  final DeliveryApprovalStatus approvalStatus;
  final String? approvedBy;
  final DateTime? approvedAt;
  final String? rejectionReason;

  /// Set when the van was loaded. Until [returnsRecordedAt] is also set, the
  /// round is still out on the road.
  final DateTime? loadedAt;
  final DateTime? returnsRecordedAt;

  /// Cash the deliveryman owes the Owner for this round.
  final double? paymentAmount;

  bool get isOutForDelivery => loadedAt != null && returnsRecordedAt == null;
}

class DeliveryItem {
  DeliveryItem({
    required this.id,
    required this.deliveryId,
    required this.summaryItemId,
    required this.deliveredQuantity,
    required this.loadedQuantity,
    required this.returnedQuantity,
    required this.damagedQuantity,
  });

  factory DeliveryItem.fromJson(Map<String, dynamic> json) {
    return DeliveryItem(
      id: json['id'] as String,
      deliveryId: json['delivery_id'] as String,
      summaryItemId: json['summary_item_id'] as String,
      deliveredQuantity: json['delivered_quantity'] as int,
      loadedQuantity: (json['loaded_quantity'] as int?) ?? 0,
      returnedQuantity: (json['returned_quantity'] as int?) ?? 0,
      damagedQuantity: (json['damaged_quantity'] as int?) ?? 0,
    );
  }

  final String id;
  final String deliveryId;
  final String summaryItemId;
  final int deliveredQuantity;

  /// What physically went into the van. Delivered is what's left of it after
  /// returns and damage.
  final int loadedQuantity;
  final int returnedQuantity;
  final int damagedQuantity;
}
