/// Model สำหรับหมวดหมู่ยาอันตรายย่อย (dangerous_drug_subcategories)
class DangerousDrugSubcategory {
  final String id;
  final String code;
  final String nameTh;
  final String? nameEn;
  final String? description;
  final bool isTelemedicineProhibited;
  final int sortOrder;
  final bool isActive;
  final DateTime? deletedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DangerousDrugSubcategory({
    required this.id,
    required this.code,
    required this.nameTh,
    this.nameEn,
    this.description,
    this.isTelemedicineProhibited = false,
    this.sortOrder = 0,
    this.isActive = true,
    this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DangerousDrugSubcategory.fromJson(Map<String, dynamic> json) {
    return DangerousDrugSubcategory(
      id: json['id'] as String,
      code: json['code'] as String,
      nameTh: json['name_th'] as String,
      nameEn: json['name_en'] as String?,
      description: json['description'] as String?,
      isTelemedicineProhibited: json['is_telemedicine_prohibited'] as bool? ?? false,
      sortOrder: json['sort_order'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      deletedAt: json['deleted_at'] != null
          ? DateTime.parse(json['deleted_at'])
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'code': code,
      'name_th': nameTh,
      'name_en': nameEn,
      'description': description,
      'is_telemedicine_prohibited': isTelemedicineProhibited,
      'sort_order': sortOrder,
      'is_active': isActive,
    };
  }

  DangerousDrugSubcategory copyWith({
    String? id,
    String? code,
    String? nameTh,
    String? nameEn,
    String? description,
    bool? isTelemedicineProhibited,
    int? sortOrder,
    bool? isActive,
    DateTime? deletedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DangerousDrugSubcategory(
      id: id ?? this.id,
      code: code ?? this.code,
      nameTh: nameTh ?? this.nameTh,
      nameEn: nameEn ?? this.nameEn,
      description: description ?? this.description,
      isTelemedicineProhibited: isTelemedicineProhibited ?? this.isTelemedicineProhibited,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
      deletedAt: deletedAt ?? this.deletedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Model สำหรับระดับความเสี่ยง Custom Medications (custom_risk_levels)
class CustomRiskLevel {
  final String id;
  final String code;
  final String nameTh;
  final String? nameEn;
  final String? description;
  final bool isTelemedicineProhibited;
  final int sortOrder;
  final bool isActive;
  final DateTime? deletedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CustomRiskLevel({
    required this.id,
    required this.code,
    required this.nameTh,
    this.nameEn,
    this.description,
    this.isTelemedicineProhibited = false,
    this.sortOrder = 0,
    this.isActive = true,
    this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CustomRiskLevel.fromJson(Map<String, dynamic> json) {
    return CustomRiskLevel(
      id: json['id'] as String,
      code: json['code'] as String,
      nameTh: json['name_th'] as String,
      nameEn: json['name_en'] as String?,
      description: json['description'] as String?,
      isTelemedicineProhibited: json['is_telemedicine_prohibited'] as bool? ?? false,
      sortOrder: json['sort_order'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      deletedAt: json['deleted_at'] != null
          ? DateTime.parse(json['deleted_at'])
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'code': code,
      'name_th': nameTh,
      'name_en': nameEn,
      'description': description,
      'is_telemedicine_prohibited': isTelemedicineProhibited,
      'sort_order': sortOrder,
      'is_active': isActive,
    };
  }

  CustomRiskLevel copyWith({
    String? id,
    String? code,
    String? nameTh,
    String? nameEn,
    String? description,
    bool? isTelemedicineProhibited,
    int? sortOrder,
    bool? isActive,
    DateTime? deletedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CustomRiskLevel(
      id: id ?? this.id,
      code: code ?? this.code,
      nameTh: nameTh ?? this.nameTh,
      nameEn: nameEn ?? this.nameEn,
      description: description ?? this.description,
      isTelemedicineProhibited: isTelemedicineProhibited ?? this.isTelemedicineProhibited,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
      deletedAt: deletedAt ?? this.deletedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Model สำหรับ Audit Log การ Override การจำแนกยา
class MedicationRiskOverrideLog {
  final String id;
  final String medicationId;
  final String? oldFdaRiskStatus;
  final String? newFdaRiskStatus;
  final String? oldSubCategory;
  final String? newSubCategory;
  final String? reason;
  final String? overriddenBy;
  final DateTime createdAt;

  const MedicationRiskOverrideLog({
    required this.id,
    required this.medicationId,
    this.oldFdaRiskStatus,
    this.newFdaRiskStatus,
    this.oldSubCategory,
    this.newSubCategory,
    this.reason,
    this.overriddenBy,
    required this.createdAt,
  });

  factory MedicationRiskOverrideLog.fromJson(Map<String, dynamic> json) {
    return MedicationRiskOverrideLog(
      id: json['id'] as String,
      medicationId: json['medication_id'] as String,
      oldFdaRiskStatus: json['old_fda_risk_status'] as String?,
      newFdaRiskStatus: json['new_fda_risk_status'] as String?,
      oldSubCategory: json['old_sub_category'] as String?,
      newSubCategory: json['new_sub_category'] as String?,
      reason: json['reason'] as String?,
      overriddenBy: json['overridden_by'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'medication_id': medicationId,
      'old_fda_risk_status': oldFdaRiskStatus,
      'new_fda_risk_status': newFdaRiskStatus,
      'old_sub_category': oldSubCategory,
      'new_sub_category': newSubCategory,
      'reason': reason,
      'overridden_by': overriddenBy,
    };
  }
}

/// Model สำหรับสรุปยาที่ต้องตรวจสอบ (ใช้ใน Tab รายงาน)
class MedicationRiskSummary {
  final String medicationId;
  final String tradeName;
  final String? genericName;
  final String? fdaRiskStatus;
  final String? dangerousSubCategory;
  final bool isCustom;
  final String? customRiskLevel;

  const MedicationRiskSummary({
    required this.medicationId,
    required this.tradeName,
    this.genericName,
    this.fdaRiskStatus,
    this.dangerousSubCategory,
    this.isCustom = false,
    this.customRiskLevel,
  });

  factory MedicationRiskSummary.fromJson(Map<String, dynamic> json) {
    return MedicationRiskSummary(
      medicationId: json['medication_id'] as String,
      tradeName: json['trade_name'] as String,
      genericName: json['generic_name'] as String?,
      fdaRiskStatus: json['fda_risk_status'] as String?,
      dangerousSubCategory: json['dangerous_sub_category'] as String?,
      isCustom: json['is_custom'] as bool? ?? false,
      customRiskLevel: json['custom_risk_level'] as String?,
    );
  }
}
