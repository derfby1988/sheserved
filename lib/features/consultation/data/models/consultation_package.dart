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
    required this.createdAt,
    required this.updatedAt,
  });

  factory ConsultationPackage.fromJson(Map<String, dynamic> json) {
    var groupsRaw = json['expert_groups'];
    List<ExpertGroup> groups = [];
    if (groupsRaw is List) {
      groups = groupsRaw.map((g) => ExpertGroup.fromJson(Map<String, dynamic>.from(g))).toList();
    } else if (groupsRaw is String) {
       // Handle case where it might be a JSON string from Supabase (though usually it's parsed if using supabase_flutter)
       // But usually it's already a List or Map.
    }
    
    return ConsultationPackage(
      id: json['id'] as String,
      name: json['name'] as String,
      shortName: json['short_name'] as String,
      description: json['description'] as String? ?? '',
      price: (json['price'] as num).toDouble(),
      includesAI: json['includes_ai'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
      expertGroups: groups,
      displayOrder: json['display_order'] as int? ?? 0,
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
    'updated_at': updatedAt.toIso8601String(),
  };
}

class ExpertGroup {
  String id;
  String name;
  String role; // e.g. 'doctor', 'professor', 'pharmacist'
  int maxExperts; // -1 = unlimited
  bool isRequired;

  ExpertGroup({
    required this.id,
    required this.name,
    required this.role,
    this.maxExperts = -1,
    this.isRequired = false,
  });

  factory ExpertGroup.fromJson(Map<String, dynamic> json) => ExpertGroup(
    id: json['id'] as String,
    name: json['name'] as String,
    role: json['role'] as String,
    maxExperts: json['maxExperts'] as int? ?? -1,
    isRequired: json['isRequired'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'role': role,
    'maxExperts': maxExperts,
    'isRequired': isRequired,
  };
}
