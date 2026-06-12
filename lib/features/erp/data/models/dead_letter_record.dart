/// Model สำหรับ dead_letter_records (formalized dead letter queue)
class DeadLetterRecord {
  final String id;
  final String professionId;
  final String sourceQueue;
  final String? originalJobId;
  final String aggregateType;
  final String aggregateId;
  final String eventType;
  final Map<String, dynamic> payload;
  final String errorMessage;
  final int retryCount;
  final String resolution; // unresolved, manual_retry, compensated, ignored
  final String? resolvedBy;
  final DateTime? resolvedAt;
  final DateTime createdAt;

  const DeadLetterRecord({
    required this.id,
    required this.professionId,
    required this.sourceQueue,
    this.originalJobId,
    required this.aggregateType,
    required this.aggregateId,
    required this.eventType,
    required this.payload,
    required this.errorMessage,
    this.retryCount = 0,
    this.resolution = 'unresolved',
    this.resolvedBy,
    this.resolvedAt,
    required this.createdAt,
  });

  factory DeadLetterRecord.fromJson(Map<String, dynamic> json) {
    return DeadLetterRecord(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      sourceQueue: json['source_queue'] as String,
      originalJobId: json['original_job_id'] as String?,
      aggregateType: json['aggregate_type'] as String,
      aggregateId: json['aggregate_id'] as String,
      eventType: json['event_type'] as String,
      payload: json['payload'] as Map<String, dynamic>? ?? {},
      errorMessage: json['error_message'] as String,
      retryCount: (json['retry_count'] as num?)?.toInt() ?? 0,
      resolution: json['resolution'] as String? ?? 'unresolved',
      resolvedBy: json['resolved_by'] as String?,
      resolvedAt: json['resolved_at'] != null
          ? DateTime.parse(json['resolved_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'source_queue': sourceQueue,
      'original_job_id': originalJobId,
      'aggregate_type': aggregateType,
      'aggregate_id': aggregateId,
      'event_type': eventType,
      'payload': payload,
      'error_message': errorMessage,
      'retry_count': retryCount,
      'resolution': resolution,
      'resolved_by': resolvedBy,
      'resolved_at': resolvedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  bool get isUnresolved => resolution == 'unresolved';
}
