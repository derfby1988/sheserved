/// Model สำหรับ projection_checkpoints (CQRS Read Model)
class ProjectionCheckpoint {
  final String id;
  final String professionId;
  final String projectionName; // e.g. daily_sales, monthly_revenue
  final String? lastEventId;
  final int lastEventSeq;
  final Map<String, dynamic> stateSnapshot;
  final DateTime updatedAt;

  const ProjectionCheckpoint({
    required this.id,
    required this.professionId,
    required this.projectionName,
    this.lastEventId,
    this.lastEventSeq = 0,
    this.stateSnapshot = const {},
    required this.updatedAt,
  });

  factory ProjectionCheckpoint.fromJson(Map<String, dynamic> json) {
    return ProjectionCheckpoint(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      projectionName: json['projection_name'] as String,
      lastEventId: json['last_event_id'] as String?,
      lastEventSeq: (json['last_event_seq'] as num?)?.toInt() ?? 0,
      stateSnapshot: json['state_snapshot'] as Map<String, dynamic>? ?? {},
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'projection_name': projectionName,
      'last_event_id': lastEventId,
      'last_event_seq': lastEventSeq,
      'state_snapshot': stateSnapshot,
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
