/// ประเภทผู้ใช้งาน (ใช้เพื่อแยก Logic หน้าจอหลัก)
enum UserType {
  consumer, // ผู้ซื้อ/ผู้รับบริการ
  expert, // ผู้เชี่ยวชาญ/ผู้ขาย/สถานบริการ/ร้านค้า
  clinic, // คลินิก/ศูนย์ฯ
}

extension UserTypeExtension on UserType {
  String get value {
    switch (this) {
      case UserType.consumer:
        return 'consumer';
      case UserType.expert:
        return 'expert';
      case UserType.clinic:
        return 'clinic';
    }
  }

  String get displayName {
    switch (this) {
      case UserType.consumer:
        return 'ผู้ซื้อ/ผู้รับบริการ';
      case UserType.expert:
        return 'ผู้เชี่ยวชาญ/ผู้ขาย/ร้านค้า';
      case UserType.clinic:
        return 'คลินิก/ศูนย์ฯ';
    }
  }

  static UserType fromString(String value) {
    switch (value) {
      case 'consumer':
        return UserType.consumer;
      case 'expert':
        return UserType.expert;
      case 'clinic':
        return UserType.clinic;
      default:
        return UserType.consumer;
    }
  }
}

/// สถานะการยืนยันตัวตน
enum VerificationStatus {
  pending, // รอตรวจสอบ
  verified, // ยืนยันแล้ว
  rejected, // ถูกปฏิเสธ
}

extension VerificationStatusExtension on VerificationStatus {
  String get value {
    switch (this) {
      case VerificationStatus.pending:
        return 'pending';
      case VerificationStatus.verified:
        return 'verified';
      case VerificationStatus.rejected:
        return 'rejected';
    }
  }

  String get displayName {
    switch (this) {
      case VerificationStatus.pending:
        return 'รอตรวจสอบ';
      case VerificationStatus.verified:
        return 'ยืนยันแล้ว';
      case VerificationStatus.rejected:
        return 'ถูกปฏิเสธ';
    }
  }

  static VerificationStatus fromString(String value) {
    switch (value) {
      case 'pending':
        return VerificationStatus.pending;
      case 'verified':
        return VerificationStatus.verified;
      case 'rejected':
        return VerificationStatus.rejected;
      default:
        return VerificationStatus.pending;
    }
  }
}

/// User Model - ข้อมูลผู้ใช้หลัก
class UserModel {
  final String id;
  final String? professionId;
  final UserType userType;
  final String firstName;
  final String lastName;
  final String username;
  final String? phone;
  final String? profileImageUrl;
  final String? socialProvider; // google, facebook, apple, line
  final String? socialId;
  final String? passwordHash;
  final VerificationStatus verificationStatus;
  final bool isActive;
  final DateTime? lastLoginAt;
  final DateTime? lastSeenAt; // Real-time presence tracking
  final String availabilityStatus; // 'online', 'busy', 'offline'
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isThaiMhungEnabled; // ความสมัครใจในการรับแจ้งเหตุไทยมุง
  final int alertRadius; // รัศมีการแจ้งเตือน (เมตร)
  final bool isVolunteer; // สิทธิจิตอาสา (ดึงมาจาก Profession)
  /// รัศมีการรับแจ้งเตือนให้ทาง (เมตร) ค่าเริ่มต้น 1,000 ม.
  final int yieldWayRadius;
  /// ความสมัครใจในการรับแจ้งเตือนให้ทาง
  final bool isYieldWayEnabled;
  /// รายการ Profession IDs ที่อนุญาตให้เห็นวิดีโอต้นฉบับ (ไม่ผ่านการเบลอ)
  /// เช่น ['uuid-หมอ', 'uuid-พยาบาล'] → ช่างภาพและสถาปนิกจะยังเห็นแบบเบลออยู่
  final List<String> unblurredProfessionIds;

  /// ถือว่า online ถ้า last_seen_at อัปเดตภายใน 2 นาทีที่ผ่านมา
  bool get isOnline {
    if (lastSeenAt == null) return false;
    return DateTime.now().difference(lastSeenAt!).inMinutes < 2;
  }

  /// ตรวจสอบความเป็นอาสาสมัครเพื่อกรองการแจ้งเตือน
  bool get isProfessionalResponder => isVolunteer;

