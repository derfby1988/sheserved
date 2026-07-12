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

// ════════════════════════════════════════════════
// Drug Risk Override Models (v3.0)
// ════════════════════════════════════════════════

/// Scope ของ Override: Personal (อาชีพอิสระ) หรือ Organization (สังกัดองค์กร)
enum DrugRiskOverrideScope { personal, organization }

/// Active Override record (1 ยา × 1 scope = 1 record)
class DrugRiskOverride {
  final String id;
  final String? userId;          // Personal scope
  final String? professionId;    // Organization scope
  final String medicationId;
  final String? overrideFdaRiskStatus;
  final String? overrideSubCategory;
  final String? overrideCustomRiskCode;
  final bool? overrideIsTelemedicineProhibited;
  final String? overrideNotes;
  final String? lastModifiedBy;  // nullable — ON DELETE SET NULL
  final DateTime lastModifiedAt;
  final String? createdBy;       // nullable — ON DELETE SET NULL
  final DateTime createdAt;

  const DrugRiskOverride({
    required this.id,
    this.userId,
    this.professionId,
    required this.medicationId,
    this.overrideFdaRiskStatus,
    this.overrideSubCategory,
    this.overrideCustomRiskCode,
    this.overrideIsTelemedicineProhibited,
    this.overrideNotes,
    this.lastModifiedBy,
    required this.lastModifiedAt,
    this.createdBy,
    required this.createdAt,
  });

  DrugRiskOverrideScope get scope =>
      userId != null ? DrugRiskOverrideScope.personal : DrugRiskOverrideScope.organization;

  bool get hasAnyOverride =>
      overrideFdaRiskStatus != null ||
      overrideSubCategory != null ||
      overrideCustomRiskCode != null ||
      overrideIsTelemedicineProhibited != null;

