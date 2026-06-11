/// Model สำหรับ customers (CRM)
class Customer {
  final String id;
  final String professionId;
  final String? userId;
  final String? customerCode;
  final String customerType;
  final String displayName;
  final String? phone;
  final String? email;
  final DateTime? birthday;
  final String? notes;
  final String? loyaltyTierId;
  final int totalPoints;
  final double lifetimeValue;
  final int visitCount;
  final DateTime? lastVisitAt;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Customer({
    required this.id,
    required this.professionId,
    this.userId,
    this.customerCode,
    this.customerType = 'walk_in',
    required this.displayName,
    this.phone,
    this.email,
    this.birthday,
    this.notes,
    this.loyaltyTierId,
    this.totalPoints = 0,
    this.lifetimeValue = 0,
    this.visitCount = 0,
    this.lastVisitAt,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      userId: json['user_id'] as String?,
      customerCode: json['customer_code'] as String?,
      customerType: json['customer_type'] as String? ?? 'walk_in',
      displayName: json['display_name'] as String,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      birthday: json['birthday'] != null ? DateTime.parse(json['birthday'] as String) : null,
      notes: json['notes'] as String?,
      loyaltyTierId: json['loyalty_tier_id'] as String?,
      totalPoints: json['total_points'] as int? ?? 0,
      lifetimeValue: (json['lifetime_value'] as num?)?.toDouble() ?? 0,
      visitCount: json['visit_count'] as int? ?? 0,
      lastVisitAt: json['last_visit_at'] != null ? DateTime.parse(json['last_visit_at'] as String) : null,
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
      'customer_code': customerCode,
      'customer_type': customerType,
      'display_name': displayName,
      'phone': phone,
      'email': email,
      'birthday': birthday?.toIso8601String(),
      'notes': notes,
      'loyalty_tier_id': loyaltyTierId,
      'total_points': totalPoints,
      'lifetime_value': lifetimeValue,
      'visit_count': visitCount,
      'last_visit_at': lastVisitAt?.toIso8601String(),
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  String get customerTypeLabel {
    switch (customerType) {
      case 'walk_in': return 'Walk-in';
      case 'member': return 'Member';
      case 'corporate': return 'Corporate';
      case 'vip': return 'VIP';
      default: return customerType;
    }
  }
}