  const UserModel({
    required this.id,
    this.professionId,
    required this.userType,
    required this.firstName,
    required this.lastName,
    required this.username,
    this.passwordHash,
    this.phone,
    this.profileImageUrl,
    this.socialProvider,
    this.socialId,
    this.verificationStatus = VerificationStatus.pending,
    this.isActive = true,
    this.lastLoginAt,
    this.lastSeenAt,
    this.availabilityStatus = 'online',
    required this.createdAt,
    required this.updatedAt,
    this.isThaiMhungEnabled = true,
    this.alertRadius = 500,
    this.isVolunteer = false,
    this.yieldWayRadius = 1000,
    this.isYieldWayEnabled = false,
    this.unblurredProfessionIds = const [],
  });

  String get fullName => '$firstName $lastName';

  /// ตรวจสอบว่าเป็น Social Login หรือไม่
  bool get isSocialLogin => socialProvider != null && socialId != null;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'first_name': firstName,
      'last_name': lastName,
      'username': username,
      'password_hash': passwordHash,
      'phone': phone,
      'profile_image_url': profileImageUrl,
      'social_provider': socialProvider,
      'social_id': socialId,
      'verification_status': verificationStatus.value,
      'is_active': isActive,
      'last_login_at': lastLoginAt?.toIso8601String(),
      'last_seen_at': lastSeenAt?.toIso8601String(),
      'availability_status': availabilityStatus,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_thai_mhung_enabled': isThaiMhungEnabled,
      'alert_radius': alertRadius,
      'yield_way_radius': yieldWayRadius,
      'is_yield_way_enabled': isYieldWayEnabled,
      'unblurred_profession_ids': unblurredProfessionIds,
      // is_volunteer can be stored in metadata or handled during fetch
    };
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    // Derive UserType broadly, but UI will use Profession for exact category
    UserType type = UserType.consumer;
    if (json['user_type'] != null) {
      type = UserTypeExtension.fromString(json['user_type']);
    }

    return UserModel(
      id: json['id'],
      professionId: json['profession_id'],
      userType: type,
      firstName: json['first_name'] ?? '',
      lastName: json['last_name'] ?? '',
      username: json['username'],
      passwordHash: json['password_hash'],
      phone: json['phone'],
      profileImageUrl: json['profile_image_url'],
      socialProvider: json['social_provider'],
      socialId: json['social_id'],
      verificationStatus:
          VerificationStatusExtension.fromString(json['verification_status'] ?? 'pending'),
      isActive: json['is_active'] ?? true,
      lastLoginAt: json['last_login_at'] != null ? DateTime.parse(json['last_login_at']) : null,
      lastSeenAt: json['last_seen_at'] != null ? DateTime.parse(json['last_seen_at']) : null,
      availabilityStatus: json['availability_status'] ?? 'online',

      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      isThaiMhungEnabled: json['is_thai_mhung_enabled'] ?? true,
      alertRadius: json['alert_radius'] ?? 500,
      isVolunteer: json['is_volunteer'] ?? (json['professions']?['is_volunteer'] ?? false),
      yieldWayRadius: json['yield_way_radius'] ?? 1000,
      isYieldWayEnabled: json['is_yield_way_enabled'] ?? false,
      unblurredProfessionIds: json['unblurred_profession_ids'] != null
          ? List<String>.from(json['unblurred_profession_ids'])
          : [],
    );
  }

  UserModel copyWith({
    String? id,
    String? professionId,
    UserType? userType,
    String? firstName,
    String? lastName,
    String? username,
    String? phone,
    String? profileImageUrl,
    String? socialProvider,
    String? socialId,
    VerificationStatus? verificationStatus,
    bool? isActive,
    DateTime? lastLoginAt,
    DateTime? lastSeenAt,
    String? availabilityStatus,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isThaiMhungEnabled,
    int? alertRadius,
    bool? isVolunteer,
    int? yieldWayRadius,
    bool? isYieldWayEnabled,
    List<String>? unblurredProfessionIds,
  }) {
    return UserModel(
      id: id ?? this.id,
      professionId: professionId ?? this.professionId,
      userType: userType ?? this.userType,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      username: username ?? this.username,
      phone: phone ?? this.phone,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      socialProvider: socialProvider ?? this.socialProvider,
      socialId: socialId ?? this.socialId,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      isActive: isActive ?? this.isActive,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      availabilityStatus: availabilityStatus ?? this.availabilityStatus,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isThaiMhungEnabled: isThaiMhungEnabled ?? this.isThaiMhungEnabled,
      alertRadius: alertRadius ?? this.alertRadius,
      isVolunteer: isVolunteer ?? this.isVolunteer,
      yieldWayRadius: yieldWayRadius ?? this.yieldWayRadius,
      isYieldWayEnabled: isYieldWayEnabled ?? this.isYieldWayEnabled,
      unblurredProfessionIds: unblurredProfessionIds ?? this.unblurredProfessionIds,
    );
  }
}

