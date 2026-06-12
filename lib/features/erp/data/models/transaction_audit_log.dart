/// Model สำหรับ transaction_audit_log (append-only change tracking)
class TransactionAuditLog {
  final int id;
  final String tableName;
  final String recordId;
  final String action; // INSERT, UPDATE, DELETE
  final Map<String, dynamic>? oldValues;
  final Map<String, dynamic>? newValues;
  final String? actorId;
  final String actorType; // user, system, worker, webhook
  final String? professionId;
  final String? branchId;
  final String? sessionId;
  final String? ipAddress;
  final String? userAgent;
  final String? reason;
  final DateTime createdAt;

  const TransactionAuditLog({
    required this.id,
    required this.tableName,
    required this.recordId,
    required this.action,
    this.oldValues,
    this.newValues,
    this.actorId,
    this.actorType = 'user',
    this.professionId,
    this.branchId,
    this.sessionId,
    this.ipAddress,
    this.userAgent,
    this.reason,
    required this.createdAt,
  });

  factory TransactionAuditLog.fromJson(Map<String, dynamic> json) {
    return TransactionAuditLog(
      id: (json['id'] as num).toInt(),
      tableName: json['table_name'] as String,
      recordId: json['record_id'] as String,
      action: json['action'] as String,
      oldValues: json['old_values'] as Map<String, dynamic>?,
      newValues: json['new_values'] as Map<String, dynamic>?,
      actorId: json['actor_id'] as String?,
      actorType: json['actor_type'] as String? ?? 'user',
      professionId: json['profession_id'] as String?,
      branchId: json['branch_id'] as String?,
      sessionId: json['session_id'] as String?,
      ipAddress: json['ip_address'] as String?,
      userAgent: json['user_agent'] as String?,
      reason: json['reason'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'table_name': tableName,
      'record_id': recordId,
      'action': action,
      'old_values': oldValues,
      'new_values': newValues,
      'actor_id': actorId,
      'actor_type': actorType,
      'profession_id': professionId,
      'branch_id': branchId,
      'session_id': sessionId,
      'ip_address': ipAddress,
      'user_agent': userAgent,
      'reason': reason,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
