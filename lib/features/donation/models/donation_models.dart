
enum DonationApprovalStatus {
  pending_local,
  pending_storage,
  active,
  rejected;

  static DonationApprovalStatus fromString(String? status) {
    return DonationApprovalStatus.values.firstWhere(
      (e) => e.name == status,
      orElse: () => DonationApprovalStatus.pending_local,
    );
  }
}

class DonationCategoryField {
  final String id;
  final String label;
  final String type; // 'text', 'number', 'long_text', 'date'
  final bool isRequired;

  const DonationCategoryField({
    required this.id,
    required this.label,
    required this.type,
    this.isRequired = false,
  });

  factory DonationCategoryField.fromJson(Map<String, dynamic> json) {
    return DonationCategoryField(
      id: json['id'] ?? '',
      label: json['label'] ?? '',
      type: json['type'] ?? 'text',
      isRequired: json['is_required'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'type': type,
      'is_required': isRequired,
    };
  }
}


/// หมวดหมู่การบริจาค/ขอความช่วยเหลือ
class DonationCategory {
  final String id;
  final String name;
  final String? nameEn;
  final String? iconName;
  final bool isEmergency;
  final int displayOrder;
  final List<String> volunteerProfessionIds;
  final List<DonationCategoryField> customFields;

  const DonationCategory({
    required this.id,
    required this.name,
    this.nameEn,
    this.iconName,
    this.isEmergency = false,
    this.displayOrder = 0,
    this.volunteerProfessionIds = const [],
    this.customFields = const [],
  });

  factory DonationCategory.fromJson(Map<String, dynamic> json) {
    List<DonationCategoryField> fields = [];
    if (json['custom_fields'] != null) {
      final list = json['custom_fields'] as List;
      fields = list.map((e) => DonationCategoryField.fromJson(e)).toList();
    }

    List<String> volunteerIds = [];
    if (json['volunteer_profession_ids'] != null) {
      if (json['volunteer_profession_ids'] is List) {
        volunteerIds = List<String>.from(json['volunteer_profession_ids']);
      }
    }

    return DonationCategory(
      id: json['id'],
      name: json['name'] ?? '',
      nameEn: json['name_en'],
      iconName: json['icon_name'],
      isEmergency: json['is_emergency'] ?? false,
      displayOrder: (json['display_order'] is num)
          ? (json['display_order'] as num).toInt()
          : int.tryParse(json['display_order']?.toString() ?? '0') ?? 0,
      volunteerProfessionIds: volunteerIds,
      customFields: fields,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'name_en': nameEn,
      'icon_name': iconName,
      'is_emergency': isEmergency,
      'display_order': displayOrder,
      'volunteer_profession_ids': volunteerProfessionIds,
      'custom_fields': customFields.map((e) => e.toJson()).toList(),
    };
  }
}

/// คำร้องขอรับบริจาค/ความช่วยเหลือ
class DonationRequest {
  final String id;
  final String? userId;
  final String categoryId;
  final String title;
  final String? description;
  final double? targetAmount;
  final double currentAmount;
  final String? imageUrl;
  final bool isTrending;
  final String status;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DonationApprovalStatus approvalStatus;
  final String? storageApprovedBy;
  final DateTime? neededDate;
  final String? usageLocation;
  final String? requesterAddress;
  final String? localLeaderId;
  final String? communityId;
  final DateTime? localVerifiedAt;
  final Map<String, dynamic> customData;

  const DonationRequest({
    required this.id,
    this.userId,
    required this.categoryId,
    required this.title,
    this.description,
    this.targetAmount,
    this.currentAmount = 0,
    this.imageUrl,
    this.isTrending = false,
    this.status = 'active',
    required this.createdAt,
    this.updatedAt,
    this.approvalStatus = DonationApprovalStatus.pending_local,
    this.storageApprovedBy,
    this.neededDate,
    this.usageLocation,
    this.requesterAddress,
    this.localLeaderId,
    this.communityId,
    this.localVerifiedAt,
    this.customData = const {},
  });

  factory DonationRequest.fromJson(Map<String, dynamic> json) {
    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    return DonationRequest(
      id: json['id'],
      userId: json['user_id'],
      categoryId: json['category_id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'],
      targetAmount: json['target_amount'] != null ? parseDouble(json['target_amount']) : null,
      currentAmount: parseDouble(json['current_amount']),
      imageUrl: json['image_url'],
      isTrending: json['is_trending'] ?? false,
      status: json['status'] ?? 'active',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : null,
      approvalStatus: DonationApprovalStatus.fromString(json['approval_status'] ?? 'pending_local'),
      storageApprovedBy: json['storage_approved_by'],
      neededDate: json['needed_date'] != null ? DateTime.parse(json['needed_date']) : null,
      usageLocation: json['usage_location'],
      requesterAddress: json['requester_address'],
      localLeaderId: json['local_leader_id'],
      communityId: json['community_id'],
      localVerifiedAt: json['local_verified_at'] != null ? DateTime.parse(json['local_verified_at']) : null,
      customData: json['custom_data'] as Map<String, dynamic>? ?? {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'category_id': categoryId,
      'title': title,
      'description': description,
      'target_amount': targetAmount,
      'current_amount': currentAmount,
      'image_url': imageUrl,
      'is_trending': isTrending,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'approval_status': approvalStatus.name,
      'storage_approved_by': storageApprovedBy,
      'needed_date': neededDate?.toIso8601String(),
      'usage_location': usageLocation,
      'requester_address': requesterAddress,
      'local_leader_id': localLeaderId,
      'community_id': communityId,
      'local_verified_at': localVerifiedAt?.toIso8601String(),
      'custom_data': customData,
    };
  }

  double get progress {
    if (targetAmount != null && targetAmount! > 0) {
      return currentAmount / targetAmount!;
    }
    return 0.0;
  }

  double get remainingAmount {
    if (targetAmount == null) return 0;
    return (targetAmount! - currentAmount).clamp(0, double.infinity);
  }
}

/// สถิติภาพรวมของการขอรับบริจาค
class DonationStats {
  final double requested;
  final double received;
  final double remaining;

  const DonationStats({
    required this.requested,
    required this.received,
    required this.remaining,
  });
}

