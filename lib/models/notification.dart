/// Something that happened which the signed-in user needs to know about,
/// raised by the database when a delivery moves rather than by whoever was
/// looking at the time — so it reaches them even if the app was closed.
class AppNotification {
  AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    this.body,
    this.link,
    this.readAt,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      kind: json['kind'] as String,
      title: json['title'] as String,
      body: json['body'] as String?,
      link: json['link'] as String?,
      readAt: json['read_at'] == null ? null : DateTime.parse(json['read_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String kind;
  final String title;
  final String? body;

  /// An in-app route to open when tapped, or null if there's nowhere to go.
  final String? link;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get isUnread => readAt == null;

  /// How long ago, in the shorthand people actually use.
  String get age {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }
}

/// One batch of a product with its expiry date. Quantities are what was
/// received under the batch, not what is left — stock is not tracked per
/// batch, so this warns rather than enforces oldest-first.
class ExpiryBatch {
  ExpiryBatch({
    required this.batchId,
    required this.productId,
    required this.productName,
    required this.categoryId,
    required this.batchNo,
    this.mfgDate,
    this.expiryDate,
    this.daysRemaining,
    required this.status,
    this.received,
    required this.receipts,
    this.lastReceivedOn,
  });

  factory ExpiryBatch.fromJson(Map<String, dynamic> json) {
    return ExpiryBatch(
      batchId: json['batch_id'] as String,
      productId: json['product_id'] as String,
      productName: json['product_name'] as String,
      categoryId: json['category_id'] as String,
      batchNo: json['batch_no'] as String,
      mfgDate: json['mfg_date'] == null ? null : DateTime.parse(json['mfg_date'] as String),
      expiryDate: json['expiry_date'] == null ? null : DateTime.parse(json['expiry_date'] as String),
      daysRemaining: (json['days_remaining'] as num?)?.toInt(),
      status: json['status'] as String,
      received: json['received'] as String?,
      receipts: (json['receipts'] as num?)?.toInt() ?? 0,
      lastReceivedOn:
          json['last_received_on'] == null ? null : DateTime.parse(json['last_received_on'] as String),
    );
  }

  final String batchId;
  final String productId;
  final String productName;
  final String categoryId;
  final String batchNo;
  final DateTime? mfgDate;
  final DateTime? expiryDate;
  final int? daysRemaining;

  /// expired | critical | warning | ok | unknown
  final String status;

  /// A per-unit breakdown of what came in under this batch, e.g. "5 carton,
  /// 20 pcs" — receipts are recorded per unit, so one number would be adding
  /// cartons to pieces.
  final String? received;
  final int receipts;
  final DateTime? lastReceivedOn;

  bool get needsAttention => status == 'expired' || status == 'critical';
}
