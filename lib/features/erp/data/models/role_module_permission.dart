/// Model สำหรับ role_module_permissions (RBAC)
class RoleModulePermission {
  final String id;
  final String roleId;
  final String moduleName;
  final int accessLevel; // 0=None, 1=View, 2=Edit, 3=Full

  const RoleModulePermission({
    required this.id,
    required this.roleId,
    required this.moduleName,
    required this.accessLevel,
  });

  factory RoleModulePermission.fromJson(Map<String, dynamic> json) {
    return RoleModulePermission(
      id: json['id'] as String,
      roleId: json['role_id'] as String,
      moduleName: json['module_name'] as String,
      accessLevel: json['access_level'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role_id': roleId,
      'module_name': moduleName,
      'access_level': accessLevel,
    };
  }

  String get accessLevelLabel {
    switch (accessLevel) {
      case 0: return 'None';
      case 1: return 'View';
      case 2: return 'Edit';
      case 3: return 'Full';
      default: return 'Unknown';
    }
  }

  bool get canView => accessLevel >= 1;
  bool get canEdit => accessLevel >= 2;
  bool get canFull => accessLevel >= 3;
}
