/// KPI Target Model — เป้าหมายที่ตั้งไว้
class KpiTarget {
  final String id;
  final String professionId;
  final String? branchId;
  final String? employeeId;
  final String targetType; // 'revenue','net_profit','gross_profit','appointments','consultations','inventory_turnover'
  final double targetAmount;
  final String periodType; // 'daily','weekly','monthly','quarterly','yearly'
  final DateTime startDate;
  final DateTime endDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  KpiTarget({
    required this.id,
    required this.professionId,
    this.branchId,
    this.employeeId,
    required this.targetType,
    required this.targetAmount,
    required this.periodType,
    required this.startDate,
    required this.endDate,
    this.createdAt,
    this.updatedAt,
  });

  factory KpiTarget.fromMap(Map<String, dynamic> map) {
    return KpiTarget(
      id: map['id'] as String,
      professionId: map['profession_id'] as String,
      branchId: map['branch_id'] as String?,
      employeeId: map['employee_id'] as String?,
      targetType: map['target_type'] as String,
      targetAmount: (map['target_amount'] as num).toDouble(),
      periodType: map['period_type'] as String,
      startDate: DateTime.parse(map['start_date'] as String),
      endDate: DateTime.parse(map['end_date'] as String),
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'profession_id': professionId,
      'branch_id': branchId,
      'employee_id': employeeId,
      'target_type': targetType,
      'target_amount': targetAmount,
      'period_type': periodType,
      'start_date': startDate.toIso8601String().split('T').first,
      'end_date': endDate.toIso8601String().split('T').first,
    };
  }
}

/// KPI Actuals Model — ข้อมูลจริงที่เกิดขึ้น (Read Model)
class KpiActual {
  final String id;
  final String professionId;
  final String? branchId;
  final String? employeeId;
  final String targetType;
  final String periodType;
  final DateTime periodStart;
  final DateTime periodEnd;
  final double actualAmount;
  final double targetAmount;
  final double achievementRate;
  final String dataSource; // 'orders','journal_entries','appointments','consultations','manual'
  final int refreshCount;
  final DateTime? lastRefreshAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  KpiActual({
    required this.id,
    required this.professionId,
    this.branchId,
    this.employeeId,
    required this.targetType,
    required this.periodType,
    required this.periodStart,
    required this.periodEnd,
    required this.actualAmount,
    required this.targetAmount,
    required this.achievementRate,
    required this.dataSource,
    required this.refreshCount,
    this.lastRefreshAt,
    this.createdAt,
    this.updatedAt,
  });

  factory KpiActual.fromMap(Map<String, dynamic> map) {
    return KpiActual(
      id: map['id'] as String,
      professionId: map['profession_id'] as String,
      branchId: map['branch_id'] as String?,
      employeeId: map['employee_id'] as String?,
      targetType: map['target_type'] as String,
      periodType: map['period_type'] as String,
      periodStart: DateTime.parse(map['period_start'] as String),
      periodEnd: DateTime.parse(map['period_end'] as String),
      actualAmount: (map['actual_amount'] as num?)?.toDouble() ?? 0,
      targetAmount: (map['target_amount'] as num?)?.toDouble() ?? 0,
      achievementRate: (map['achievement_rate'] as num?)?.toDouble() ?? 0,
      dataSource: map['data_source'] as String? ?? 'orders',
      refreshCount: map['refresh_count'] as int? ?? 1,
      lastRefreshAt: map['last_refresh_at'] != null
          ? DateTime.parse(map['last_refresh_at'] as String)
          : null,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
    );
  }

  /// แปลง achievement rate เป็นสี (ตาม Alert Threshold)
  AlertLevel get alertLevel {
    if (achievementRate >= 100) return AlertLevel.success;
    if (achievementRate >= 80) return AlertLevel.warning;
    if (achievementRate >= 60) return AlertLevel.critical;
    return AlertLevel.danger;
  }
}

enum AlertLevel { success, warning, critical, danger }

/// KPI Alert Threshold Model — เกณฑ์การแจ้งเตือน
class KpiAlertThreshold {
  final String id;
  final String professionId;
  final String targetType;
  final double warningThresholdPct;
  final double criticalThresholdPct;
  final bool alertEnabled;
  final List<String> notifyRoles;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  KpiAlertThreshold({
    required this.id,
    required this.professionId,
    required this.targetType,
    required this.warningThresholdPct,
    required this.criticalThresholdPct,
    required this.alertEnabled,
    required this.notifyRoles,
    this.createdAt,
    this.updatedAt,
  });

  factory KpiAlertThreshold.fromMap(Map<String, dynamic> map) {
    return KpiAlertThreshold(
      id: map['id'] as String,
      professionId: map['profession_id'] as String,
      targetType: map['target_type'] as String,
      warningThresholdPct: (map['warning_threshold_pct'] as num).toDouble(),
      criticalThresholdPct: (map['critical_threshold_pct'] as num).toDouble(),
      alertEnabled: map['alert_enabled'] as bool? ?? true,
      notifyRoles: (map['notify_roles'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const ['owner', 'manager'],
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
    );
  }
}

/// KPI Dashboard Summary — สรุปยอดรวมสำหรับแสดงบน Dashboard
class KpiDashboardSummary {
  final String targetType;
  final String periodType;
  final double totalActual;
  final double totalTarget;
  final double overallAchievementRate;
  final int recordCount;
  final DateTime? lastRefreshAt;

  KpiDashboardSummary({
    required this.targetType,
    required this.periodType,
    required this.totalActual,
    required this.totalTarget,
    required this.overallAchievementRate,
    required this.recordCount,
    this.lastRefreshAt,
  });
}
