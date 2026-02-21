/// ประเภทผู้ใช้งาน
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
  final DateTime createdAt;
  final DateTime updatedAt;

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
    required this.createdAt,
    required this.updatedAt,
  });

  String get fullName => '$firstName $lastName';

  /// ตรวจสอบว่าเป็น Social Login หรือไม่
  bool get isSocialLogin => socialProvider != null && socialId != null;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      // Note: user_type removed from DB but kept in Model for app logic
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
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    // Derive UserType from profession_id if user_type is missing
    UserType derivedType = UserType.consumer;
    if (json['user_type'] != null) {
      derivedType = UserTypeExtension.fromString(json['user_type']);
    } else if (json['profession_id'] != null) {
      final pId = json['profession_id'].toString();
      if (pId == '00000000-0000-0000-0000-000000000002') {
        derivedType = UserType.expert;
      } else if (pId == '00000000-0000-0000-0000-000000000003') {
        derivedType = UserType.clinic;
      } else {
        derivedType = UserType.consumer;
      }
    }

    return UserModel(
      id: json['id'],
      professionId: json['profession_id'],
      userType: derivedType,
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
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  UserModel copyWith({
    String? id,
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
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserModel(
      id: id ?? this.id,
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
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
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
  final DateTime createdAt;
  final DateTime updatedAt;

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
  final DateTime createdAt;
  final DateTime updatedAt;

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
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }
}
