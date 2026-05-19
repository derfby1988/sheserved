class DeviceHealthMetric {
  final String? id;
  final String userId;
  final String metricType;
  final num value;
  final String unit;
  final DateTime measuredAt;
  final String sourceName;
  final DateTime? syncedAt;

  DeviceHealthMetric({
    this.id,
    required this.userId,
    required this.metricType,
    required this.value,
    required this.unit,
    required this.measuredAt,
    required this.sourceName,
    this.syncedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      'metric_type': metricType,
      'value': value,
      'unit': unit,
      'measured_at': measuredAt.toIso8601String(),
      'source_name': sourceName,
      if (syncedAt != null) 'synced_at': syncedAt!.toIso8601String(),
    };
  }

  factory DeviceHealthMetric.fromJson(Map<String, dynamic> json) {
    return DeviceHealthMetric(
      id: json['id'],
      userId: json['user_id'],
      metricType: json['metric_type'],
      value: json['value'],
      unit: json['unit'],
      measuredAt: DateTime.parse(json['measured_at']),
      sourceName: json['source_name'],
      syncedAt: json['synced_at'] != null
          ? DateTime.parse(json['synced_at'])
          : null,
    );
  }
}
