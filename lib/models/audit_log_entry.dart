class AuditLogEntry {
  AuditLogEntry({
    required this.id,
    this.userId,
    required this.actionType,
    required this.tableName,
    this.recordId,
    required this.occurredAt,
  });

  factory AuditLogEntry.fromJson(Map<String, dynamic> json) {
    return AuditLogEntry(
      id: json['id'] as String,
      userId: json['user_id'] as String?,
      actionType: json['action_type'] as String,
      tableName: json['table_name'] as String,
      recordId: json['record_id'] as String?,
      occurredAt: DateTime.parse(json['occurred_at'] as String),
    );
  }

  final String id;
  final String? userId;
  final String actionType;
  final String tableName;
  final String? recordId;
  final DateTime occurredAt;
}
