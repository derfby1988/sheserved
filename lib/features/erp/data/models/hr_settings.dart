class HrSettings {
  final String id;
  final String professionId;
  final String attendanceMode;
  final bool allowFlexibleHours;
  final double defaultWorkHoursPerDay;
  final double otMultiplierWeekday;
  final double otMultiplierWeekend;
  final double otMultiplierHoliday;
  final double socialSecurityRate;
  final double diligenceAllowanceAmount;
  final double providentFundEmployeeRate;
  final double providentFundEmployerRate;
  final double providentFundWageCap;
  final bool taxCalculationEnabled;
  final double lateDeductionPerMinute;
  final double absentDeductionPerDay;
  final String? externalHrmApiUrl;
  final bool externalHrmSyncEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  const HrSettings({
    required this.id,
    required this.professionId,
    this.attendanceMode = 'manual',
    this.allowFlexibleHours = false,
    this.defaultWorkHoursPerDay = 8.0,
    this.otMultiplierWeekday = 1.5,
    this.otMultiplierWeekend = 2.0,
    this.otMultiplierHoliday = 3.0,
    this.socialSecurityRate = 0.05,
    this.diligenceAllowanceAmount = 0,
    this.providentFundEmployeeRate = 0.03,
    this.providentFundEmployerRate = 0.03,
    this.providentFundWageCap = 100000,
    this.taxCalculationEnabled = false,
    this.lateDeductionPerMinute = 0,
    this.absentDeductionPerDay = 0,
    this.externalHrmApiUrl,
    this.externalHrmSyncEnabled = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory HrSettings.fromJson(Map<String, dynamic> json) {
    return HrSettings(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      attendanceMode: json['attendance_mode'] as String? ?? 'manual',
      allowFlexibleHours: json['allow_flexible_hours'] as bool? ?? false,
      defaultWorkHoursPerDay:
          (json['default_work_hours_per_day'] as num?)?.toDouble() ?? 8.0,
      otMultiplierWeekday:
          (json['ot_multiplier_weekday'] as num?)?.toDouble() ?? 1.5,
      otMultiplierWeekend:
          (json['ot_multiplier_weekend'] as num?)?.toDouble() ?? 2.0,
      otMultiplierHoliday:
          (json['ot_multiplier_holiday'] as num?)?.toDouble() ?? 3.0,
      socialSecurityRate:
          (json['social_security_rate'] as num?)?.toDouble() ?? 0.05,
      diligenceAllowanceAmount:
          (json['diligence_allowance_amount'] as num?)?.toDouble() ?? 0,
      providentFundEmployeeRate:
          (json['provident_fund_employee_rate'] as num?)?.toDouble() ?? 0.03,
      providentFundEmployerRate:
          (json['provident_fund_employer_rate'] as num?)?.toDouble() ?? 0.03,
      providentFundWageCap:
          (json['provident_fund_wage_cap'] as num?)?.toDouble() ?? 100000,
      taxCalculationEnabled:
          json['tax_calculation_enabled'] as bool? ?? false,
      lateDeductionPerMinute:
          (json['late_deduction_per_minute'] as num?)?.toDouble() ?? 0,
      absentDeductionPerDay:
          (json['absent_deduction_per_day'] as num?)?.toDouble() ?? 0,
      externalHrmApiUrl: json['external_hrm_api_url'] as String?,
      externalHrmSyncEnabled:
          json['external_hrm_sync_enabled'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'attendance_mode': attendanceMode,
      'allow_flexible_hours': allowFlexibleHours,
      'default_work_hours_per_day': defaultWorkHoursPerDay,
      'ot_multiplier_weekday': otMultiplierWeekday,
      'ot_multiplier_weekend': otMultiplierWeekend,
      'ot_multiplier_holiday': otMultiplierHoliday,
      'social_security_rate': socialSecurityRate,
      'diligence_allowance_amount': diligenceAllowanceAmount,
      'provident_fund_employee_rate': providentFundEmployeeRate,
      'provident_fund_employer_rate': providentFundEmployerRate,
      'provident_fund_wage_cap': providentFundWageCap,
      'tax_calculation_enabled': taxCalculationEnabled,
      'late_deduction_per_minute': lateDeductionPerMinute,
      'absent_deduction_per_day': absentDeductionPerDay,
      'external_hrm_api_url': externalHrmApiUrl,
      'external_hrm_sync_enabled': externalHrmSyncEnabled,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
