/// Model สำหรับ delivery_runs (Logistics Core)
class DeliveryRun {
  final String id;
  final String professionId;
  final String riderId;
  final DateTime runDate;
  final String status; // preparing, ready, in_progress, completed, cancelled
  final int totalOrders;
  final int completedOrders;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DeliveryRun({
    required this.id,
    required this.professionId,
    required this.riderId,
    required this.runDate,
    this.status = 'preparing',
    this.totalOrders = 0,
    this.completedOrders = 0,
    this.startedAt,
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DeliveryRun.fromJson(Map<String, dynamic> json) {
    return DeliveryRun(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      riderId: json['rider_id'] as String,
      runDate: DateTime.parse(json['run_date'] as String),
      status: json['status'] as String? ?? 'preparing',
      totalOrders: json['total_orders'] as int? ?? 0,
      completedOrders: json['completed_orders'] as int? ?? 0,
      startedAt: json['started_at'] != null
          ? DateTime.parse(json['started_at'] as String)
          : null,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'rider_id': riderId,
      'run_date': runDate.toIso8601String(),
      'status': status,
      'total_orders': totalOrders,
      'completed_orders': completedOrders,
      'started_at': startedAt?.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  double get progressPercent => totalOrders > 0 ? completedOrders / totalOrders : 0;
  bool get isComplete => status == 'completed';
}
