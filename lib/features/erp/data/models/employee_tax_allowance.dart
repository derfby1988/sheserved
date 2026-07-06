class EmployeeTaxAllowance {
  final String id;
  final String professionId;
  final String employeeId;
  final String allowanceType;
  final double amount;
  final String? description;
  final int effectiveYear;
  final DateTime createdAt;

  const EmployeeTaxAllowance({
    required this.id,
    required this.professionId,
    required this.employeeId,
    required this.allowanceType,
    this.amount = 0,
    this.description,
    required this.effectiveYear,
    required this.createdAt,
  });

  factory EmployeeTaxAllowance.fromJson(Map<String, dynamic> json) {
    return EmployeeTaxAllowance(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      employeeId: json['employee_id'] as String,
      allowanceType: json['allowance_type'] as String,
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      description: json['description'] as String?,
      effectiveYear: json['effective_year'] as int? ?? DateTime.now().year,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'employee_id': employeeId,
      'allowance_type': allowanceType,
      'amount': amount,
      'description': description,
      'effective_year': effectiveYear,
      'created_at': createdAt.toIso8601String(),
    };
  }

  String get typeLabel {
    switch (allowanceType) {
      case 'personal':
        return 'ค่าลดหย่อนส่วนบุคคล';
      case 'spouse':
        return 'คู่สมรส';
      case 'child':
        return 'บุตร';
      case 'parent':
        return 'บิดามารดา';
      case 'insurance':
        return 'ประกันชีวิต';
      case 'donation':
        return 'เงินบริจาค';
      case 'housing':
        return 'ดอกเบี้ยเงินกู้บ้าน';
      case 'education':
        return 'ค่าเล่าเรียน';
      case 'disability':
        return 'ค่าลดหย่อนผู้พิการ';
      case 'other':
        return 'อื่นๆ';
      default:
        return allowanceType;
    }
  }
}
