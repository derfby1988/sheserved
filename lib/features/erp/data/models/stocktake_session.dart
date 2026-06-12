/// Model สำหรับ stocktake_sessions (รอบตรวจนับสต็อก)
class StocktakeSession {
  final String id;
  final String professionId;
  final String? stocktakeConfigId;
  final String? branchId;
  final String status; // in_progress, completed, cancelled, approved
  final DateTime startedAt;
  final DateTime? completedAt;
  final String? approvedBy;
  final DateTime? approvedAt;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const StocktakeSession({
    required this.id,
    required this.professionId,
    this.stocktakeConfigId,
    this.branchId,
    this.status = 'in_progress',
    required this.startedAt,
    this.completedAt,
    this.approvedBy,
    this.approvedAt,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory StocktakeSession.fromJson(Map<String, dynamic> json) {
    return StocktakeSession(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      stocktakeConfigId: json['stocktake_config_id'] as String?,
      branchId: json['branch_id'] as String?,
      status: json['status'] as String? ?? 'in_progress',
      startedAt: DateTime.parse(json['started_at'] as String),
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      approvedBy: json['approved_by'] as String?,
      approvedAt: json['approved_at'] != null
          ? DateTime.parse(json['approved_at'] as String)
          : null,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'stocktake_config_id': stocktakeConfigId,
      'branch_id': branchId,
      'status': status,
      'started_at': startedAt.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'approved_by': approvedBy,
      'approved_at': approvedAt?.toIso8601String(),
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  bool get isInProgress => status == 'in_progress';
  bool get isCompleted => status == 'completed';
}
