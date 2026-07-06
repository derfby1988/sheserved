/// Model สำหรับ employees (HR Core)
class Employee {
  final String id;
  final String professionId;
  final String? userId;
  final String employeeCode;
  final String fullName;
  final String? email;
  final String? phone;
  final String? department;
  final String? jobTitle;
  final DateTime? hireDate;
  final double? salary;
  final double baseSalary;
  final double taxDeductibleExpenses;
  final double personalAllowance;
  final double providentFundRate;
  final String paymentMethod;
  final String? bankAccountNumber;
  final String? bankName;
  final double commissionRate;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Employee({
    required this.id,
    required this.professionId,
    this.userId,
    required this.employeeCode,
    required this.fullName,
    this.email,
    this.phone,
    this.department,
    this.jobTitle,
    this.hireDate,
    this.salary,
    this.baseSalary = 0,
    this.taxDeductibleExpenses = 0,
    this.personalAllowance = 60000,
    this.providentFundRate = 0.03,
    this.paymentMethod = 'bank_transfer',
    this.bankAccountNumber,
    this.bankName,
    this.commissionRate = 0,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Employee.fromJson(Map<String, dynamic> json) {
    return Employee(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      userId: json['user_id'] as String?,
      employeeCode: json['employee_code'] as String,
      fullName: json['full_name'] as String,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      department: json['department'] as String?,
      jobTitle: json['job_title'] as String?,
      hireDate: json['hire_date'] != null ? DateTime.parse(json['hire_date'] as String) : null,
      salary: (json['salary'] as num?)?.toDouble(),
      baseSalary: (json['base_salary'] as num?)?.toDouble() ?? 0,
      taxDeductibleExpenses: (json['tax_deductible_expenses'] as num?)?.toDouble() ?? 0,
      personalAllowance: (json['personal_allowance'] as num?)?.toDouble() ?? 60000,
      providentFundRate: (json['provident_fund_rate'] as num?)?.toDouble() ?? 0.03,
      paymentMethod: json['payment_method'] as String? ?? 'bank_transfer',
      bankAccountNumber: json['bank_account_number'] as String?,
      bankName: json['bank_name'] as String?,
      commissionRate: (json['commission_rate'] as num?)?.toDouble() ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'user_id': userId,
      'employee_code': employeeCode,
      'full_name': fullName,
      'email': email,
      'phone': phone,
      'department': department,
      'job_title': jobTitle,
      'hire_date': hireDate?.toIso8601String(),
      'salary': salary,
      'base_salary': baseSalary,
      'tax_deductible_expenses': taxDeductibleExpenses,
      'personal_allowance': personalAllowance,
      'provident_fund_rate': providentFundRate,
      'payment_method': paymentMethod,
      'bank_account_number': bankAccountNumber,
      'bank_name': bankName,
      'commission_rate': commissionRate,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
