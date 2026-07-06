class PayrollItem {
  final String id;
  final String professionId;
  final String payrollRunId;
  final String employeeId;
  final String itemType;
  final double amount;
  final bool isEarning;
  final bool isEmployerCost;
  final String? notes;
  final String? referenceId;
  final String? referenceType;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PayrollItem({
    required this.id,
    required this.professionId,
    required this.payrollRunId,
    required this.employeeId,
    required this.itemType,
    required this.amount,
    this.isEarning = true,
    this.isEmployerCost = false,
    this.notes,
    this.referenceId,
    this.referenceType,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PayrollItem.fromJson(Map<String, dynamic> json) {
    return PayrollItem(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      payrollRunId: json['payroll_run_id'] as String,
      employeeId: json['employee_id'] as String,
      itemType: json['item_type'] as String,
      amount: (json['amount'] as num).toDouble(),
      isEarning: json['is_earning'] as bool? ?? true,
      isEmployerCost: (json['item_type'] as String?)?.contains('employer') ?? false,
      notes: json['notes'] as String?,
      referenceId: json['reference_id'] as String?,
      referenceType: json['reference_type'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'payroll_run_id': payrollRunId,
      'employee_id': employeeId,
      'item_type': itemType,
      'amount': amount,
      'is_earning': isEarning,
      'notes': notes,
      'reference_id': referenceId,
      'reference_type': referenceType,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  String get itemLabel {
    switch (itemType) {
      case 'base_salary':
        return 'เงินเดือนพื้นฐาน';
      case 'commission':
        return 'คอมมิชชั่น';
      case 'overtime':
        return 'ล่วงเวลา (OT)';
      case 'diligence_allowance':
        return 'เบี้ยขยัน';
      case 'bonus':
        return 'โบนัส';
      case 'allowance':
        return 'เงินเพิ่ม';
      case 'deduction':
        return 'รายการหัก';
      case 'social_security':
        return 'ประกันสังคม';
      case 'social_security_employer':
        return 'ประกันสังคม (นายจ้าง)';
      case 'provident_fund_employee':
        return 'กองทุนสำรองเลี้ยงชีพ (พนักงาน)';
      case 'provident_fund_employer':
        return 'กองทุนสำรองเลี้ยงชีพ (นายจ้าง)';
      case 'tax':
        return 'ภาษีเงินได้หัก ณ ที่จ่าย';
      case 'late_penalty':
        return 'หักสาย';
      case 'absent_penalty':
        return 'หักขาด';
      case 'other':
        return 'อื่นๆ';
      default:
        return itemType;
    }
  }
}
