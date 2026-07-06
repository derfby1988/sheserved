class PayrollRun {
  final String id;
  final String professionId;
  final String? branchId;
  final String runName;
  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime? payDate;
  final String status;
  final double totalGross;
  final double totalDeductions;
  final double totalNet;
  final double employerSocialSecurity;
  final double employerProvidentFund;
  final double totalEmployerCost;
  final String? approvedBy;
  final DateTime? approvedAt;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PayrollRun({
    required this.id,
    required this.professionId,
    this.branchId,
    required this.runName,
    required this.periodStart,
    required this.periodEnd,
    this.payDate,
    this.status = 'draft',
    this.totalGross = 0,
    this.totalDeductions = 0,
    this.totalNet = 0,
    this.employerSocialSecurity = 0,
    this.employerProvidentFund = 0,
    this.totalEmployerCost = 0,
    this.approvedBy,
    this.approvedAt,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PayrollRun.fromJson(Map<String, dynamic> json) {
    return PayrollRun(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      branchId: json['branch_id'] as String?,
      runName: json['run_name'] as String,
      periodStart: DateTime.parse(json['period_start'] as String),
      periodEnd: DateTime.parse(json['period_end'] as String),
      payDate: json['pay_date'] != null
          ? DateTime.parse(json['pay_date'] as String)
          : null,
      status: json['status'] as String? ?? 'draft',
      totalGross: (json['total_gross'] as num?)?.toDouble() ?? 0,
      totalDeductions: (json['total_deductions'] as num?)?.toDouble() ?? 0,
      totalNet: (json['total_net'] as num?)?.toDouble() ?? 0,
      employerSocialSecurity: (json['employer_social_security'] as num?)?.toDouble() ?? 0,
      employerProvidentFund: (json['employer_provident_fund'] as num?)?.toDouble() ?? 0,
      totalEmployerCost: (json['total_employer_cost'] as num?)?.toDouble() ?? 0,
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
      'branch_id': branchId,
      'run_name': runName,
      'period_start': periodStart.toIso8601String(),
      'period_end': periodEnd.toIso8601String(),
      'pay_date': payDate?.toIso8601String(),
      'status': status,
      'total_gross': totalGross,
      'total_deductions': totalDeductions,
      'total_net': totalNet,
      'employer_social_security': employerSocialSecurity,
      'employer_provident_fund': employerProvidentFund,
      'total_employer_cost': totalEmployerCost,
      'approved_by': approvedBy,
      'approved_at': approvedAt?.toIso8601String(),
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