  factory DrugRiskOverride.fromJson(Map<String, dynamic> json) {
    return DrugRiskOverride(
      id: json['id'] as String,
      userId: json['user_id'] as String?,
      professionId: json['profession_id'] as String?,
      medicationId: json['medication_id'] as String,
      overrideFdaRiskStatus: json['override_fda_risk_status'] as String?,
      overrideSubCategory: json['override_sub_category'] as String?,
      overrideCustomRiskCode: json['override_custom_risk_code'] as String?,
      overrideIsTelemedicineProhibited:
          json['override_is_telemedicine_prohibited'] as bool?,
      overrideNotes: json['override_notes'] as String?,
      lastModifiedBy: json['last_modified_by'] as String?,
      lastModifiedAt: json['last_modified_at'] != null
          ? DateTime.parse(json['last_modified_at'])
          : DateTime.now(),
      createdBy: json['created_by'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (userId != null) 'user_id': userId,
      if (professionId != null) 'profession_id': professionId,
      'medication_id': medicationId,
      'override_fda_risk_status': overrideFdaRiskStatus,
      'override_sub_category': overrideSubCategory,
      'override_custom_risk_code': overrideCustomRiskCode,
      'override_is_telemedicine_prohibited': overrideIsTelemedicineProhibited,
      'override_notes': overrideNotes,
      'last_modified_by': lastModifiedBy,
      'created_by': createdBy,
    };
  }

  DrugRiskOverride copyWith({
    String? id,
    String? userId,
    String? professionId,
    String? medicationId,
    String? overrideFdaRiskStatus,
    String? overrideSubCategory,
    String? overrideCustomRiskCode,
    bool? overrideIsTelemedicineProhibited,
    String? overrideNotes,
    String? lastModifiedBy,
    DateTime? lastModifiedAt,
    String? createdBy,
    DateTime? createdAt,
  }) {
    return DrugRiskOverride(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      professionId: professionId ?? this.professionId,
      medicationId: medicationId ?? this.medicationId,
      overrideFdaRiskStatus: overrideFdaRiskStatus ?? this.overrideFdaRiskStatus,
      overrideSubCategory: overrideSubCategory ?? this.overrideSubCategory,
      overrideCustomRiskCode: overrideCustomRiskCode ?? this.overrideCustomRiskCode,
      overrideIsTelemedicineProhibited:
          overrideIsTelemedicineProhibited ?? this.overrideIsTelemedicineProhibited,
      overrideNotes: overrideNotes ?? this.overrideNotes,
      lastModifiedBy: lastModifiedBy ?? this.lastModifiedBy,
      lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// Version History record (Audit Trail สำหรับทุก scope)
class DrugRiskOverrideHistory {
  final String id;
  final String? overrideId;
  final String? professionId;
  final String? userId;
  final String medicationId;
  final String? fdaRiskStatusBefore;
  final String? fdaRiskStatusAfter;
  final String? subCategoryBefore;
  final String? subCategoryAfter;
  final String? customRiskCodeBefore;
  final String? customRiskCodeAfter;
  final bool? isTelemedicineProhibitedBefore;
  final bool? isTelemedicineProhibitedAfter;
  final String? notesBefore;
  final String? notesAfter;
  final String action; // 'create' | 'update' | 'delete'
  final String? changedBy;
  final String changedByName; // Text Snapshot — ชื่อจริง ณ เวลานั้น
  final DateTime changedAt;
  final String? changeReason;

  const DrugRiskOverrideHistory({
    required this.id,
    this.overrideId,
    this.professionId,
    this.userId,
    required this.medicationId,
    this.fdaRiskStatusBefore,
    this.fdaRiskStatusAfter,
    this.subCategoryBefore,
    this.subCategoryAfter,
    this.customRiskCodeBefore,
    this.customRiskCodeAfter,
    this.isTelemedicineProhibitedBefore,
    this.isTelemedicineProhibitedAfter,
    this.notesBefore,
    this.notesAfter,
    required this.action,
    this.changedBy,
    required this.changedByName,
    required this.changedAt,
    this.changeReason,
  });

  factory DrugRiskOverrideHistory.fromJson(Map<String, dynamic> json) {
    return DrugRiskOverrideHistory(
      id: json['id'] as String,
      overrideId: json['override_id'] as String?,
      professionId: json['profession_id'] as String?,
      userId: json['user_id'] as String?,
      medicationId: json['medication_id'] as String,
      fdaRiskStatusBefore: json['fda_risk_status_before'] as String?,
      fdaRiskStatusAfter: json['fda_risk_status_after'] as String?,
      subCategoryBefore: json['sub_category_before'] as String?,
      subCategoryAfter: json['sub_category_after'] as String?,
      customRiskCodeBefore: json['custom_risk_code_before'] as String?,
      customRiskCodeAfter: json['custom_risk_code_after'] as String?,
      isTelemedicineProhibitedBefore:
          json['is_telemedicine_prohibited_before'] as bool?,
      isTelemedicineProhibitedAfter:
          json['is_telemedicine_prohibited_after'] as bool?,
      notesBefore: json['notes_before'] as String?,
      notesAfter: json['notes_after'] as String?,
      action: json['action'] as String,
      changedBy: json['changed_by'] as String?,
      changedByName: json['changed_by_name'] as String? ?? 'Unknown',
      changedAt: json['changed_at'] != null
          ? DateTime.parse(json['changed_at'])
          : DateTime.now(),
      changeReason: json['change_reason'] as String?,
    );
  }
}

/// ผลลัพธ์จาก RPC resolve_effective_modifier
class EffectiveModifierInfo {
  final String? id;
  final String name;
  final String status; // 'active' | 'fallback_history' | 'fallback_system' | 'no_override'
  final String? snapshotName;
  final DateTime? modifiedAt;

  const EffectiveModifierInfo({
    this.id,
    required this.name,
    required this.status,
    this.snapshotName,
    this.modifiedAt,
  });

  bool get isActive => status == 'active';
  bool get isFallback => status == 'fallback_history' || status == 'fallback_system';
  bool get hasNoOverride => status == 'no_override';

  factory EffectiveModifierInfo.fromJson(Map<String, dynamic> json) {
    return EffectiveModifierInfo(
      id: json['id'] as String?,
      name: json['name'] as String? ?? 'System Admin',
      status: json['status'] as String? ?? 'fallback_system',
      snapshotName: json['snapshot_name'] as String?,
      modifiedAt: json['modified_at'] != null
          ? DateTime.tryParse(json['modified_at'].toString())
          : null,
    );
  }
}
