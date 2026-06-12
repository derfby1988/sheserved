/// Model สำหรับ retry_attempts (cross-queue retry tracking)
class RetryAttempt {
  final String id;
  final String professionId;
  final String operationType;
  final String targetId;
  final int attemptNumber;
  final String status; // pending, success, permanent_failure
  final String? errorMessage;
  final int backoffMs;
  final DateTime? nextAttemptAt;
  final DateTime? succeededAt;
  final DateTime createdAt;

  const RetryAttempt({
    required this.id,
    required this.professionId,
    required this.operationType,
    required this.targetId,
    this.attemptNumber = 1,
    this.status = 'pending',
    this.errorMessage,
    this.backoffMs = 2000,
    this.nextAttemptAt,
    this.succeededAt,
    required this.createdAt,
  });

  factory RetryAttempt.fromJson(Map<String, dynamic> json) {
    return RetryAttempt(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      operationType: json['operation_type'] as String,
      targetId: json['target_id'] as String,
      attemptNumber: (json['attempt_number'] as num?)?.toInt() ?? 1,
      status: json['status'] as String? ?? 'pending',
      errorMessage: json['error_message'] as String?,
      backoffMs: (json['backoff_ms'] as num?)?.toInt() ?? 2000,
      nextAttemptAt: json['next_attempt_at'] != null
          ? DateTime.parse(json['next_attempt_at'] as String)
          : null,
      succeededAt: json['succeeded_at'] != null
          ? DateTime.parse(json['succeeded_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'operation_type': operationType,
      'target_id': targetId,
      'attempt_number': attemptNumber,
      'status': status,
      'error_message': errorMessage,
      'backoff_ms': backoffMs,
      'next_attempt_at': nextAttemptAt?.toIso8601String(),
      'succeeded_at': succeededAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  bool get isPending => status == 'pending';
  bool get isSuccess => status == 'success';
  bool get isPermanentFailure => status == 'permanent_failure';
}
