/// Model สำหรับ kpi_aggregations (Analytics Core)
class KpiAggregation {
  final String id;
  final String professionId;
  final String kpiName; // revenue, order_count, customer_count, etc.
  final String kpiCategory; // sales, finance, operations, customer, inventory
  final DateTime periodStart;
  final DateTime periodEnd;
  final double value;
  final double? targetValue;
  final String unit; // count, amount, percent, days
  final bool isBetterHigher;
  final DateTime createdAt;

  const KpiAggregation({
    required this.id,
    required this.professionId,
    required this.kpiName,
    required this.kpiCategory,
    required this.periodStart,
    required this.periodEnd,
    this.value = 0,
    this.targetValue,
    this.unit = 'count',
    this.isBetterHigher = true,
    required this.createdAt,
  });

  factory KpiAggregation.fromJson(Map<String, dynamic> json) {
    return KpiAggregation(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      kpiName: json['kpi_name'] as String,
      kpiCategory: json['kpi_category'] as String,
      periodStart: DateTime.parse(json['period_start'] as String),
      periodEnd: DateTime.parse(json['period_end'] as String),
      value: (json['value'] as num?)?.toDouble() ?? 0,
      targetValue: (json['target_value'] as num?)?.toDouble(),
      unit: json['unit'] as String? ?? 'count',
      isBetterHigher: json['is_better_higher'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'kpi_name': kpiName,
      'kpi_category': kpiCategory,
      'period_start': periodStart.toIso8601String(),
      'period_end': periodEnd.toIso8601String(),
      'value': value,
      'target_value': targetValue,
      'unit': unit,
      'is_better_higher': isBetterHigher,
      'created_at': createdAt.toIso8601String(),
    };
  }

  double? get variancePercent => targetValue != null && targetValue! > 0
      ? ((value - targetValue!) / targetValue!) * 100
      : null;

  bool get isOnTarget => targetValue != null &&
      (isBetterHigher ? value >= targetValue! : value <= targetValue!);
}
