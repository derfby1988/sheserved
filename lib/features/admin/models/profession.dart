/// หมวดหมู่หลักของผู้ใช้ (Dynamic Model)
class UserCategory {
  final String id;
  final String name;
  final String? nameEn;
  final String? description;
  final String? iconName;
  final int displayOrder;
  final bool isActive;

  const UserCategory({
    required this.id,
    required this.name,
    this.nameEn,
    this.description,
    this.iconName,
    this.displayOrder = 0,
    this.isActive = true,
  });

  /// ค่าคงที่สำหรับหมวดหมู่หลัก (เพื่อความปลอดภัยในการอ้างอิงโค้ดส่วนอื่น)
  static const String consumerId = 'consumer';
  static const String providerId = 'provider';
  static const String localLeaderId = 'local_leader';

  static const UserCategory consumer = UserCategory(
    id: consumerId,
    name: 'ผู้ซื้อ/ผู้รับบริการ',
  );

  static const UserCategory provider = UserCategory(
    id: providerId,
    name: 'ผู้ให้บริการ',
  );

  static const UserCategory localLeader = UserCategory(
    id: localLeaderId,
    name: 'ผู้นำชุมชน',
    nameEn: 'Local Leader',
    iconName: 'gavel',
  );

  String get value => id;
  String get displayName => name;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'name_en': nameEn,
      'description': description,
      'icon_name': iconName,
      'display_order': displayOrder,
      'is_active': isActive,
    };
  }

  factory UserCategory.fromJson(Map<String, dynamic> json) {
    return UserCategory(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      nameEn: json['name_en'],
      description: json['description'],
      iconName: json['icon_name'],
      displayOrder: json['display_order'] ?? 0,
      isActive: json['is_active'] ?? true,
    );
  }

  UserCategory copyWith({
    String? id,
    String? name,
    String? nameEn,
    String? description,
    String? iconName,
    int? displayOrder,
    bool? isActive,
  }) {
    return UserCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      nameEn: nameEn ?? this.nameEn,
      description: description ?? this.description,
      iconName: iconName ?? this.iconName,
      displayOrder: displayOrder ?? this.displayOrder,
      isActive: isActive ?? this.isActive,
    );
  }

  /// แปลงจาก String (สำหรับความเข้ากันได้กับข้อมูลเดิม)
  static UserCategory fromString(String value) {
    if (value == consumerId || value == 'consumer') {
      return const UserCategory(id: consumerId, name: 'Consumer');
    } else if (value == providerId || value == 'provider') {
      return const UserCategory(id: providerId, name: 'Provider');
    } else if (value == localLeaderId || value == 'local_leader') {
      return const UserCategory(id: localLeaderId, name: 'Local Leader');
    }
    return UserCategory(id: value, name: value);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserCategory &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}


/// สถานะการยืนยัน
enum VerificationStatus {
  pending,   // รอตรวจสอบ
  approved,  // อนุมัติแล้ว
  rejected,  // ถูกปฏิเสธ
}

extension VerificationStatusExtension on VerificationStatus {
  String get value {
    switch (this) {
      case VerificationStatus.pending:
        return 'pending';
      case VerificationStatus.approved:
        return 'approved';
      case VerificationStatus.rejected:
        return 'rejected';
    }
  }

  String get displayName {
    switch (this) {
      case VerificationStatus.pending:
        return 'รอตรวจสอบ';
      case VerificationStatus.approved:
        return 'อนุมัติแล้ว';
      case VerificationStatus.rejected:
        return 'ถูกปฏิเสธ';
    }
  }

  static VerificationStatus fromString(String value) {
    switch (value) {
      case 'pending':
        return VerificationStatus.pending;
      case 'approved':
        return VerificationStatus.approved;
      case 'rejected':
        return VerificationStatus.rejected;
      default:
        return VerificationStatus.pending;
    }
  }
}

/// Model สำหรับอาชีพ
class Profession {
  final String id;
  final String name;
  final String? nameEn;
  final String? description;
  final String? iconName;
  final UserCategory category;
  final bool isBuiltIn; // true = ห้ามลบ (consumer, expert, clinic)
  final bool isActive;
  final bool isVolunteer; // สามารถเป็นอาสาสมัครลงพื้นที่ช่วยเหลือได้
  final bool requiresVerification; // ต้องตรวจสอบก่อนใช้งาน
  final int displayOrder;
  final int fieldCount; // จำนวน fields (calculated)
  final int memberCount; // จำนวนสมาชิกทั้งหมด (calculated)
  final String? colorHex; // Hex color string (e.g. #FF0000)
  final DateTime createdAt;
  final DateTime updatedAt;

