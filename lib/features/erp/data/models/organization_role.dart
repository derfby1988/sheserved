/// Model สำหรับ organization_roles (RBAC)
class OrganizationRole {
  final String id;
  final String professionId;
  final String roleName;
  final String? roleDescription;
  final bool isSystemRole;
  final DateTime createdAt;
  final DateTime updatedAt;

  const OrganizationRole({
    required this.id,
    required this.professionId,
    required this.roleName,
    this.roleDescription,
    this.isSystemRole = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory OrganizationRole.fromJson(Map<String, dynamic> json) {
    return OrganizationRole(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      roleName: json['role_name'] as String,
      roleDescription: json['role_description'] as String?,
      isSystemRole: json['is_system_role'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'role_name': roleName,
      'role_description': roleDescription,
      'is_system_role': isSystemRole,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  OrganizationRole copyWith({
    String? id,
    String? professionId,
    String? roleName,
    String? roleDescription,
    bool? isSystemRole,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return OrganizationRole(
      id: id ?? this.id,
      professionId: professionId ?? this.professionId,
      roleName: roleName ?? this.roleName,
      roleDescription: roleDescription ?? this.roleDescription,
      isSystemRole: isSystemRole ?? this.isSystemRole,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
