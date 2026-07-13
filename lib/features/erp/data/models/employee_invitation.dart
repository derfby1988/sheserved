/// Model สำหรับ employee_invitations (คำเชิญพนักงาน)
class EmployeeInvitation {
  final String id;
  final String professionId;
  final String invitedBy;
  final String? userId;
  final String? email;
  final String? phone;
  final String fullName;
  final String? employeeCode;
  final String? department;
  final String? jobTitle;
  final String? branchId;
  final double? baseSalary;
  final double? salary;
  final double? commissionRate;
  final double? providentFundRate;
  final double? personalAllowance;
  final double? taxDeductibleExpenses;
  final String? paymentMethod;
  final String? bankName;
  final String? bankAccountNumber;
  final String status;
  final String token;
  final String? rejectionReason;
  final DateTime? rejectedAt;
  final DateTime? expiresAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const EmployeeInvitation({
    required this.id,
    required this.professionId,
    required this.invitedBy,
    this.userId,
    this.email,
    this.phone,
    required this.fullName,
    this.employeeCode,
    this.department,
    this.jobTitle,
    this.branchId,
    this.baseSalary,
    this.salary,
    this.commissionRate,
    this.providentFundRate,
    this.personalAllowance,
    this.taxDeductibleExpenses,
    this.paymentMethod,
    this.bankName,
    this.bankAccountNumber,
    required this.status,
    required this.token,
    this.rejectionReason,
    this.rejectedAt,
    this.expiresAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory EmployeeInvitation.fromJson(Map<String, dynamic> json) {
    return EmployeeInvitation(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      invitedBy: json['invited_by'] as String,
      userId: json['user_id'] as String?,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      fullName: json['full_name'] as String,
      employeeCode: json['employee_code'] as String?,
      department: json['department'] as String?,
      jobTitle: json['job_title'] as String?,
      branchId: json['branch_id'] as String?,
      baseSalary: (json['base_salary'] as num?)?.toDouble(),
      salary: (json['salary'] as num?)?.toDouble(),
      commissionRate: (json['commission_rate'] as num?)?.toDouble(),
      providentFundRate: (json['provident_fund_rate'] as num?)?.toDouble(),
      personalAllowance: (json['personal_allowance'] as num?)?.toDouble(),
      taxDeductibleExpenses: (json['tax_deductible_expenses'] as num?)?.toDouble(),
      paymentMethod: json['payment_method'] as String?,
      bankName: json['bank_name'] as String?,
      bankAccountNumber: json['bank_account_number'] as String?,
      status: json['status'] as String,
      token: json['token'] as String,
      rejectionReason: json['rejection_reason'] as String?,
      rejectedAt: json['rejected_at'] != null ? DateTime.parse(json['rejected_at'] as String) : null,
      expiresAt: json['expires_at'] != null ? DateTime.parse(json['expires_at'] as String) : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'invited_by': invitedBy,
      'user_id': userId,
      'email': email,
      'phone': phone,
      'full_name': fullName,
      'employee_code': employeeCode,
      'department': department,
      'job_title': jobTitle,
      'branch_id': branchId,
      'base_salary': baseSalary,
      'salary': salary,
      'commission_rate': commissionRate,
      'provident_fund_rate': providentFundRate,
      'personal_allowance': personalAllowance,
      'tax_deductible_expenses': taxDeductibleExpenses,
      'payment_method': paymentMethod,
      'bank_name': bankName,
      'bank_account_number': bankAccountNumber,
      'status': status,
      'token': token,
      'rejection_reason': rejectionReason,
      'rejected_at': rejectedAt?.toIso8601String(),
      'expires_at': expiresAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isRejected => status == 'rejected';
  bool get isExpired => status == 'expired';
  bool get isExpiredDate => expiresAt != null && expiresAt!.isBefore(DateTime.now());
}
