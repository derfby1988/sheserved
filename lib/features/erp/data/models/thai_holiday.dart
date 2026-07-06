class ThaiHoliday {
  final String id;
  final DateTime holidayDate;
  final String holidayNameTh;
  final String? holidayNameEn;
  final String holidayType;
  final bool isActive;
  final DateTime createdAt;

  const ThaiHoliday({
    required this.id,
    required this.holidayDate,
    required this.holidayNameTh,
    this.holidayNameEn,
    this.holidayType = 'public',
    this.isActive = true,
    required this.createdAt,
  });

  factory ThaiHoliday.fromJson(Map<String, dynamic> json) {
    return ThaiHoliday(
      id: json['id'] as String,
      holidayDate: DateTime.parse(json['holiday_date'] as String),
      holidayNameTh: json['holiday_name_th'] as String,
      holidayNameEn: json['holiday_name_en'] as String?,
      holidayType: json['holiday_type'] as String? ?? 'public',
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'holiday_date': holidayDate.toIso8601String().split('T')[0],
      'holiday_name_th': holidayNameTh,
      'holiday_name_en': holidayNameEn,
      'holiday_type': holidayType,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
    };
  }

  String get typeLabel {
    switch (holidayType) {
      case 'public':
        return 'วันหยุดราชการ';
      case 'religious':
        return 'วันหยุดทางศาสนา';
      case 'substitution':
        return 'วันหยุดชดเชย';
      case 'special':
        return 'วันหยุดพิเศษ';
      default:
        return holidayType;
    }
  }
}
