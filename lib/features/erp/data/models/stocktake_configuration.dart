/// Model สำหรับ stocktake_configurations (ตั้งค่ารอบตรวจนับสต็อก)
class StocktakeConfiguration {
  final String id;
  final String professionId;
  final String? branchId;
  final String name;
  final String frequencyType; // WEEKLY, MONTHLY, QUARTERLY, YEARLY, CUSTOM
  final int? customIntervalDays;
  final DateTime nextStocktakeDate;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const StocktakeConfiguration({
    required this.id,
    required this.professionId,
    this.branchId,
    this.name = 'Stocktake',
    required this.frequencyType,
    this.customIntervalDays,
    required this.nextStocktakeDate,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory StocktakeConfiguration.fromJson(Map<String, dynamic> json) {
    return StocktakeConfiguration(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      branchId: json['branch_id'] as String?,
      name: json['name'] as String? ?? 'Stocktake',
      frequencyType: json['frequency_type'] as String,
      customIntervalDays: (json['custom_interval_days'] as num?)?.toInt(),
      nextStocktakeDate: DateTime.parse(json['next_stocktake_date'] as String),
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'branch_id': branchId,
      'name': name,
      'frequency_type': frequencyType,
      'custom_interval_days': customIntervalDays,
      'next_stocktake_date': nextStocktakeDate.toIso8601String(),
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  String get frequencyLabel {
    switch (frequencyType) {
      case 'WEEKLY': return 'รายสัปดาห์';
      case 'MONTHLY': return 'รายเดือน';
      case 'QUARTERLY': return 'รายไตรมาส';
      case 'YEARLY': return 'รายปี';
      case 'CUSTOM': return 'กำหนดเอง (${customIntervalDays ?? ''} วัน)';
      default: return frequencyType;
    }
  }
}
