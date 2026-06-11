/// Model สำหรับ dashboard_snapshots (Read Model / Analytics Core)
class DashboardSnapshot {
  final String id;
  final String professionId;
  final DateTime snapshotDate;
  final String snapshotType; // daily, weekly, monthly, quarterly, yearly
  final Map<String, dynamic> metrics;
  final DateTime createdAt;

  const DashboardSnapshot({
    required this.id,
    required this.professionId,
    required this.snapshotDate,
    required this.snapshotType,
    required this.metrics,
    required this.createdAt,
  });

  factory DashboardSnapshot.fromJson(Map<String, dynamic> json) {
    return DashboardSnapshot(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      snapshotDate: DateTime.parse(json['snapshot_date'] as String),
      snapshotType: json['snapshot_type'] as String,
      metrics: json['metrics'] as Map<String, dynamic>? ?? {},
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'snapshot_date': snapshotDate.toIso8601String(),
      'snapshot_type': snapshotType,
      'metrics': metrics,
      'created_at': createdAt.toIso8601String(),
    };
  }

  double? getMetric(String key) {
    final value = metrics[key];
    if (value is num) return value.toDouble();
    return null;
  }

  String get typeLabel {
    switch (snapshotType) {
      case 'daily': return 'รายวัน';
      case 'weekly': return 'รายสัปดาห์';
      case 'monthly': return 'รายเดือน';
      case 'quarterly': return 'รายไตรมาส';
      case 'yearly': return 'รายปี';
      default: return snapshotType;
    }
  }
}