  const Profession({
    required this.id,
    required this.name,
    this.nameEn,
    this.description,
    this.iconName,
    this.colorHex,
    required this.category,
    this.isBuiltIn = false,
    this.isActive = true,
    this.isVolunteer = false,
    this.requiresVerification = true,
    this.displayOrder = 0,
    this.fieldCount = 0,
    this.memberCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Built-in professions
  static const String consumerProfessionId = '00000000-0000-0000-0000-000000000001';
  static const String expertProfessionId = '00000000-0000-0000-0000-000000000002';
  static const String clinicProfessionId = '00000000-0000-0000-0000-000000000003';

  /// ค่าเริ่มต้นสำหรับ Built-in professions
  static List<Profession> get defaultProfessions {
    final now = DateTime.now();
    return [
      Profession(
        id: consumerProfessionId,
        name: 'ผู้ซื้อ/ผู้รับบริการ',
        nameEn: 'Consumer',
        description: 'ผู้ใช้ทั่วไปที่ต้องการซื้อสินค้าหรือรับบริการ',
        iconName: 'shopping_cart',
        colorHex: '#2196F3', // Blue
        category: UserCategory.consumer,
        isBuiltIn: true,
        isActive: true,
        isVolunteer: false,
        requiresVerification: false,
        displayOrder: 0,
        createdAt: now,
        updatedAt: now,
      ),
      Profession(
        id: expertProfessionId,
        name: 'ผู้เชี่ยวชาญ/ผู้ขาย/ร้านค้า',
        nameEn: 'Expert/Seller',
        description: 'ผู้เชี่ยวชาญ ผู้ขายสินค้า หรือเจ้าของร้านค้า',
        iconName: 'store',
        colorHex: '#FF9800', // Orange
        category: UserCategory.provider,
        isBuiltIn: true,
        isActive: true,
        isVolunteer: false,
        requiresVerification: true,
        displayOrder: 1,
        createdAt: now,
        updatedAt: now,
      ),
      Profession(
        id: clinicProfessionId,
        name: 'คลินิก/ศูนย์',
        nameEn: 'Clinic/Center',
        description: 'คลินิก ศูนย์บริการ หรือสถานประกอบการ',
        iconName: 'local_hospital',
        colorHex: '#E91E63', // Pink
        category: UserCategory.provider,
        isBuiltIn: true,
        isActive: true,
        isVolunteer: false,
        requiresVerification: true,
        displayOrder: 2,
        createdAt: now,
        updatedAt: now,
      ),
    ];
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'name_en': nameEn,
      'description': description,
      'icon_name': iconName,
      'category': category.value,
      'is_built_in': isBuiltIn,
      'is_active': isActive,
      'is_volunteer': isVolunteer,
      'requires_verification': requiresVerification,
      'display_order': displayOrder,
      'color_hex': colorHex,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Profession.fromJson(Map<String, dynamic> json) {
    UserCategory category;
    if (json['category_data'] != null) {
      category = UserCategory.fromJson(json['category_data']);
    } else {
      category = UserCategory.fromString(json['category'] ?? 'consumer');
    }

    return Profession(
      id: json['id'],
      name: json['name'],
      nameEn: json['name_en'],
      description: json['description'],
      iconName: json['icon_name'],
      category: category,
      isBuiltIn: json['is_built_in'] ?? false,
      isActive: json['is_active'] ?? true,
      isVolunteer: json['is_volunteer'] ?? false,
      requiresVerification: json['requires_verification'] ?? true,
      displayOrder: json['display_order'] ?? 0,
      colorHex: json['color_hex'],
      fieldCount: json['field_count'] ?? 0,
      memberCount: json['member_count'] ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : DateTime.now(),
    );
  }


  Profession copyWith({
    String? id,
    String? name,
    String? nameEn,
    String? description,
    String? iconName,
    UserCategory? category,
    bool? isBuiltIn,
    bool? isActive,
    bool? isVolunteer,
    bool? requiresVerification,
    int? displayOrder,
    String? colorHex,
    int? fieldCount,
    int? memberCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Profession(
      id: id ?? this.id,
      name: name ?? this.name,
      nameEn: nameEn ?? this.nameEn,
      description: description ?? this.description,
      iconName: iconName ?? this.iconName,
      category: category ?? this.category,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      isActive: isActive ?? this.isActive,
      isVolunteer: isVolunteer ?? this.isVolunteer,
      requiresVerification: requiresVerification ?? this.requiresVerification,
      displayOrder: displayOrder ?? this.displayOrder,
      colorHex: colorHex ?? this.colorHex,
      fieldCount: fieldCount ?? this.fieldCount,
      memberCount: memberCount ?? this.memberCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Model สำหรับผู้สมัครที่รอตรวจสอบ
class RegistrationApplication {
  final String id;
  final String oderId;
  final String professionId;
  final Profession? profession;
  final String firstName;
  final String lastName;
  final String username;
  final String? phone;
  final String? profileImageUrl;
  final Map<String, dynamic> registrationData; // Dynamic fields data
  final VerificationStatus status;
  final String? reviewNote;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const RegistrationApplication({
    required this.id,
    required this.oderId,
    required this.professionId,
    this.profession,
    required this.firstName,
    required this.lastName,
    required this.username,
    this.phone,
    this.profileImageUrl,
    this.registrationData = const {},
    this.status = VerificationStatus.pending,
    this.reviewNote,
    this.reviewedBy,
    this.reviewedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  String get fullName => '$firstName $lastName';

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': oderId,
      'profession_id': professionId,
      'first_name': firstName,
      'last_name': lastName,
      'username': username,
      'phone': phone,
      'profile_image_url': profileImageUrl,
      'registration_data': registrationData,
      'status': status.value,
      'review_note': reviewNote,
      'reviewed_by': reviewedBy,
      'reviewed_at': reviewedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory RegistrationApplication.fromJson(Map<String, dynamic> json) {
    return RegistrationApplication(
      id: json['id'],
      oderId: json['user_id'],
      professionId: json['profession_id'],
      profession: json['profession'] != null
          ? Profession.fromJson(json['profession'])
          : null,
      firstName: json['first_name'] ?? '',
      lastName: json['last_name'] ?? '',
      username: json['username'] ?? '',
      phone: json['phone'],
      profileImageUrl: json['profile_image_url'],
      registrationData: json['registration_data'] ?? {},
      status: VerificationStatusExtension.fromString(json['status'] ?? 'pending'),
      reviewNote: json['review_note'],
      reviewedBy: json['reviewed_by'],
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.parse(json['reviewed_at'])
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : DateTime.now(),
    );
  }
}
