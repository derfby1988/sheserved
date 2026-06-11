/// Model สำหรับ employee_roles (RBAC)
class EmployeeRole {
  final String id;
  final String professionId;
  final String? branchId;
  final String userId;
  final String roleId;
  final DateTime assignedAt;
  final String? assignedBy;
  final bool isActive;

  const EmployeeRole({
    required this.id,
    required this.professionId,
    this.branchId,
    required this.userId,
    required this.roleId,
    required this.assignedAt,
    this.assignedBy,
    this.isActive = true,
  });

  factory EmployeeRole.fromJson(Map<String, dynamic> json) {
    return EmployeeRole(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      branchId: json['branch_id'] as String?,
      userId: json['user_id'] as String,
      roleId: json['role_id'] as String,
      assignedAt: DateTime.parse(json['assigned_at'] as String),
      assignedBy: json['assigned_by'] as String?,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'branch_id': branchId,
      'user_id': userId,
      'role_id': roleId,
      'assigned_at': assignedAt.toIso8601String(),
      'assigned_by': assignedBy,
      'is_active': isActive,
    };
  }
}