/// Consumer Profile - ข้อมูลเพิ่มเติมสำหรับผู้ซื้อ/ผู้รับบริการ
class ConsumerProfile {
  final String id;
  final String userId;
  final DateTime? birthday;
  final String? address;
  final String? emergencyContact;
  final String? emergencyPhone;
  final Map<String, dynamic>? healthInfo;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ConsumerProfile({
    required this.id,
    required this.userId,
    this.birthday,
    this.address,
    this.emergencyContact,
    this.emergencyPhone,
    this.healthInfo,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'birthday': birthday?.toIso8601String(),
      'address': address,
      'emergency_contact': emergencyContact,
      'emergency_phone': emergencyPhone,
      'health_info': healthInfo,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory ConsumerProfile.fromJson(Map<String, dynamic> json) {
    return ConsumerProfile(
      id: json['id'],
      userId: json['user_id'],
      birthday: json['birthday'] != null ? DateTime.parse(json['birthday']) : null,
      address: json['address'],
      emergencyContact: json['emergency_contact'],
      emergencyPhone: json['emergency_phone'],
      healthInfo: json['health_info'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }
}

/// Expert Profile - ข้อมูลเพิ่มเติมสำหรับผู้เชี่ยวชาญ/ผู้ขาย/ร้านค้า
class ExpertProfile {
  final String id;
  final String userId;
  final String? businessName;
  final String? specialty;
  final int? experienceYears;
  final String? businessAddress;
  final String? businessPhone;
  final String? businessEmail;
  final String? description;
  final String? idCardImageUrl;
  final String? certificateImageUrl;
  final double? rating;
  final int reviewCount;
  final bool isAvailable;
  final VerificationStatus verificationStatus;
  final DateTime? lastSeenAt;
  final String availabilityStatus;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// ถือว่า online ถ้า last_seen_at อัปเดตภายใน 2 นาทีที่ผ่านมา และไม่อยู่ในสถานะ busy/offline
  bool get isOnline {
    if (lastSeenAt == null) return false;
    if (availabilityStatus == 'busy' || availabilityStatus == 'offline') return false;
    return DateTime.now().toUtc().difference(lastSeenAt!).inMinutes < 2;
  }

  bool get isBusy => availabilityStatus == 'busy';


  const ExpertProfile({
    required this.id,
    required this.userId,
    this.businessName,
    this.specialty,
    this.experienceYears,
    this.businessAddress,
    this.businessPhone,
    this.businessEmail,
    this.description,
    this.idCardImageUrl,
    this.certificateImageUrl,
    this.rating,
    this.reviewCount = 0,
    this.isAvailable = true,
    this.verificationStatus = VerificationStatus.pending,
    this.lastSeenAt,
    this.availabilityStatus = 'online',
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'business_name': businessName,
      'specialty': specialty,
      'experience_years': experienceYears,
      'business_address': businessAddress,
      'business_phone': businessPhone,
      'business_email': businessEmail,
      'description': description,
      'id_card_image_url': idCardImageUrl,
      'certificate_image_url': certificateImageUrl,
      'rating': rating,
      'review_count': reviewCount,
      'is_available': isAvailable,
      'last_seen_at': lastSeenAt?.toIso8601String(),
      'availability_status': availabilityStatus,
      // 'working_hours': workingHours, // not present in class
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory ExpertProfile.fromJson(Map<String, dynamic> json) {
    return ExpertProfile(
      id: json['id'],
      userId: json['user_id'],
      businessName: json['business_name'],
      specialty: json['specialty'],
      experienceYears: json['experience_years'],
      businessAddress: json['business_address'],
      businessPhone: json['business_phone'],
      businessEmail: json['business_email'],
      description: json['description'],
      idCardImageUrl: json['id_card_image_url'],
      certificateImageUrl: json['certificate_image_url'],
      rating: json['rating']?.toDouble(),
      reviewCount: json['review_count'] ?? 0,
      isAvailable: json['is_available'] ?? true,
      // workingHours: json['working_hours'], // not present in class
      verificationStatus: json['users'] != null && json['users']['verification_status'] != null
          ? VerificationStatusExtension.fromString(json['users']['verification_status'])
          : VerificationStatusExtension.fromString(json['verification_status'] ?? 'pending'),
      lastSeenAt: json['users'] != null && json['users']['last_seen_at'] != null
          ? DateTime.parse(json['users']['last_seen_at'])
          : (json['last_seen_at'] != null ? DateTime.parse(json['last_seen_at']) : null),
      availabilityStatus: json['users'] != null && json['users']['availability_status'] != null
          ? json['users']['availability_status']
          : (json['availability_status'] ?? 'online'),
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }
}

/// Clinic Profile - ข้อมูลเพิ่มเติมสำหรับคลินิก/ศูนย์ฯ
class ClinicProfile {
  final String id;
  final String userId;
  final String? clinicName;
  final String? licenseNumber;
  final String? serviceType;
  final String? businessAddress;
  final String? businessPhone;
  final String? businessEmail;
  final String? description;
  final String? businessImageUrl;
  final String? licenseImageUrl;
  final String? idCardImageUrl;
  final double? latitude;
  final double? longitude;
  final double? rating;
  final int reviewCount;
  final bool isOpen;
  final Map<String, dynamic>? workingHours;
  final List<String>? services;
  final DateTime? lastSeenAt;
  final String availabilityStatus;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// ถือว่า online ถ้า last_seen_at อัปเดตภายใน 2 นาทีที่ผ่านมา และไม่อยู่ในสถานะ busy/offline
  bool get isOnline {
    if (lastSeenAt == null) return false;
    if (availabilityStatus == 'busy' || availabilityStatus == 'offline') return false;
    return DateTime.now().toUtc().difference(lastSeenAt!).inMinutes < 2;
  }

  bool get isBusy => availabilityStatus == 'busy';


  const ClinicProfile({
    required this.id,
    required this.userId,
    this.clinicName,
    this.licenseNumber,
    this.serviceType,
    this.businessAddress,
    this.businessPhone,
    this.businessEmail,
    this.description,
    this.businessImageUrl,
    this.licenseImageUrl,
    this.idCardImageUrl,
    this.latitude,
    this.longitude,
    this.rating,
    this.reviewCount = 0,
    this.isOpen = true,
    this.workingHours,
    this.services,
    this.lastSeenAt,
    this.availabilityStatus = 'online',
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'clinic_name': clinicName,
      'license_number': licenseNumber,
      'service_type': serviceType,
      'business_address': businessAddress,
      'business_phone': businessPhone,
      'business_email': businessEmail,
      'description': description,
      'business_image_url': businessImageUrl,
      'license_image_url': licenseImageUrl,
      'id_card_image_url': idCardImageUrl,
      'latitude': latitude,
      'longitude': longitude,
      'rating': rating,
      'review_count': reviewCount,
      'is_open': isOpen,
      'working_hours': workingHours,
      'services': services,
      'last_seen_at': lastSeenAt?.toIso8601String(),
      'availability_status': availabilityStatus,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory ClinicProfile.fromJson(Map<String, dynamic> json) {
    return ClinicProfile(
      id: json['id'],
      userId: json['user_id'],
      clinicName: json['clinic_name'],
      licenseNumber: json['license_number'],
      serviceType: json['service_type'],
      businessAddress: json['business_address'],
      businessPhone: json['business_phone'],
      businessEmail: json['business_email'],
      description: json['description'],
      businessImageUrl: json['business_image_url'],
      licenseImageUrl: json['license_image_url'],
      idCardImageUrl: json['id_card_image_url'],
      latitude: json['latitude']?.toDouble(),
      longitude: json['longitude']?.toDouble(),
      rating: json['rating']?.toDouble(),
      reviewCount: json['review_count'] ?? 0,
      isOpen: json['is_open'] ?? true,
      workingHours: json['working_hours'],
      services: json['services'] != null ? List<String>.from(json['services']) : null,
      lastSeenAt: json['users'] != null && json['users']['last_seen_at'] != null
          ? DateTime.parse(json['users']['last_seen_at'])
          : (json['last_seen_at'] != null ? DateTime.parse(json['last_seen_at']) : null),
      availabilityStatus: json['users'] != null && json['users']['availability_status'] != null
          ? json['users']['availability_status']
          : (json['availability_status'] ?? 'online'),
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }
}
