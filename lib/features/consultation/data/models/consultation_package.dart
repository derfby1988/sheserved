class ConsultationPackage {
  final String id;
  String name;
  String shortName;
  String description;
  double price;
  bool includesAI;
  bool isActive;
  List<ExpertGroup> expertGroups;
  int displayOrder;
  int sessionMinutes;
  int expireMinutes;
  DateTime createdAt;
  DateTime updatedAt;

  ConsultationPackage({
    required this.id,
    required this.name,
    required this.shortName,
    this.description = '',
    required this.price,
    this.includesAI = false,
    this.isActive = true,
    this.expertGroups = const [],
    this.displayOrder = 0,
    this.sessionMinutes = 15,
    this.expireMinutes = 120,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ConsultationPackage.fromJson(Map<String, dynamic> json) {
    var groupsRaw = json['expert_groups'];
    List<ExpertGroup> groups = [];
    if (groupsRaw is List) {
      groups = groupsRaw.map((g) => ExpertGroup.fromJson(Map<String, dynamic>.from(g))).toList();
    }
    
    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    int parseInt(dynamic value) {
      if (value == null) return 0;
      if (value is int) return value;
      if (value is double) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    return ConsultationPackage(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      shortName: json['short_name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      price: parseDouble(json['price']),
      includesAI: json['includes_ai'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
      expertGroups: groups,
      displayOrder: parseInt(json['display_order']),
      sessionMinutes: parseInt(json['session_minutes']) != 0 ? parseInt(json['session_minutes']) : 15,
      expireMinutes: parseInt(json['expire_minutes']) != 0 ? parseInt(json['expire_minutes']) : 120,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : DateTime.now(),
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at'] as String) : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'short_name': shortName,
    'description': description,
    'price': price,
    'includes_ai': includesAI,
    'is_active': isActive,
    'expert_groups': expertGroups.map((g) => g.toJson()).toList(),
    'display_order': displayOrder,
    'session_minutes': sessionMinutes,
    'expire_minutes': expireMinutes,
    'updated_at': updatedAt.toIso8601String(),
  };
}

class ExpertGroup {
  String id;
  String name;
  String role; // e.g. 'doctor', 'professor', 'pharmacist'
  int maxExperts; // -1 = unlimited
  bool isRequired;
  String? icon; // Material icon name, e.g. 'medical_services'

  ExpertGroup({
    required this.id,
    required this.name,
    required this.role,
    this.maxExperts = -1,
    this.isRequired = false,
    this.icon,
  });

  factory ExpertGroup.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value) {
      if (value == null) return 0;
      if (value is int) return value;
      if (value is double) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    return ExpertGroup(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      role: json['role'] as String? ?? '',
      maxExperts: parseInt(json['maxExperts'] ?? json['max_experts'] ?? -1),
      isRequired: json['isRequired'] == true || json['is_required'] == true,
      icon: json['icon'] as String? ?? json['group_icon'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'role': role,
    'maxExperts': maxExperts,
    'isRequired': isRequired,
    'icon': icon,
  };
}
