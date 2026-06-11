/// Model สำหรับ scheduled_reports (KPI Step 5)
class ScheduledReport {
  final String id;
  final String professionId;
  final String reportName;
  final String reportType; // sales_summary, inventory_status, employee_performance, customer_activity, financial_gl
  final String frequency; // daily, weekly, monthly, quarterly
  final String format; // pdf, excel, csv
  final Map<String, dynamic> parameters;
  final bool isActive;
  final DateTime? lastRunAt;
  final DateTime? nextRunAt;
  final String? lastRunStatus;
  final String? lastRunError;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ScheduledReport({
    required this.id,
    required this.professionId,
    required this.reportName,
    required this.reportType,
    this.frequency = 'daily',
    this.format = 'pdf',
    this.parameters = const {},
    this.isActive = true,
    this.lastRunAt,
    this.nextRunAt,
    this.lastRunStatus,
    this.lastRunError,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ScheduledReport.fromJson(Map<String, dynamic> json) {
    return ScheduledReport(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      reportName: json['report_name'] as String,
      reportType: json['report_type'] as String,
      frequency: json['frequency'] as String? ?? 'daily',
      format: json['format'] as String? ?? 'pdf',
      parameters: json['parameters'] as Map<String, dynamic>? ?? {},
      isActive: json['is_active'] as bool? ?? true,
      lastRunAt: json['last_run_at'] != null ? DateTime.parse(json['last_run_at'] as String) : null,
      nextRunAt: json['next_run_at'] != null ? DateTime.parse(json['next_run_at'] as String) : null,
      lastRunStatus: json['last_run_status'] as String?,
      lastRunError: json['last_run_error'] as String?,
      createdBy: json['created_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'profession_id': professionId,
      'report_name': reportName,
      'report_type': reportType,
      'frequency': frequency,
      'format': format,
      'parameters': parameters,
      'is_active': isActive,
      'next_run_at': nextRunAt?.toIso8601String(),
    };
  }
}
